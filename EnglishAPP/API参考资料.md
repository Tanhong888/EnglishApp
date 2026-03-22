# EnglishAPP API 参考资料

## 1. 总览

- 服务地址（本地）：`http://127.0.0.1:8000`
- 业务前缀：`/api/v1`
- OpenAPI：`/docs`

说明：`/health` 是全局健康检查，不在 `/api/v1` 前缀下。

---

## 2. 统一响应结构

绝大多数接口返回如下结构：

```json
{
  "code": 0,
  "message": "ok",
  "data": {},
  "trace_id": "local-dev"
}
```

鉴权/校验错误使用 FastAPI 标准错误结构，例如：

```json
{
  "detail": "missing_authorization"
}
```

---

## 3. 鉴权说明

受保护接口需要请求头：

```http
Authorization: Bearer <access_token>
```

Token 机制：

- Access Token：短期
- Refresh Token：长期，可轮换
- `/auth/logout`：撤销 Refresh Token

---

## 4. 健康检查

### `GET /health`

用途：服务健康状态。

---

## 5. 认证与账号

### `POST /api/v1/auth/register`

- 入参：`email`、`password`、`nickname?`、`target?`
- 返回：用户基础信息

### `POST /api/v1/auth/login`

- 入参：`email`、`password`
- 返回：`access_token`、`refresh_token`、`token_type`、`user`

### `POST /api/v1/auth/refresh`

- 入参：`refresh_token`
- 返回：新 `access_token` + 新 `refresh_token`（旧 refresh 自动失效）

### `POST /api/v1/auth/logout`

- 入参：`refresh_token`
- 返回：`revoked: true`

### `GET /api/v1/users/me`（鉴权）

- 返回：当前用户资料 + 账号状态字段

### `DELETE /api/v1/users/me`（鉴权）

- 入参：`mode: soft|hard`
- 软删：不可登录，保留期后可硬删
- 硬删：直接删除用户相关学习数据

---

## 6. 首页与内容

### `GET /api/v1/home/recommendations`

- 返回：`today` 推荐文章、`quick_entries`

### `GET /api/v1/articles`

- Query：
- `page` 默认 `1`
- `size` 默认 `20`，最大 `50`
- `stage` 可选
- `level` 可选（1-4）
- `topic` 可选
- `sort`：`recommended|latest|hot`

- 返回：`items/page/size/total/has_next`

### `GET /api/v1/articles/{article_id}`

- 返回：文章基础信息 + `paragraphs`

### `GET /api/v1/articles/{article_id}/audio`

- 返回：`status`、`article_audio_url`、`paragraph_timestamps`、`retry_hint`
- `status`：`pending|processing|ready|failed`

### `GET /api/v1/articles/{article_id}/favorite-status`（鉴权）

- 返回：当前用户是否已收藏该文章

### `POST /api/v1/articles/{article_id}/favorite`（鉴权）

- 收藏文章（幂等）

### `DELETE /api/v1/articles/{article_id}/favorite`（鉴权）

- 取消收藏（幂等）

---

## 7. 词汇与生词本

### `GET /api/v1/words/{word}`

- 大小写不敏感查词
- 返回：`id/lemma/phonetic/pos/meaning_cn`

### `POST /api/v1/vocab`（鉴权）

- 入参：`word_id`、`source_article_id`
- 约束：`(user_id, word_id, source_article_id)` 唯一
- 返回：`created` 标识本次是否新建

### `PATCH /api/v1/vocab/{entry_id}`（鉴权）

- 入参：`mastered: bool`
- 用途：更新掌握状态

---

## 8. 阅读进度

### `POST /api/v1/reading/progress`（鉴权）

- 入参：`article_id`、`paragraph_index`
- 用途：保存阅读进度

### `GET /api/v1/reading/recent`（鉴权）

- 用途：获取最近阅读列表

---

## 9. 解析与小测

### `GET /api/v1/articles/{article_id}/sentence-analyses`

- 返回：句子、翻译、结构

### `GET /api/v1/articles/{article_id}/quiz`

- 返回：题目与选项

### `POST /api/v1/quiz/submit`

- 入参：`article_id`、`answers`
- 返回：`attempt_id`、`accuracy`

### `GET /api/v1/quiz/attempts/{attempt_id}`

- 返回：正确数、总题数、正确率、错题列表

---

## 10. 我的页面聚合接口（鉴权）

### `GET /api/v1/me/stats`

- 返回：`read_articles`、`study_days`、`vocab_count`、`completion_rate`

### `GET /api/v1/me/learning-records`

- 返回：按天聚合的学习记录

### `GET /api/v1/me/vocab`

- Query：`source_article_id?`、`mastered?`、`page`、`size`
- 默认按词去重聚合返回

### `GET /api/v1/me/favorites`

- Query：`page`、`size`
- 返回收藏文章列表

---

## 11. 常用请求示例

### 登录

```bash
curl -X POST "http://127.0.0.1:8000/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@englishapp.dev","password":"Passw0rd!"}'
```

### 查询文章列表

```bash
curl "http://127.0.0.1:8000/api/v1/articles?page=1&size=20&sort=recommended"
```

### 查词

```bash
curl "http://127.0.0.1:8000/api/v1/words/consolidate"
```

### 加入生词本（鉴权）

```bash
curl -X POST "http://127.0.0.1:8000/api/v1/vocab" \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"word_id":1,"source_article_id":1}'
```
