# 英语分级阅读软件技术设计文档（V1.0）

## 1. 文档目标

基于 PRD（`英语分级阅读软件prd.md`）确定项目可落地的技术方案，覆盖：

- 客户端、服务端、后台、数据库、缓存、对象存储
- 核心业务模块技术实现方式
- API 与数据模型设计
- 测试、部署、监控、安全与迭代策略

目标是优先支持 MVP 闭环：`分级阅读 -> 阅读辅助 -> 小测 -> 生词沉淀`。

---

## 2. 技术选型总览

| 层级 | 技术 | 版本建议 | 选择原因 |
|---|---|---|---|
| 移动端 | Flutter + Dart | Flutter 3.24+ / Dart 3.5+ | 一套代码覆盖 iOS/Android，开发效率高，符合 PRD 建议 |
| 状态管理 | Riverpod | 2.x | 类型安全、易测试、适合中型业务复杂度 |
| 路由 | go_router | 14.x | 声明式路由，支持深链与登录态拦截 |
| 网络层 | Dio | 5.x | 拦截器、超时、重试、日志能力成熟 |
| 本地存储 | Hive + SharedPreferences | 最新稳定版 | 生词离线缓存、配置持久化简单高效 |
| 音频播放 | just_audio | 最新稳定版 | 支持分段播放、状态控制、高亮联动 |
| 服务端框架 | FastAPI | 0.115+ | 开发快、异步能力强、接口文档自动化 |
| ORM | SQLAlchemy + Alembic | 2.x / 1.13+ | 工业级 ORM + 数据库迁移能力 |
| 数据校验 | Pydantic | 2.x | 与 FastAPI 深度集成，模型清晰 |
| 数据库 | PostgreSQL | 16 | 关系建模强、全文检索可用、稳定性高 |
| 缓存/队列 | Redis | 7.x | 缓存热点数据、异步任务队列、限流 |
| 异步任务 | Celery | 5.x | 处理 TTS 生成、批量内容处理等后台任务 |
| 对象存储 | S3 兼容存储（AWS S3/阿里云 OSS/腾讯云 COS） | - | 存放音频、封面、静态资源 |
| 管理后台前端 | React + Vite + Ant Design | React 18+ | 运营/教研录入内容效率高 |
| 管理后台 API | 与主 FastAPI 复用 | - | 减少系统数量，降低维护成本 |
| 网关/反代 | Nginx | 稳定版 | TLS、静态资源分发、反向代理 |
| 监控告警 | Sentry + Prometheus + Grafana | 最新稳定版 | 错误追踪 + 指标监控完整 |
| 日志 | Loki 或 ELK（二选一） | - | 可检索链路日志，便于定位问题 |
| CI/CD | GitHub Actions | - | 自动测试、构建、部署流程标准化 |
| 容器化 | Docker + Docker Compose | 25+ | 本地一致环境，便于上线迁移 |

---

## 3. 总体架构

```text
Flutter App
   |
   | HTTPS/JSON
   v
Nginx (TLS, Reverse Proxy)
   |
   v
FastAPI (Monolith)
   |-- PostgreSQL (核心业务数据)
   |-- Redis (缓存/限流/队列)
   |-- S3 (音频与静态资源)
   |-- Celery Worker (TTS、离线处理)
   |
   +-- Admin Web (React) -> 复用 FastAPI 管理接口
```

架构策略：V1 采用单体服务（模块化单体），不拆微服务，优先确保迭代速度与稳定性。

---

## 4. 客户端技术方案（Flutter）

## 4.1 目录建议

```text
lib/
  core/           # 网络、错误、通用组件、主题
  features/
    auth/
    home/
    reading/
    quiz/
    vocab/
    profile/
  shared/
```

## 4.2 关键实现点

- 阅读页：支持段落渲染、可点击单词 Span、重点句高亮。
- 音频：全文/分段播放，播放进度与段落高亮同步。
- 生词本：本地缓存 + 服务端同步，支持离线查看最近收藏。
- 小测：提交后立即显示结果和错题解析。
- 埋点：关键动作（点击单词、收藏、生词复习、小测提交）统一事件上报。

## 4.3 推荐依赖

- `flutter_riverpod`
- `go_router`
- `dio`
- `freezed` + `json_serializable`
- `just_audio`
- `hive`
- `sentry_flutter`

---

## 5. 服务端技术方案（FastAPI）

## 5.1 模块划分

- `auth`：登录、Token、权限
- `content`：文章、段落、标签、推荐
- `reading`：阅读进度、最近阅读、收藏文章
- `lexicon`：单词释义、音标、发音、词组
- `analysis`：句子解析
- `quiz`：题目、提交、结果
- `vocab`：生词本与掌握状态
- `analytics`：埋点与统计聚合
- `admin`：内容管理（运营/教研）

## 5.2 核心中间件

- JWT 鉴权（Access + Refresh）
- 请求日志与 Trace ID
- 限流（基于 Redis）
- 统一异常处理与错误码
- CORS 与安全 Header

---

## 6. 数据库设计（PostgreSQL）

## 6.1 关键表（MVP）

- `users`：账号信息
- `user_profiles`：备考目标、等级偏好
- `articles`：文章主信息（标题、难度、阶段、主题、时长）
- `article_paragraphs`：段落内容与顺序
- `article_sentences`：句子级切分与定位
- `sentence_analyses`：重点句解析
- `words`：词典主数据（词形、音标、词性、释义）
- `article_words`：文章可点词映射（位置、词形归一）
- `quizzes` / `quiz_questions` / `quiz_options`
- `user_quiz_attempts` / `user_quiz_answers`
- `user_vocab_entries`：用户生词收藏与掌握状态
- `user_article_favorites`：用户收藏文章状态
- `user_reading_progress`：阅读进度、最后阅读位置
- `learning_records`：学习记录聚合数据

## 6.2 索引建议

- `articles(stage_tag, level, topic, published_at)`
- `words(lemma)` 唯一索引
- `user_vocab_entries(user_id, word_id, source_article_id)` 唯一索引
- `user_article_favorites(user_id, article_id)` 唯一索引
- `user_reading_progress(user_id, article_id)` 唯一索引

---

## 7. API 设计（MVP）

## 7.1 用户与鉴权

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `GET /api/v1/users/me`

## 7.2 内容与阅读

- `GET /api/v1/home/recommendations`
- `GET /api/v1/articles`（支持阶段、难度、主题筛选、排序、分页）
- `GET /api/v1/articles/{article_id}`
- `GET /api/v1/articles/{article_id}/audio`
- `POST /api/v1/articles/{article_id}/favorite`
- `DELETE /api/v1/articles/{article_id}/favorite`
- `POST /api/v1/reading/progress`
- `GET /api/v1/reading/recent`

## 7.3 点词释义与句子解析

- `GET /api/v1/words/{word}`
- `POST /api/v1/vocab`（加入生词本）
- `PATCH /api/v1/vocab/{entry_id}`（更新掌握状态）
- `GET /api/v1/articles/{article_id}/sentence-analyses`

## 7.4 小测

- `GET /api/v1/articles/{article_id}/quiz`
- `POST /api/v1/quiz/submit`
- `GET /api/v1/quiz/attempts/{attempt_id}`

## 7.5 我的

- `GET /api/v1/me/stats`
- `GET /api/v1/me/learning-records`
- `GET /api/v1/me/vocab`（默认按词去重，可按 `source_article_id` 过滤来源明细）
- `GET /api/v1/me/favorites`
- `GET /api/v1/analytics/dashboard/me-summary`（需登录，`days` 默认 7，用于我的页个人行为指标卡）

## 7.6 关键接口契约样例（MVP）

1. `GET /api/v1/articles`
   - Query：`page`（默认 1）、`size`（默认 20，最大 50）、`stage`、`level`、`topic`、`sort`（`recommended|latest|hot`）
   - Response：`items`、`page`、`size`、`total`、`has_next`
   - 默认排序：`recommended`
2. `POST /api/v1/vocab`
   - 入参包含：`word_id`、`source_article_id`
   - 存储约束：`(user_id, word_id, source_article_id)` 唯一
   - 展示约束：`GET /api/v1/me/vocab` 默认按词去重展示
3. `POST /api/v1/articles/{article_id}/favorite` / `DELETE /api/v1/articles/{article_id}/favorite`
   - 同一用户同一文章幂等，收藏与取消收藏均记录状态变更时间
4. `GET /api/v1/articles/{article_id}/audio`
   - 返回 `status`：`pending|processing|ready|failed`
5. `GET /api/v1/analytics/dashboard/summary`（全局指标）
6. `GET /api/v1/analytics/dashboard/me-summary`（个人指标）
   - Query：`days`（默认 7，范围 1-90）
   - Response：`event_total`、`dau`、`event_counts`、`timeline`、`top_words`

---

## 8. 后台管理系统（运营/教研）

## 8.1 技术

- 前端：React + Ant Design + TanStack Query
- 后端：复用 FastAPI `admin` 模块
- 权限：RBAC（管理员、教研、运营）

## 8.2 功能

- 文章 CRUD、标签管理（阶段/难度/主题）
- 重点句解析录入
- 词汇与释义管理
- 小测题目管理
- 内容审核与发布流程

---

## 9. TTS 与词典能力

## 9.1 TTS 方案

V1 推荐直接接入云 TTS（例如火山、腾讯、阿里云、Azure 任一），通过异步任务生成并缓存音频 URL：

- 发布文章后触发音频生成任务
- 成功后写回 `article_audio_url` 与分段时间戳
- 客户端读取时间戳实现段落高亮联动
- 音频状态机：`pending -> processing -> ready | failed`
- 失败重试：最多 3 次（指数退避）
- 告警触发：同一文章重试耗尽或 10 分钟仍未进入 `ready` 状态
- 客户端降级：`failed` 时隐藏播放控件，展示“稍后重试/使用文本阅读”

## 9.2 词典来源

- 初期可接入第三方词典 API + 本地常用词库缓存
- 高频词落库到 `words` 表，降低查询延迟和第三方依赖风险

---

## 10. 安全与合规

- 密码：`Argon2` 哈希存储
- 传输：全站 HTTPS
- 鉴权：JWT 短期 Access + 长期 Refresh
- Token 轮换：每次刷新均轮换 Refresh Token，旧 Token 立即失效
- Token 撤销：`/auth/logout` 将当前 Refresh Token 加入撤销集合并立即失效
- 限流：登录/查词/提交接口防刷
- 数据最小化：仅保留必要学习行为数据
- 账号生命周期：支持用户发起账号删除，先软删（不可登录），30 天保留期后硬删个人数据
- 审计日志：后台发布、编辑、删除操作全记录

---

## 11. 性能目标与容量预估

结合 PRD 非功能目标，后端设计目标：

- 首页接口 P95 < 300ms
- 文章详情接口 P95 < 400ms
- 点词查询 P95 < 200ms（命中缓存）
- 小测提交接口 P95 < 300ms

初期容量建议（可支撑 3-10 万注册用户）：

- 应用实例：2 台（2C4G）起步
- PostgreSQL：4C8G
- Redis：2C4G
- 对象存储按量扩展

---

## 12. 测试与质量保障

## 12.1 后端

- 单元测试：`pytest`
- API 集成测试：`pytest + httpx`
- 数据迁移测试：Alembic 自动化校验

## 12.2 客户端

- 单元测试：`flutter test`
- 关键流程集成测试：阅读 -> 小测 -> 生词收藏
- 真机回归：低端 Android + 主流 iOS 机型

## 12.3 质量门禁

- PR 必须通过 Lint + Test
- 主分支只允许通过 CI 的合并请求
- 发布需附版本变更说明与回滚策略

## 12.4 规则级验收用例（Given-When-Then）

1. 同词多文章来源
   - Given 用户已收藏 `word_id=1001` 来源文章 A
   - When 用户在文章 B 再次收藏 `word_id=1001`
   - Then 数据层新增第二条来源记录；默认列表按词去重展示 1 条，按 `source_article_id` 可分别查询 A/B 来源
2. 收藏文章链路
   - Given 用户未收藏文章 X
   - When 依次调用收藏、重复收藏、取消收藏接口
   - Then 重复收藏幂等，取消成功，阅读历史保持不变
3. 列表分页与排序
   - Given 内容库已有多篇文章
   - When 以 `sort=latest` 请求 `page=1,size=20` 和 `page=2,size=20`
   - Then 返回字段完整，`size<=50`，两页数据无重复且顺序稳定
4. TTS 失败态降级
   - Given 某文章 TTS 连续失败并达到重试上限
   - When 客户端请求音频状态
   - Then 接口返回 `failed`，客户端隐藏播放控件并提示文本阅读
5. 登出后 Token 失效
   - Given 用户已登录并持有 Refresh Token
   - When 调用 `/auth/logout` 后再次调用 `/auth/refresh`
   - Then 刷新失败并返回未授权错误

---

## 13. 部署与 CI/CD

## 13.1 环境划分

- `dev`：开发联调
- `staging`：预发布验证
- `prod`：生产

## 13.2 流水线

1. 提交代码触发 CI
2. 执行 Lint + Test
3. 构建 Docker 镜像
4. 发布到 staging 自动冒烟
5. 人工确认后发布 prod

---

## 14. 里程碑建议（8-12 周）

1. 第 1-2 周：项目初始化、鉴权、数据库骨架、后台基础能力
2. 第 3-5 周：文章阅读页、点词释义、句子解析、音频播放
3. 第 6-7 周：小测、生词本、学习记录
4. 第 8-9 周：后台内容流程、埋点、监控告警
5. 第 10-12 周：压力测试、修复、灰度上线

---

## 15. V1 技术边界（明确不做）

- 不做微服务拆分
- 不做复杂推荐算法
- 不做跟读评分模型
- 不做复杂记忆曲线引擎
- 不做多端实时同步高级能力

以上能力在 V1.1/V2.0 按数据反馈逐步引入。

---

## 16. 结论

本方案选择 `Flutter + FastAPI + PostgreSQL + Redis + S3` 作为 MVP 最优组合，优势是：

- 上线速度快，和 PRD 目标一致
- 支持阅读核心闭环，技术风险可控
- 后续可平滑演进到个性化推荐、AI 解析与跟读能力

可先按本技术文档启动开发，再在第一个版本上线后依据留存与功能数据做二次技术迭代。



