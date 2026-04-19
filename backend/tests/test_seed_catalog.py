from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import app.db.init_db as init_db_module
import app.db.session as db_session
import app.main as main_module
import app.tasks.audio_tasks as audio_tasks_module
from app.main import app


@pytest.fixture
def client(tmp_path: Path) -> TestClient:
    test_db_path = tmp_path / 'englishapp-seed-catalog.db'
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


def test_seed_article_catalog_reaches_twenty_articles(client: TestClient) -> None:
    response = client.get('/api/v1/articles', params={'page': 1, 'size': 50, 'sort': 'recommended'})
    assert response.status_code == 200

    data = response.json()['data']
    titles = {item['title'] for item in data['items']}

    assert data['total'] >= 20
    assert 'How Bilingual Brains Switch Attention' in titles
    assert 'Why Data Privacy Matters to Students' in titles
    assert 'How Citizen Science Expands Research' in titles


def test_new_seed_article_exposes_detail_analysis_and_quiz(client: TestClient) -> None:
    list_response = client.get('/api/v1/articles', params={'page': 1, 'size': 50, 'sort': 'recommended'})
    assert list_response.status_code == 200

    items = list_response.json()['data']['items']
    target = next(item for item in items if item['title'] == 'How Citizen Science Expands Research')
    article_id = target['id']

    detail_response = client.get(f'/api/v1/articles/{article_id}')
    assert detail_response.status_code == 200
    assert len(detail_response.json()['data']['paragraphs']) >= 4

    analysis_response = client.get(f'/api/v1/articles/{article_id}/sentence-analyses')
    assert analysis_response.status_code == 200
    assert len(analysis_response.json()['data']['items']) >= 2

    quiz_response = client.get(f'/api/v1/articles/{article_id}/quiz')
    assert quiz_response.status_code == 200
    assert len(quiz_response.json()['data']['questions']) == 3


def test_long_form_seed_article_exposes_paragraph_translations(client: TestClient) -> None:
    list_response = client.get('/api/v1/articles', params={'page': 1, 'size': 50, 'sort': 'recommended'})
    assert list_response.status_code == 200

    items = list_response.json()['data']['items']
    target = next(item for item in items if item['title'] == 'How Renewable Power Grids Stay Stable')
    article_id = target['id']

    detail_response = client.get(f'/api/v1/articles/{article_id}')
    assert detail_response.status_code == 200

    detail = detail_response.json()['data']
    paragraphs = detail['paragraphs']

    assert detail['translation_status'] == 'complete'
    assert len(paragraphs) >= 6
    assert all(item['translation'] for item in paragraphs)
    assert detail['content_translation']
