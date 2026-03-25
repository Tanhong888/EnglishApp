from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

import app.db.init_db as init_db_module
import app.db.session as db_session
import app.main as main_module
import app.tasks.audio_tasks as audio_tasks_module
from app.db.models import Article, ArticleContent, ArticleSource
from app.main import app


@pytest.fixture
def client(tmp_path: Path) -> TestClient:
    test_db_path = tmp_path / 'englishapp-test.db'
    test_url = f"sqlite:///{test_db_path.as_posix()}"
    test_engine = create_engine(test_url, echo=False, future=True, connect_args={'check_same_thread': False})
    test_session_local = sessionmaker(bind=test_engine, autoflush=False, autocommit=False, expire_on_commit=False)

    original_engine = db_session.engine
    original_session_local = db_session.SessionLocal
    original_init_engine = init_db_module.engine
    original_main_session_local = main_module.SessionLocal
    original_audio_session_local = audio_tasks_module.SessionLocal

    db_session.engine = test_engine
    db_session.SessionLocal = test_session_local
    init_db_module.engine = test_engine
    main_module.SessionLocal = test_session_local
    audio_tasks_module.SessionLocal = test_session_local

    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        db_session.engine = original_engine
        db_session.SessionLocal = original_session_local
        init_db_module.engine = original_init_engine
        main_module.SessionLocal = original_main_session_local
        audio_tasks_module.SessionLocal = original_audio_session_local
        test_engine.dispose()


def make_headers(access_token: str) -> dict:
    return {'Authorization': f'Bearer {access_token}'}


def login_and_get_tokens(client: TestClient, email: str = 'demo@englishapp.dev', password: str = 'Passw0rd!') -> dict:
    response = client.post('/api/v1/auth/login', json={'email': email, 'password': password})
    assert response.status_code == 200
    return response.json()['data']


def register_and_login(client: TestClient) -> tuple[str, dict]:
    email = f"user_{uuid4().hex[:8]}@example.com"
    password = 'Passw0rd!'

    register_response = client.post(
        '/api/v1/auth/register',
        json={'email': email, 'password': password, 'nickname': 'new_user', 'target': 'cet4'},
    )
    assert register_response.status_code == 200

    tokens = login_and_get_tokens(client, email=email, password=password)
    return email, tokens


def test_healthcheck(client: TestClient) -> None:
    response = client.get('/health')
    assert response.status_code == 200
    payload = response.json()
    assert payload['code'] == 0
    assert payload['data']['status'] == 'ok'


def test_security_headers_and_request_id(client: TestClient) -> None:
    request_id = 'req-test-123'
    response = client.get('/health', headers={'X-Request-ID': request_id})
    assert response.status_code == 200

    assert response.headers['X-Request-ID'] == request_id
    assert response.headers['X-Content-Type-Options'] == 'nosniff'
    assert response.headers['X-Frame-Options'] == 'DENY'
    assert response.headers['Referrer-Policy'] == 'strict-origin-when-cross-origin'
    assert response.headers['Permissions-Policy'] == 'camera=(), microphone=(), geolocation=()'


def test_unhandled_exception_shape_contains_trace_id(client: TestClient) -> None:
    from app.db.session import get_db

    def broken_db():
        raise RuntimeError('forced-db-error')
        yield

    app.dependency_overrides[get_db] = broken_db
    try:
        with TestClient(app, raise_server_exceptions=False) as safe_client:
            response = safe_client.get('/api/v1/articles', headers={'X-Request-ID': 'req-force-500'})
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 500
    payload = response.json()
    assert payload['message'] == 'internal_server_error'
    assert payload['detail'] == 'internal_server_error'
    assert payload['trace_id'] == 'req-force-500'


def test_articles_pagination_limit(client: TestClient) -> None:
    response = client.get('/api/v1/articles', params={'size': 100})
    assert response.status_code == 422


def test_articles_list_success(client: TestClient) -> None:
    response = client.get('/api/v1/articles', params={'page': 1, 'size': 20, 'sort': 'recommended'})
    assert response.status_code == 200
    payload = response.json()
    assert payload['code'] == 0
    assert 'items' in payload['data']


def test_personal_routes_require_auth(client: TestClient) -> None:
    me_response = client.get('/api/v1/me/stats')
    favorite_response = client.post('/api/v1/articles/1/favorite')
    vocab_response = client.post('/api/v1/vocab', json={'word_id': 1, 'source_article_id': 1})
    recent_response = client.get('/api/v1/reading/recent')

    assert me_response.status_code == 401
    assert favorite_response.status_code == 401
    assert vocab_response.status_code == 401
    assert recent_response.status_code == 401


def test_me_stats_completion_rate_uses_user_progress(client: TestClient) -> None:
    _, tokens = register_and_login(client)
    headers = make_headers(tokens['access_token'])

    first_progress = client.post(
        '/api/v1/reading/progress',
        json={'article_id': 1, 'paragraph_index': 1},
        headers=headers,
    )
    assert first_progress.status_code == 200
    assert first_progress.json()['data']['progress_percent'] == 25.0
    assert first_progress.json()['data']['completed'] is False

    stats_mid = client.get('/api/v1/me/stats', headers=headers)
    assert stats_mid.status_code == 200
    assert stats_mid.json()['data']['read_articles'] == 1
    assert stats_mid.json()['data']['completion_rate'] == 0.0

    final_progress = client.post(
        '/api/v1/reading/progress',
        json={'article_id': 1, 'paragraph_index': 4},
        headers=headers,
    )
    assert final_progress.status_code == 200
    assert final_progress.json()['data']['progress_percent'] == 100.0
    assert final_progress.json()['data']['completed'] is True

    stats_done = client.get('/api/v1/me/stats', headers=headers)
    assert stats_done.status_code == 200
    assert stats_done.json()['data']['completion_rate'] == 1.0


def test_favorite_idempotent_flow(client: TestClient) -> None:
    tokens = login_and_get_tokens(client)
    headers = make_headers(tokens['access_token'])

    response_1 = client.post('/api/v1/articles/1/favorite', headers=headers)
    response_2 = client.post('/api/v1/articles/1/favorite', headers=headers)
    response_3 = client.delete('/api/v1/articles/1/favorite', headers=headers)

    assert response_1.status_code == 200
    assert response_2.status_code == 200
    assert response_3.status_code == 200

    assert response_1.json()['data']['idempotent'] is True
    assert response_2.json()['data']['idempotent'] is True


def test_vocab_multi_source(client: TestClient) -> None:
    tokens = login_and_get_tokens(client)
    headers = make_headers(tokens['access_token'])

    response_1 = client.post('/api/v1/vocab', json={'word_id': 1, 'source_article_id': 1}, headers=headers)
    response_2 = client.post('/api/v1/vocab', json={'word_id': 1, 'source_article_id': 2}, headers=headers)

    assert response_1.status_code == 200
    assert response_2.status_code == 200
    assert response_1.json()['data']['word_id'] == 1
    assert response_2.json()['data']['word_id'] == 1


def test_auth_lifecycle_and_users_me(client: TestClient) -> None:
    tokens = login_and_get_tokens(client)

    me_response = client.get('/api/v1/users/me', headers=make_headers(tokens['access_token']))
    assert me_response.status_code == 200
    assert me_response.json()['data']['email'] == 'demo@englishapp.dev'

    refresh_response = client.post('/api/v1/auth/refresh', json={'refresh_token': tokens['refresh_token']})
    assert refresh_response.status_code == 200

    new_refresh_token = refresh_response.json()['data']['refresh_token']
    logout_response = client.post('/api/v1/auth/logout', json={'refresh_token': new_refresh_token})
    assert logout_response.status_code == 200

    reused_response = client.post('/api/v1/auth/refresh', json={'refresh_token': new_refresh_token})
    assert reused_response.status_code == 401


def test_update_current_user_target(client: TestClient) -> None:
    tokens = login_and_get_tokens(client)
    headers = make_headers(tokens['access_token'])

    update_response = client.patch('/api/v1/users/me', headers=headers, json={'target': 'cet6'})
    assert update_response.status_code == 200
    assert update_response.json()['data']['target'] == 'cet6'

    me_response = client.get('/api/v1/users/me', headers=headers)
    assert me_response.status_code == 200
    assert me_response.json()['data']['target'] == 'cet6'



def test_account_soft_delete_flow(client: TestClient) -> None:
    email, tokens = register_and_login(client)
    headers = make_headers(tokens['access_token'])

    delete_response = client.request('DELETE', '/api/v1/users/me', headers=headers, json={'mode': 'soft'})
    assert delete_response.status_code == 200
    assert delete_response.json()['data']['mode'] == 'soft'

    relogin_response = client.post('/api/v1/auth/login', json={'email': email, 'password': 'Passw0rd!'})
    assert relogin_response.status_code == 403

    refresh_response = client.post('/api/v1/auth/refresh', json={'refresh_token': tokens['refresh_token']})
    assert refresh_response.status_code == 401


def test_account_hard_delete_flow(client: TestClient) -> None:
    email, tokens = register_and_login(client)
    headers = make_headers(tokens['access_token'])

    delete_response = client.request('DELETE', '/api/v1/users/me', headers=headers, json={'mode': 'hard'})
    assert delete_response.status_code == 200
    assert delete_response.json()['data']['mode'] == 'hard'

    relogin_response = client.post('/api/v1/auth/login', json={'email': email, 'password': 'Passw0rd!'})
    assert relogin_response.status_code == 401

    me_response = client.get('/api/v1/users/me', headers=headers)
    assert me_response.status_code == 401


def test_demo_articles_have_full_paragraphs(client: TestClient) -> None:
    first_article = client.get('/api/v1/articles/1')
    assert first_article.status_code == 200
    first_paragraphs = first_article.json()['data']['paragraphs']
    assert len(first_paragraphs) >= 4
    assert all(item['text'] for item in first_paragraphs)

    third_article = client.get('/api/v1/articles/3')
    assert third_article.status_code == 200
    third_paragraphs = third_article.json()['data']['paragraphs']
    assert len(third_paragraphs) >= 4
    assert all(item['text'] for item in third_paragraphs)



def test_sentence_analysis_endpoint(client: TestClient) -> None:
    response = client.get('/api/v1/articles/1/sentence-analyses')
    assert response.status_code == 200
    data = response.json()['data']
    assert data['article_id'] == 1
    assert isinstance(data['items'], list)
    assert len(data['items']) >= 1

    first = data['items'][0]
    assert 'sentence_id' in first
    assert first['sentence']
    assert first['translation']
    assert first['structure']


def test_sentence_analysis_article_not_found(client: TestClient) -> None:
    response = client.get('/api/v1/articles/99999/sentence-analyses')
    assert response.status_code == 404



def test_quiz_not_found(client: TestClient) -> None:
    quiz_response = client.get('/api/v1/articles/99999/quiz')
    assert quiz_response.status_code == 404

    submit_response = client.post(
        '/api/v1/quiz/submit',
        json={
            'article_id': 99999,
            'answers': [],
        },
    )
    assert submit_response.status_code == 404


def test_quiz_flow_endpoints(client: TestClient) -> None:
    quiz_response = client.get('/api/v1/articles/1/quiz')
    assert quiz_response.status_code == 200

    questions = quiz_response.json()['data']['questions']
    assert len(questions) == 3

    submit_response = client.post(
        '/api/v1/quiz/submit',
        json={
            'article_id': 1,
            'answers': [],
        },
    )
    assert submit_response.status_code == 200

    attempt_id = submit_response.json()['data']['attempt_id']
    attempt_response = client.get(f'/api/v1/quiz/attempts/{attempt_id}')
    assert attempt_response.status_code == 200

    attempt_data = attempt_response.json()['data']
    assert attempt_data['attempt_id'] == attempt_id
    assert attempt_data['total_count'] == 3
    assert attempt_data['correct_count'] == 0
    assert attempt_data['accuracy'] == 0.0
    assert attempt_data['wrong_items'] == [1, 2, 3]


def test_favorite_status_endpoint(client: TestClient) -> None:
    tokens = login_and_get_tokens(client)
    headers = make_headers(tokens['access_token'])

    status_before = client.get('/api/v1/articles/1/favorite-status', headers=headers)
    assert status_before.status_code == 200

    client.delete('/api/v1/articles/1/favorite', headers=headers)
    status_after_unfavorite = client.get('/api/v1/articles/1/favorite-status', headers=headers)
    assert status_after_unfavorite.status_code == 200
    assert status_after_unfavorite.json()['data']['favorite'] is False

    client.post('/api/v1/articles/1/favorite', headers=headers)
    status_after_favorite = client.get('/api/v1/articles/1/favorite-status', headers=headers)
    assert status_after_favorite.status_code == 200
    assert status_after_favorite.json()['data']['favorite'] is True


def test_word_lookup_endpoint(client: TestClient) -> None:
    response = client.get('/api/v1/words/consolidate')
    assert response.status_code == 200
    data = response.json()['data']
    assert data['lemma'] == 'consolidate'
    assert 'meaning_cn' in data


def test_word_lookup_not_found(client: TestClient) -> None:
    response = client.get('/api/v1/words/nonexistentwordxyz')
    assert response.status_code == 404


def test_vocab_word_mastered_update_by_source(client: TestClient) -> None:
    tokens = login_and_get_tokens(client)
    headers = make_headers(tokens['access_token'])

    reset_response = client.patch('/api/v1/vocab/word/1', json={'mastered': False}, headers=headers)
    assert reset_response.status_code == 200

    source_update = client.patch(
        '/api/v1/vocab/word/1',
        json={'mastered': True, 'source_article_id': 1},
        headers=headers,
    )
    assert source_update.status_code == 200
    assert source_update.json()['data']['updated_count'] == 1

    source_1_vocab = client.get('/api/v1/me/vocab', params={'source_article_id': 1}, headers=headers)
    source_2_vocab = client.get('/api/v1/me/vocab', params={'source_article_id': 2}, headers=headers)
    all_vocab = client.get('/api/v1/me/vocab', headers=headers)

    assert source_1_vocab.status_code == 200
    assert source_2_vocab.status_code == 200
    assert all_vocab.status_code == 200

    source_1_items = source_1_vocab.json()['data']['items']
    source_2_items = source_2_vocab.json()['data']['items']
    all_items = all_vocab.json()['data']['items']

    word_1_from_source_1 = next(item for item in source_1_items if item['word_id'] == 1)
    word_1_from_source_2 = next(item for item in source_2_items if item['word_id'] == 1)
    word_1_aggregated = next(item for item in all_items if item['word_id'] == 1)

    assert word_1_from_source_1['mastered'] is True
    assert word_1_from_source_2['mastered'] is False
    assert word_1_aggregated['mastered'] is False



def test_me_vocab_list_includes_word_meta_and_latest_entry_id(client: TestClient) -> None:
    tokens = login_and_get_tokens(client)
    headers = make_headers(tokens['access_token'])

    response = client.get('/api/v1/me/vocab', headers=headers)
    assert response.status_code == 200

    items = response.json()['data']['items']
    consolidate = next(item for item in items if item['word_id'] == 1)

    assert consolidate['latest_entry_id'] >= 1
    assert consolidate['lemma'] == 'consolidate'
    assert consolidate['phonetic'] == 'kənˈsɑːlɪdeɪt'
    assert consolidate['pos'] == 'vt.'
    assert consolidate['meaning_cn'] == '巩固'
    assert consolidate['source_count'] == 2



def test_me_vocab_search_filters_by_lemma_and_meaning(client: TestClient) -> None:
    tokens = login_and_get_tokens(client)
    headers = make_headers(tokens['access_token'])

    by_lemma = client.get('/api/v1/me/vocab', params={'q': 'consolidate'}, headers=headers)
    assert by_lemma.status_code == 200
    lemma_items = by_lemma.json()['data']['items']
    assert len(lemma_items) == 1
    assert lemma_items[0]['lemma'] == 'consolidate'

    by_meaning = client.get('/api/v1/me/vocab', params={'q': '公平'}, headers=headers)
    assert by_meaning.status_code == 200
    meaning_items = by_meaning.json()['data']['items']
    assert len(meaning_items) == 1
    assert meaning_items[0]['lemma'] == 'equity'



def test_me_vocab_entry_detail_contract(client: TestClient) -> None:
    tokens = login_and_get_tokens(client)
    headers = make_headers(tokens['access_token'])

    vocab_list_response = client.get('/api/v1/me/vocab', headers=headers)
    assert vocab_list_response.status_code == 200
    entry_id = next(item['latest_entry_id'] for item in vocab_list_response.json()['data']['items'] if item['word_id'] == 1)

    detail_response = client.get(f'/api/v1/me/vocab/entries/{entry_id}', headers=headers)
    assert detail_response.status_code == 200

    data = detail_response.json()['data']
    assert data['entry_id'] == entry_id
    assert data['word_id'] == 1
    assert data['lemma'] == 'consolidate'
    assert data['phonetic'] == 'kənˈsɑːlɪdeɪt'
    assert data['pos'] == 'vt.'
    assert data['meaning_cn'] == '巩固'
    assert data['source_count'] == 2
    assert data['mastered'] is False
    assert len(data['sources']) == 2
    assert {source['source_article_id'] for source in data['sources']} == {1, 2}
    assert all(source['source_article_title'] for source in data['sources'])



def test_article_audio_failed_contract(client: TestClient) -> None:
    response = client.get('/api/v1/articles/3/audio')
    assert response.status_code == 200

    data = response.json()['data']
    assert data['status'] == 'failed'
    assert data['article_audio_url'] is None
    assert data['retry_hint'] == '稍后重试'


def test_me_favorites_pagination_contract(client: TestClient) -> None:
    tokens = login_and_get_tokens(client)
    headers = make_headers(tokens['access_token'])

    client.post('/api/v1/articles/1/favorite', headers=headers)
    client.post('/api/v1/articles/2/favorite', headers=headers)
    client.post('/api/v1/articles/3/favorite', headers=headers)

    page_1 = client.get('/api/v1/me/favorites', params={'page': 1, 'size': 1}, headers=headers)
    page_2 = client.get('/api/v1/me/favorites', params={'page': 2, 'size': 1}, headers=headers)

    assert page_1.status_code == 200
    assert page_2.status_code == 200

    data_1 = page_1.json()['data']
    data_2 = page_2.json()['data']

    assert data_1['page'] == 1
    assert data_1['size'] == 1
    assert data_1['total'] >= 2
    assert data_1['has_next'] is True
    assert len(data_1['items']) == 1

    assert data_2['page'] == 2
    assert data_2['size'] == 1
    assert len(data_2['items']) == 1



def test_learning_records_time_filters(client: TestClient) -> None:
    tokens = login_and_get_tokens(client)
    headers = make_headers(tokens['access_token'])

    progress_response = client.post(
        '/api/v1/reading/progress',
        json={'article_id': 1, 'paragraph_index': 1},
        headers=headers,
    )
    assert progress_response.status_code == 200

    all_response = client.get('/api/v1/me/learning-records', headers=headers)
    assert all_response.status_code == 200
    all_data = all_response.json()['data']
    all_items = all_data['items']
    assert all_data['page'] == 1
    assert all_data['size'] == 20
    assert 'total' in all_data
    assert 'has_next' in all_data
    assert isinstance(all_items, list)
    assert len(all_items) >= 1

    recent_response = client.get('/api/v1/me/learning-records', params={'days': 1}, headers=headers)
    assert recent_response.status_code == 200
    recent_data = recent_response.json()['data']
    recent_items = recent_data['items']
    assert recent_data['page'] == 1
    assert isinstance(recent_items, list)
    assert len(recent_items) >= 1

    future_response = client.get('/api/v1/me/learning-records', params={'date_from': '2999-01-01'}, headers=headers)
    assert future_response.status_code == 200
    future_data = future_response.json()['data']
    assert future_data['items'] == []
    assert future_data['total'] == 0


def test_article_audio_ready_contract(client: TestClient) -> None:
    response = client.get('/api/v1/articles/2/audio')
    assert response.status_code == 200

    detail_response = client.get('/api/v1/articles/2')
    assert detail_response.status_code == 200

    data = response.json()['data']
    assert data['status'] == 'ready'
    assert isinstance(data['article_audio_url'], str)
    assert data['article_audio_url'].startswith('https://')

    timestamps = data['paragraph_timestamps']
    paragraphs = detail_response.json()['data']['paragraphs']

    assert isinstance(timestamps, list)
    assert len(timestamps) >= 1
    assert len(timestamps) == len(paragraphs)

    previous_end = -1.0
    for item in timestamps:
        assert 'index' in item
        assert 'start' in item
        assert 'end' in item
        assert item['start'] >= 0
        assert item['end'] > item['start']
        assert item['start'] >= previous_end
        previous_end = item['end']




def test_word_pronunciation_endpoint(client: TestClient) -> None:
    response = client.get('/api/v1/words/consolidate/pronunciation')
    assert response.status_code == 200
    data = response.json()['data']
    assert data['lemma'] == 'consolidate'
    assert data['provider'] == 'youdao'
    assert data['audio_url'].startswith('https://dict.youdao.com/dictvoice')




def test_analytics_track_and_list(client: TestClient) -> None:
    create_response = client.post(
        '/api/v1/analytics/events',
        json={
            'event_name': 'word_tap',
            'user_id': 1,
            'article_id': 2,
            'word': 'Consolidate',
            'context': {'from': 'article_detail', 'position': 3},
        },
    )
    assert create_response.status_code == 200
    create_data = create_response.json()['data']
    assert create_data['event_name'] == 'word_tap'
    event_id = create_data['event_id']

    list_response = client.get('/api/v1/analytics/events', params={'event_name': 'word_tap', 'limit': 10})
    assert list_response.status_code == 200
    items = list_response.json()['data']['items']
    assert isinstance(items, list)
    assert any(item['event_id'] == event_id for item in items)

    summary_response = client.get('/api/v1/analytics/dashboard/summary', params={'days': 7})
    assert summary_response.status_code == 200
    summary_data = summary_response.json()['data']
    assert summary_data['window_days'] == 7
    assert summary_data['event_total'] >= 1
    assert summary_data['dau'] >= 1
    assert summary_data['event_counts']['word_tap'] >= 1
    assert isinstance(summary_data['timeline'], list)


def test_analytics_me_summary_scoped_by_current_user(client: TestClient) -> None:
    demo_tokens = login_and_get_tokens(client)
    demo_headers = make_headers(demo_tokens['access_token'])
    demo_me = client.get('/api/v1/users/me', headers=demo_headers)
    assert demo_me.status_code == 200
    demo_user_id = demo_me.json()['data']['id']

    _, other_tokens = register_and_login(client)
    other_headers = make_headers(other_tokens['access_token'])
    other_me = client.get('/api/v1/users/me', headers=other_headers)
    assert other_me.status_code == 200
    other_user_id = other_me.json()['data']['id']

    create_demo = client.post(
        '/api/v1/analytics/events',
        json={
            'event_name': 'user_scope_probe_u1',
            'user_id': demo_user_id,
            'article_id': 1,
            'context': {'source': 'scope_test'},
        },
    )
    assert create_demo.status_code == 200

    create_other = client.post(
        '/api/v1/analytics/events',
        json={
            'event_name': 'user_scope_probe_u2',
            'user_id': other_user_id,
            'article_id': 1,
            'context': {'source': 'scope_test'},
        },
    )
    assert create_other.status_code == 200

    unauthorized = client.get('/api/v1/analytics/dashboard/me-summary', params={'days': 7})
    assert unauthorized.status_code == 401

    demo_summary = client.get('/api/v1/analytics/dashboard/me-summary', params={'days': 7}, headers=demo_headers)
    assert demo_summary.status_code == 200
    demo_data = demo_summary.json()['data']
    assert demo_data['event_counts'].get('user_scope_probe_u1', 0) >= 1
    assert demo_data['event_counts'].get('user_scope_probe_u2', 0) == 0

    other_summary = client.get('/api/v1/analytics/dashboard/me-summary', params={'days': 7}, headers=other_headers)
    assert other_summary.status_code == 200
    other_data = other_summary.json()['data']
    assert other_data['event_counts'].get('user_scope_probe_u2', 0) >= 1
    assert other_data['event_counts'].get('user_scope_probe_u1', 0) == 0


def test_analytics_track_rate_limit(client: TestClient) -> None:
    import importlib

    analytics_module = importlib.import_module('app.modules.analytics.router')
    original_limit = analytics_module.ANALYTICS_TRACK_LIMIT_PER_MINUTE

    try:
        analytics_module.ANALYTICS_TRACK_LIMIT_PER_MINUTE = 1
        analytics_module.reset_analytics_rate_limit_state_for_test()

        first = client.post(
            '/api/v1/analytics/events',
            json={
                'event_name': 'rate_limit_probe',
                'user_id': 9999,
                'article_id': 1,
                'context': {'source': 'rate_limit_test'},
            },
        )
        assert first.status_code == 200

        second = client.post(
            '/api/v1/analytics/events',
            json={
                'event_name': 'rate_limit_probe',
                'user_id': 9999,
                'article_id': 1,
                'context': {'source': 'rate_limit_test'},
            },
        )
        assert second.status_code == 429
    finally:
        analytics_module.ANALYTICS_TRACK_LIMIT_PER_MINUTE = original_limit
        analytics_module.reset_analytics_rate_limit_state_for_test()


def test_auth_login_rate_limit(client: TestClient) -> None:
    import importlib

    auth_module = importlib.import_module('app.modules.auth.router')
    original_limit = auth_module.AUTH_LOGIN_LIMIT_PER_MINUTE

    try:
        auth_module.AUTH_LOGIN_LIMIT_PER_MINUTE = 1
        auth_module.reset_auth_login_rate_limit_state_for_test()

        first = client.post('/api/v1/auth/login', json={'email': 'demo@englishapp.dev', 'password': 'Passw0rd!'})
        assert first.status_code == 200

        second = client.post('/api/v1/auth/login', json={'email': 'demo@englishapp.dev', 'password': 'Passw0rd!'})
        assert second.status_code == 429
    finally:
        auth_module.AUTH_LOGIN_LIMIT_PER_MINUTE = original_limit
        auth_module.reset_auth_login_rate_limit_state_for_test()



def test_word_lookup_rate_limit(client: TestClient) -> None:
    import importlib

    words_module = importlib.import_module('app.modules.words.router')
    original_limit = words_module.WORD_LOOKUP_LIMIT_PER_MINUTE

    try:
        words_module.WORD_LOOKUP_LIMIT_PER_MINUTE = 1
        words_module.reset_word_lookup_rate_limit_state_for_test()

        first = client.get('/api/v1/words/consolidate')
        assert first.status_code == 200

        second = client.get('/api/v1/words/consolidate')
        assert second.status_code == 429
    finally:
        words_module.WORD_LOOKUP_LIMIT_PER_MINUTE = original_limit
        words_module.reset_word_lookup_rate_limit_state_for_test()



def test_quiz_submit_rate_limit(client: TestClient) -> None:
    import importlib

    quiz_module = importlib.import_module('app.modules.quiz.router')
    original_limit = quiz_module.QUIZ_SUBMIT_LIMIT_PER_MINUTE

    try:
        quiz_module.QUIZ_SUBMIT_LIMIT_PER_MINUTE = 1
        quiz_module.reset_quiz_submit_rate_limit_state_for_test()

        first = client.post('/api/v1/quiz/submit', json={'article_id': 1, 'answers': []})
        assert first.status_code == 200

        second = client.post('/api/v1/quiz/submit', json={'article_id': 1, 'answers': []})
        assert second.status_code == 429
    finally:
        quiz_module.QUIZ_SUBMIT_LIMIT_PER_MINUTE = original_limit
        quiz_module.reset_quiz_submit_rate_limit_state_for_test()






def test_web_article_search_contract(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    import importlib

    web_articles_module = importlib.import_module('app.modules.web_articles.router')

    feeds = {
        'https://feed-a.example/rss.xml': """<?xml version='1.0'?>
        <rss version='2.0'>
          <channel>
            <title>BBC Tech</title>
            <item>
              <title>Sleep science improves learning</title>
              <link>https://example.com/a1</link>
              <description>Students learn English faster with better sleep.</description>
              <pubDate>Sat, 21 Mar 2026 12:00:00 GMT</pubDate>
            </item>
            <item>
              <title>AI fairness in schools</title>
              <link>https://example.com/a2</link>
              <description>Equity and education remain key topics.</description>
              <pubDate>Fri, 20 Mar 2026 12:00:00 GMT</pubDate>
            </item>
          </channel>
        </rss>
        """,
        'https://feed-b.example/atom.xml': """<?xml version='1.0' encoding='utf-8'?>
        <feed xmlns='http://www.w3.org/2005/Atom'>
          <title>NPR Science</title>
          <entry>
            <title>English reading habits and memory</title>
            <link href='https://example.com/b1' />
            <summary>Memory and reading routines can reinforce vocabulary.</summary>
            <updated>2026-03-22T09:00:00Z</updated>
          </entry>
          <entry>
            <title>Duplicate article</title>
            <link href='https://example.com/a2' />
            <summary>This should be deduplicated by URL.</summary>
            <updated>2026-03-22T08:00:00Z</updated>
          </entry>
        </feed>
        """,
    }

    monkeypatch.setattr(web_articles_module.settings, 'web_article_feed_urls', ','.join(feeds.keys()))
    monkeypatch.setattr(web_articles_module, 'fetch_feed_xml', lambda url: feeds[url])

    response = client.get('/api/v1/web-articles/search', params={'q': 'memory', 'page': 1, 'size': 10})
    assert response.status_code == 200
    data = response.json()['data']
    assert data['page'] == 1
    assert data['size'] == 10
    assert data['total'] == 1
    assert data['has_next'] is False
    assert data['sources_checked'] == 2
    assert data['source_errors'] == []

    item = data['items'][0]
    assert item['title'] == 'English reading habits and memory'
    assert item['source'] == 'NPR Science'
    assert item['url'] == 'https://example.com/b1'
    assert item['published_at'] == '2026-03-22T09:00:00+00:00'



def test_web_article_search_latest_pagination_and_source_errors(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    import importlib

    web_articles_module = importlib.import_module('app.modules.web_articles.router')

    feeds = {
        'https://feed-a.example/rss.xml': """<?xml version='1.0'?>
        <rss version='2.0'>
          <channel>
            <title>BBC World</title>
            <item>
              <title>Article One</title>
              <link>https://example.com/one</link>
              <description>Latest story one.</description>
              <pubDate>Sun, 22 Mar 2026 12:00:00 GMT</pubDate>
            </item>
            <item>
              <title>Article Two</title>
              <link>https://example.com/two</link>
              <description>Latest story two.</description>
              <pubDate>Sat, 21 Mar 2026 12:00:00 GMT</pubDate>
            </item>
          </channel>
        </rss>
        """,
    }

    def fake_fetch(url: str) -> str:
        if url in feeds:
            return feeds[url]
        raise OSError('network down')

    monkeypatch.setattr(
        web_articles_module.settings,
        'web_article_feed_urls',
        'https://feed-a.example/rss.xml,https://feed-b.example/rss.xml',
    )
    monkeypatch.setattr(web_articles_module, 'fetch_feed_xml', fake_fetch)

    response = client.get('/api/v1/web-articles/search', params={'page': 1, 'size': 1})
    assert response.status_code == 200
    data = response.json()['data']
    assert data['total'] == 2
    assert data['has_next'] is True
    assert len(data['items']) == 1
    assert data['items'][0]['title'] == 'Article One'
    assert data['source_errors'] == ['https://feed-b.example/rss.xml']



def test_web_article_import_infers_topic_and_level_from_source(client: TestClient) -> None:
    from app.core.config import settings

    unique_id = uuid4().hex
    headers = {'X-Admin-Key': settings.admin_api_key}
    payload = {
        'title': f'AI Research Update {unique_id}',
        'url': f'https://www.techcrunch.com/story-{unique_id}',
        'source': 'TechCrunch',
        'summary': 'A report about AI software startups and new tools.',
        'published_at': '2026-03-22T09:00:00Z',
    }

    response = client.post('/api/v1/web-articles/import', headers=headers, json=payload)
    assert response.status_code == 200
    article_id = response.json()['data']['article_id']

    admin_detail = client.get(f'/api/v1/admin/articles/{article_id}', headers=headers)
    assert admin_detail.status_code == 200
    detail = admin_detail.json()['data']
    assert detail['topic'] == 'technology'
    assert detail['stage'] == 'cet6'
    assert detail['level'] == 2


def test_web_article_import_creates_draft_and_is_idempotent(client: TestClient) -> None:
    from app.core.config import settings

    unique_id = uuid4().hex
    headers = {'X-Admin-Key': settings.admin_api_key}
    payload = {
        'title': f'Imported RSS Article {unique_id}',
        'url': f'https://example.com/imported-rss-article-{unique_id}',
        'source': 'NPR Science',
        'summary': 'Imported summary for editing before publication.',
        'published_at': '2026-03-22T09:00:00Z',
        'stage_tag': 'cet6',
        'level': 2,
        'topic': 'science',
    }

    first = client.post('/api/v1/web-articles/import', headers=headers, json=payload)
    assert first.status_code == 200
    first_data = first.json()['data']
    assert first_data['imported'] is True
    assert first_data['idempotent'] is False
    article_id = first_data['article_id']

    admin_detail = client.get(f'/api/v1/admin/articles/{article_id}', headers=headers)
    assert admin_detail.status_code == 200
    detail = admin_detail.json()['data']
    assert detail['status'] == 'draft'
    assert detail['source_url'] == payload['url']
    assert detail['paragraph_count'] == 1

    second = client.post('/api/v1/web-articles/import', headers=headers, json=payload)
    assert second.status_code == 200
    second_data = second.json()['data']
    assert second_data['article_id'] == article_id
    assert second_data['imported'] is False
    assert second_data['idempotent'] is True

    with db_session.SessionLocal() as db:
        article = db.get(Article, article_id)
        assert article is not None
        assert article.status == 'draft'
        assert article.slug is not None

        snapshots = db.scalars(select(ArticleContent).where(ArticleContent.article_id == article_id)).all()
        assert len(snapshots) == 1
        assert 'Imported summary' in snapshots[0].content_text

        sources = db.scalars(select(ArticleSource).where(ArticleSource.article_id == article_id)).all()
        assert len(sources) == 1
        assert sources[0].source_type == 'rss'
        assert sources[0].source_name == 'NPR Science'
        assert sources[0].source_url == payload['url']


def test_admin_articles_require_admin_key(client: TestClient) -> None:
    missing = client.get('/api/v1/admin/articles')
    assert missing.status_code == 401

    invalid = client.get('/api/v1/admin/articles', headers={'X-Admin-Key': 'wrong-key'})
    assert invalid.status_code == 403



def test_admin_articles_search_filters_title_summary_and_source(client: TestClient) -> None:
    from app.core.config import settings

    unique_id = uuid4().hex
    headers = {'X-Admin-Key': settings.admin_api_key}
    create_response = client.post(
        '/api/v1/admin/articles',
        headers=headers,
        json={
            'title': f'Climate Policy Brief {unique_id}',
            'stage_tag': 'cet6',
            'level': 2,
            'topic': 'policy',
            'summary': 'A concise summary about urban transport reform.',
            'source_url': f'https://newsroom.example.com/brief-{unique_id}',
            'reading_minutes': 5,
            'is_published': False,
            'paragraphs': ['Draft paragraph for admin search coverage.'],
        },
    )
    assert create_response.status_code == 200
    article_id = create_response.json()['data']['id']

    by_title = client.get('/api/v1/admin/articles', headers=headers, params={'q': unique_id})
    assert by_title.status_code == 200
    title_items = by_title.json()['data']['items']
    assert any(item['id'] == article_id for item in title_items)

    by_summary = client.get('/api/v1/admin/articles', headers=headers, params={'q': 'urban transport reform'})
    assert by_summary.status_code == 200
    summary_items = by_summary.json()['data']['items']
    assert any(item['id'] == article_id for item in summary_items)

    by_source = client.get('/api/v1/admin/articles', headers=headers, params={'q': 'newsroom.example.com'})
    assert by_source.status_code == 200
    source_items = by_source.json()['data']['items']
    assert any(item['id'] == article_id for item in source_items)


def test_admin_article_crud_and_publish_flow(client: TestClient) -> None:
    from app.core.config import settings

    headers = {'X-Admin-Key': settings.admin_api_key}

    create_response = client.post(
        '/api/v1/admin/articles',
        headers=headers,
        json={
            'title': 'Admin Draft Article',
            'stage_tag': 'cet6',
            'level': 2,
            'topic': 'technology',
            'reading_minutes': 7,
            'is_published': False,
            'paragraphs': [
                'Draft paragraph one about adaptive learning systems.',
                'Draft paragraph two about formative feedback loops.',
            ],
        },
    )
    assert create_response.status_code == 200
    created = create_response.json()['data']
    article_id = created['id']
    assert created['is_published'] is False
    assert created['paragraph_count'] == 2

    public_draft_detail = client.get(f'/api/v1/articles/{article_id}')
    assert public_draft_detail.status_code == 404

    admin_detail = client.get(f'/api/v1/admin/articles/{article_id}', headers=headers)
    assert admin_detail.status_code == 200
    assert admin_detail.json()['data']['title'] == 'Admin Draft Article'

    update_response = client.patch(
        f'/api/v1/admin/articles/{article_id}',
        headers=headers,
        json={
            'title': 'Admin Published Article',
            'paragraphs': [
                'Updated paragraph one about adaptive learning systems.',
                'Updated paragraph two about formative feedback loops.',
                'Updated paragraph three about teacher dashboards.',
            ],
        },
    )
    assert update_response.status_code == 200
    updated = update_response.json()['data']
    assert updated['title'] == 'Admin Published Article'
    assert updated['paragraph_count'] == 3

    publish_response = client.post(
        f'/api/v1/admin/articles/{article_id}/publish',
        headers=headers,
        json={'is_published': True},
    )
    assert publish_response.status_code == 200
    assert publish_response.json()['data']['is_published'] is True

    admin_list_response = client.get('/api/v1/admin/articles', headers=headers, params={'published': 'true'})
    assert admin_list_response.status_code == 200
    admin_items = admin_list_response.json()['data']['items']
    assert any(item['id'] == article_id for item in admin_items)

    public_detail = client.get(f'/api/v1/articles/{article_id}')
    assert public_detail.status_code == 200
    public_data = public_detail.json()['data']
    assert public_data['title'] == 'Admin Published Article'
    assert len(public_data['paragraphs']) == 3


def test_admin_sentence_analysis_and_quiz_and_word_management(client: TestClient) -> None:
    from app.core.config import settings

    headers = {'X-Admin-Key': settings.admin_api_key}

    create_article = client.post(
        '/api/v1/admin/articles',
        headers=headers,
        json={
            'title': 'Admin Content Pipeline Article',
            'stage_tag': 'cet4',
            'level': 1,
            'topic': 'science',
            'reading_minutes': 6,
            'is_published': False,
            'paragraphs': [
                'Paragraph one about memory and study routines.',
                'Paragraph two about repetition and retrieval.',
            ],
        },
    )
    assert create_article.status_code == 200
    article_id = create_article.json()['data']['id']

    analysis_replace = client.put(
        f'/api/v1/admin/articles/{article_id}/sentence-analyses',
        headers=headers,
        json={
            'items': [
                {
                    'sentence_index': 1,
                    'sentence': 'Sleep helps the brain strengthen memory traces.',
                    'translation': '睡眠帮助大脑强化记忆痕迹。',
                    'structure': '主谓宾',
                },
                {
                    'sentence_index': 2,
                    'sentence': 'Retrieval practice makes recall more stable over time.',
                    'translation': '提取练习会让回忆在更长时间内更稳定。',
                    'structure': '主谓宾补',
                },
            ]
        },
    )
    assert analysis_replace.status_code == 200
    analysis_data = analysis_replace.json()['data']
    assert len(analysis_data['items']) == 2
    assert analysis_data['items'][0]['sentence_index'] == 1

    admin_analysis = client.get(f'/api/v1/admin/articles/{article_id}/sentence-analyses', headers=headers)
    assert admin_analysis.status_code == 200
    assert len(admin_analysis.json()['data']['items']) == 2

    draft_public_analysis = client.get(f'/api/v1/articles/{article_id}/sentence-analyses')
    assert draft_public_analysis.status_code == 404

    quiz_replace = client.put(
        f'/api/v1/admin/articles/{article_id}/quiz',
        headers=headers,
        json={
            'questions': [
                {
                    'question_index': 1,
                    'stem': 'What is the main idea of the passage?',
                    'options': ['Memory training', 'City traffic', 'Weather forecast'],
                    'correct_option_index': 1,
                },
                {
                    'question_index': 2,
                    'stem': 'Which activity improves recall?',
                    'options': ['Passive rereading', 'Retrieval practice', 'Skipping review'],
                    'correct_option_index': 2,
                },
            ]
        },
    )
    assert quiz_replace.status_code == 200
    quiz_data = quiz_replace.json()['data']
    assert len(quiz_data['questions']) == 2
    assert quiz_data['questions'][1]['correct_option_index'] == 2

    draft_public_quiz = client.get(f'/api/v1/articles/{article_id}/quiz')
    assert draft_public_quiz.status_code == 404

    publish_response = client.post(
        f'/api/v1/admin/articles/{article_id}/publish',
        headers=headers,
        json={'is_published': True},
    )
    assert publish_response.status_code == 200

    public_analysis = client.get(f'/api/v1/articles/{article_id}/sentence-analyses')
    assert public_analysis.status_code == 200
    assert len(public_analysis.json()['data']['items']) == 2

    public_quiz = client.get(f'/api/v1/articles/{article_id}/quiz')
    assert public_quiz.status_code == 200
    assert len(public_quiz.json()['data']['questions']) == 2

    lemma = f'retention_{uuid4().hex[:8]}'
    word_create = client.post(
        '/api/v1/admin/words',
        headers=headers,
        json={
            'lemma': lemma,
            'phonetic': 'rɪˈtenʃən',
            'pos': 'n.',
            'meaning_cn': '保持；记忆保持',
        },
    )
    assert word_create.status_code == 200
    word_id = word_create.json()['data']['id']

    word_list = client.get('/api/v1/admin/words', headers=headers, params={'q': lemma})
    assert word_list.status_code == 200
    word_items = word_list.json()['data']['items']
    assert any(item['id'] == word_id for item in word_items)

    word_update = client.patch(
        f'/api/v1/admin/words/{word_id}',
        headers=headers,
        json={'meaning_cn': '保持；记忆留存'},
    )
    assert word_update.status_code == 200
    assert word_update.json()['data']['meaning_cn'] == '保持；记忆留存'


def test_admin_publish_enqueues_audio_task_and_reaches_ready(client: TestClient) -> None:
    import time

    from app.core.config import settings

    headers = {'X-Admin-Key': settings.admin_api_key}
    create_response = client.post(
        '/api/v1/admin/articles',
        headers=headers,
        json={
            'title': 'Audio Ready Workflow Article',
            'stage_tag': 'cet4',
            'level': 1,
            'topic': 'science',
            'reading_minutes': 5,
            'is_published': False,
            'paragraphs': [
                'Paragraph one for audio generation.',
                'Paragraph two for audio generation.',
            ],
        },
    )
    assert create_response.status_code == 200
    article_id = create_response.json()['data']['id']

    publish_response = client.post(
        f'/api/v1/admin/articles/{article_id}/publish',
        headers=headers,
        json={'is_published': True},
    )
    assert publish_response.status_code == 200
    assert publish_response.json()['data']['audio_status'] == 'pending'

    deadline = time.time() + 5
    final_task = None
    while time.time() < deadline:
        task_response = client.get(f'/api/v1/admin/articles/{article_id}/audio-task', headers=headers)
        assert task_response.status_code == 200
        final_task = task_response.json()['data']['task']
        if final_task is not None and final_task['status'] == 'ready':
            break
        time.sleep(0.15)

    assert final_task is not None
    assert final_task['status'] == 'ready'
    assert final_task['article_audio_url'] == f"{settings.public_base_url}{settings.api_prefix}/articles/{article_id}/audio/file"

    public_audio = client.get(f'/api/v1/articles/{article_id}/audio')
    assert public_audio.status_code == 200
    audio_data = public_audio.json()['data']
    assert audio_data['status'] == 'ready'
    assert audio_data['article_audio_url'] == f"{settings.public_base_url}{settings.api_prefix}/articles/{article_id}/audio/file"

    audio_file = client.get(f'/api/v1/articles/{article_id}/audio/file')
    assert audio_file.status_code == 200
    assert audio_file.headers['content-type'].startswith('audio/wav')
    assert len(audio_file.content) > 100



def test_admin_article_snapshots_and_sources_are_persisted(client: TestClient) -> None:
    from app.core.config import settings

    headers = {'X-Admin-Key': settings.admin_api_key}
    create_response = client.post(
        '/api/v1/admin/articles',
        headers=headers,
        json={
            'title': 'Snapshot Source Article',
            'stage_tag': 'cet6',
            'level': 2,
            'topic': 'technology',
            'source_url': 'https://example.com/source-article',
            'reading_minutes': 7,
            'is_published': False,
            'paragraphs': [
                'Paragraph one about adaptive content systems.',
                'Paragraph two about human review workflows.',
            ],
        },
    )
    assert create_response.status_code == 200
    article_id = create_response.json()['data']['id']

    update_response = client.patch(
        f'/api/v1/admin/articles/{article_id}',
        headers=headers,
        json={
            'reading_minutes': 9,
            'paragraphs': [
                'Paragraph one about adaptive content systems.',
                'Paragraph two about human review workflows.',
                'Paragraph three about versioned publishing.',
            ],
        },
    )
    assert update_response.status_code == 200

    with db_session.SessionLocal() as db:
        article = db.get(Article, article_id)
        assert article is not None
        assert article.slug is not None
        assert article.status == 'draft'
        assert article.summary is not None

        snapshots = db.scalars(
            select(ArticleContent)
            .where(ArticleContent.article_id == article_id)
            .order_by(ArticleContent.version.asc())
        ).all()
        assert len(snapshots) == 2
        assert snapshots[0].version == 1
        assert snapshots[1].version == 2
        assert snapshots[-1].estimated_reading_minutes == 9
        assert 'versioned publishing' in snapshots[-1].content_text

        sources = db.scalars(select(ArticleSource).where(ArticleSource.article_id == article_id)).all()
        assert len(sources) == 1
        assert sources[0].source_type == 'manual'
        assert sources[0].source_url == 'https://example.com/source-article'


def test_admin_audio_task_retries_and_fails(client: TestClient) -> None:
    import time

    from app.core.config import settings

    headers = {'X-Admin-Key': settings.admin_api_key}
    create_response = client.post(
        '/api/v1/admin/articles',
        headers=headers,
        json={
            'title': '[tts-fail] Audio Failure Workflow Article',
            'stage_tag': 'cet6',
            'level': 2,
            'topic': 'technology',
            'reading_minutes': 5,
            'is_published': True,
            'paragraphs': [
                'Paragraph one for failing audio generation.',
                'Paragraph two for failing audio generation.',
            ],
        },
    )
    assert create_response.status_code == 200
    article_id = create_response.json()['data']['id']

    deadline = time.time() + 8
    final_task = None
    while time.time() < deadline:
        task_response = client.get(f'/api/v1/admin/articles/{article_id}/audio-task', headers=headers)
        assert task_response.status_code == 200
        final_task = task_response.json()['data']['task']
        if final_task is not None and final_task['status'] == 'failed':
            break
        time.sleep(0.15)

    assert final_task is not None
    assert final_task['status'] == 'failed'
    assert final_task['attempt_count'] == settings.tts_max_attempts
    assert final_task['last_error'] == 'mock_tts_generation_failed'

    public_audio = client.get(f'/api/v1/articles/{article_id}/audio')
    assert public_audio.status_code == 200
    audio_data = public_audio.json()['data']
    assert audio_data['status'] == 'failed'
    assert audio_data['article_audio_url'] is None
    assert audio_data['retry_hint'] == '稍后重试'


