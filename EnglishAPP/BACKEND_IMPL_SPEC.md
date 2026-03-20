# 英语分级阅读后端实现规格（V1）

## 1. 文档目标

基于现有 PRD/TECH，提供可直接进入开发的后端实现细则，覆盖：

- 模块边界
- 数据模型与约束
- API 契约
- 鉴权生命周期
- 缓存与异步任务
- 测试与验收

---

## 2. 技术栈与边界

- 框架：FastAPI
- ORM：SQLAlchemy 2.x
- 校验：Pydantic 2.x
- DB：PostgreSQL 16
- 缓存/队列：Redis 7.x
- 异步：Celery 5.x
- 存储：S3 兼容对象存储

边界：

- V1 为模块化单体，不拆微服务
- 不做复杂推荐算法
- 不做跟读评分

---

## 3. 模块划分与职责

1. `auth`
- 注册、登录、刷新、登出、当前用户信息
- Refresh Token 轮换与撤销

2. `content`
- 文章列表筛选排序分页
- 文章详情
- 音频状态查询

3. `reading`
- 阅读进度保存
- 最近阅读记录

4. `vocab`
- 加入生词本
- 更新掌握状态
- 生词列表（默认按词去重，支持文章来源筛选）

5. `favorite`
- 收藏文章新增/取消
- 收藏列表

6. `analysis`
- 重点句解析查询

7. `quiz`
- 获取题目
- 提交答案
- 查询结果

8. `analytics`
- 埋点入库与聚合

---

## 4. 数据模型与关键约束

## 4.1 核心表（V1）

- `users`
- `user_profiles`
- `articles`
- `article_paragraphs`
- `article_sentences`
- `sentence_analyses`
- `words`
- `article_words`
- `quizzes` / `quiz_questions` / `quiz_options`
- `user_quiz_attempts` / `user_quiz_answers`
- `user_vocab_entries`
- `user_article_favorites`
- `user_reading_progress`
- `learning_records`

## 4.2 关键唯一约束

- `words(lemma)` 唯一
- `user_vocab_entries(user_id, word_id, source_article_id)` 唯一
- `user_article_favorites(user_id, article_id)` 唯一
- `user_reading_progress(user_id, article_id)` 唯一

## 4.3 业务约束

1. 同词不同文章来源可同时存在（数据层保留多来源）。
2. 生词列表默认按 `word_id` 去重返回。
3. 收藏文章幂等：重复收藏不报错，返回当前状态。
4. 取消收藏不影响阅读历史。

---

## 5. 统一 API 规范

## 5.1 统一响应格式

成功：

```json
{
  "code": 0,
  "message": "ok",
  "data": {},
  "trace_id": "8f0a4d..."
}
```

失败：

```json
{
  "code": 10023,
  "message": "invalid_token",
  "data": null,
  "trace_id": "8f0a4d..."
}
```

## 5.2 分页规范

- 入参：`page`（默认 1）、`size`（默认 20，最大 50）
- 返回：`items`、`page`、`size`、`total`、`has_next`
- 超出 `size` 上限返回 `400`

## 5.3 错误码建议

- `10001` 参数非法
- `10002` 未认证
- `10003` 无权限
- `10004` 资源不存在
- `10005` 业务冲突
- `10023` Token 无效或已撤销
- `20001` 第三方词典服务异常
- `20002` TTS 服务异常

---

## 6. 核心接口契约（V1）

## 6.1 鉴权

1. `POST /api/v1/auth/register`
2. `POST /api/v1/auth/login`
3. `POST /api/v1/auth/refresh`
4. `POST /api/v1/auth/logout`
5. `GET /api/v1/users/me`

`/auth/refresh` 规则：

- 每次刷新都签发新 Refresh Token
- 旧 Refresh Token 立即失效

`/auth/logout` 规则：

- 当前 Refresh Token 加入 Redis 撤销集合
- 撤销有效期至少覆盖 Token 剩余生命周期

## 6.2 内容与阅读

1. `GET /api/v1/articles`

Query：

- `page`、`size`
- `stage`（`cet4|cet6|kaoyan`）
- `level`（`1|2|3|4`）
- `topic`
- `sort`（`recommended|latest|hot`）

Response：

```json
{
  "items": [],
  "page": 1,
  "size": 20,
  "total": 132,
  "has_next": true
}
```

2. `GET /api/v1/articles/{article_id}`
3. `GET /api/v1/articles/{article_id}/audio`

`audio` 返回示例：

```json
{
  "status": "processing",
  "article_audio_url": null,
  "paragraph_timestamps": []
}
```

4. `POST /api/v1/reading/progress`
5. `GET /api/v1/reading/recent`

## 6.3 收藏文章

1. `POST /api/v1/articles/{article_id}/favorite`
2. `DELETE /api/v1/articles/{article_id}/favorite`
3. `GET /api/v1/me/favorites`

行为约束：

- 收藏/取消均幂等
- `GET /api/v1/me/favorites` 支持分页

## 6.4 生词本

1. `POST /api/v1/vocab`

Request：

```json
{
  "word_id": 1001,
  "source_article_id": 501
}
```

2. `PATCH /api/v1/vocab/{entry_id}`
3. `GET /api/v1/me/vocab`

Query（可选）：

- `source_article_id`
- `mastered`
- `page`、`size`

默认返回：

- 按词去重聚合
- 可返回 `source_count` 与 `latest_source_article_id`

## 6.5 解析与小测

1. `GET /api/v1/articles/{article_id}/sentence-analyses`
2. `GET /api/v1/articles/{article_id}/quiz`
3. `POST /api/v1/quiz/submit`
4. `GET /api/v1/quiz/attempts/{attempt_id}`

---

## 7. TTS 异步任务实现

状态机：

- `pending -> processing -> ready | failed`

任务流程：

1. 文章发布后创建 `pending` 任务
2. Worker 拉取并置为 `processing`
3. 成功后上传音频到对象存储并回写 URL 与时间戳，状态置 `ready`
4. 失败重试最多 3 次（指数退避）
5. 超过重试上限置 `failed`

告警：

- 单文章重试耗尽告警
- 10 分钟仍未 `ready` 告警

客户端降级约定：

- `failed` 时隐藏播放控件，保留文本学习链路

---

## 8. 缓存与性能策略

1. 文章列表缓存
- Key：`articles:list:{stage}:{level}:{topic}:{sort}:{page}:{size}`
- TTL：120 秒

2. 文章详情缓存
- Key：`articles:detail:{article_id}`
- TTL：300 秒

3. 点词缓存
- Key：`words:lemma:{lemma}`
- TTL：24 小时

4. 失效策略
- 文章发布或更新时主动删除相关列表/详情缓存
- 高频词更新时删除对应 lemma 缓存

---

## 9. 安全与数据生命周期

1. 密码：Argon2 哈希
2. 传输：HTTPS
3. Access Token：短期
4. Refresh Token：长期，轮换+撤销
5. 账号删除：先软删（不可登录），30 天后硬删个人数据
6. 审计日志：后台发布、编辑、删除全记录

---

## 10. 目录结构建议（后端）

```text
app/
  main.py
  core/           # config, security, middleware, errors
  modules/
    auth/
    content/
    reading/
    vocab/
    favorite/
    analysis/
    quiz/
    analytics/
  db/             # models, session, migrations
  tasks/          # celery tasks
  schemas/        # shared pydantic schemas
tests/
  unit/
  integration/
  contract/
```

---

## 11. 测试与验收（必须覆盖）

1. 同词多文章来源
- 同一 `word_id` 在不同 `source_article_id` 可插入两条记录
- 列表默认去重，按文章来源可查明细

2. 收藏文章链路
- 收藏幂等
- 取消后可再次收藏
- 不影响阅读历史

3. 列表分页稳定性
- 两页无重复
- 排序稳定
- `size` 上限生效

4. TTS 失败降级
- 超过重试上限返回 `failed`
- 客户端降级策略可触发

5. Token 生命周期
- 登出后 Refresh 不可再用
- 旧 Refresh 在轮换后不可再用

---

## 12. 实施顺序建议

1. 先落 `auth/content` 与统一中间件
2. 再落 `vocab/favorite/reading`
3. 再落 `analysis/quiz`
4. 最后接 `tts/analytics` 与监控告警

