from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def client() -> TestClient:
    with TestClient(app) as test_client:
        yield test_client


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
