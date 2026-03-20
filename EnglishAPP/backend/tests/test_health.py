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
