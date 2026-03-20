# WJX Auto-Filler (WAF) 技术方案 V1.0

## 1. 概述
- **目标**：实现一个可视化配置、可控分布、可批量提交的问卷星自动填写工具，满足 PRD 中的解析能力、数据控制、真实模拟和高效交互要求。
- **约束**：必须严格模拟人类行为、支持 IP/UA 伪装、单机至少 5 个并发 Session、可长时间稳定运行、可导出任务报告。
- **整体方案**：采用 `Web 前端 (Vue3 + Naive UI)` + `后端 API (FastAPI)` + `自动化执行引擎 (Playwright Worker)` 的三层架构，数据集中存储在 PostgreSQL，任务调度与状态缓存使用 Redis。

```
[Browser UI] --REST/WebSocket--> [FastAPI Service] --队列--> [Playwright Worker Pool]
      |                                  |                     |
      |                                  |                     +--> Proxy/UA 管理器
      |                                  |                     +--> 模拟执行器
      |                                  +--> PostgreSQL/Redis +--> 日志/报告生成
```

## 2. 组件架构
| 组件 | 技术栈 | 责任 |
| --- | --- | --- |
| **UI 客户端** | Vue 3 + Vite + Naive UI | URL 输入、题目权重配置、进度与日志展示、任务控制。 |
| **API 网关** | FastAPI + Uvicorn | 提供问卷解析、策略保存、任务编排、日志查询、报告导出接口。 |
| **策略/调度服务** | FastAPI 内部模块 + Redis | 归一化概率、生成执行计划、投递至 Playwright worker 队列、控制并发。 |
| **Playwright Worker** | Python + Playwright + asyncio | 拉取任务、启动无头浏览器、模拟操作、提交问卷、上报结果。 |
| **Proxy & UA 管理器** | Python 模块 | 维护可用代理池、轮询切换 IP、随机 UA。 |
| **数据存储** | PostgreSQL + SQLModel/SQLAlchemy | 存储问卷结构、任务配置、提交记录、操作日志、模板库。 |
| **文件/模板库** | S3 兼容对象存储或本地目录 | 存放填空题文本库、截图、导出报告。 |

## 3. 关键模块设计
### 3.1 问卷解析模块
- 输入：`POST /api/questionnaire/parse`，参数为问卷 URL。
- 步骤：URL 校验 → 获取问卷 HTML（requests + cookie jar）→ 利用 `BeautifulSoup + 正则` 提取题目、选项、ID、题型 → 标准化 JSON。
- 容错：检测密码页/截止页文本；当解析失败返回错误码（`QUESTIONNAIRE_LOCKED`、`QUESTIONNAIRE_CLOSED` 等）。
- 缓存：解析结果以 `questionnaire_hash` 作为 key 缓存 10 分钟，避免重复解析。

### 3.2 策略配置模块
- 前端根据解析结果生成题卡，支持滑块、输入框、批量粘贴。
- 后端 `StrategyService` 负责：
  - 单选题概率归一化（超出时自动缩放，缺失时平均填充）。
  - 多选题组合策略：支持 `per_option_probability` 与 `min/max selection` 两种模式，内部使用加权随机 + 约束求解（先决定选择数量，再根据独立概率抽样）。
  - 填空题数据源：`/api/templates` 上传/管理文本库，按类别随机抽取。
- 任务创建：`POST /api/tasks`，保存问卷引用、份数、并发上限、代理策略等，状态置为 `PENDING`。

### 3.3 调度与执行
- `Scheduler` 轮询 PENDING/PAUSED 任务，依据：
  - 可用 worker 数量（来自 Redis 统计）。
  - 并发上限、IP 轮换策略、速率限制（份/分钟）。
  - 每次调度生成 `ExecutionPlan`（包含问卷结构、策略快照、随机种子、代理/UA 指令）。
- 执行流程（worker）：
  1. 初始化 Playwright `chromium`，根据 task 指令设置 `User-Agent`、`proxy`、`viewport`。
  2. `Page` 级 hook 实现：加载等待、网络错误重试、截图（仅 on-error）。
  3. 模拟行为：
     - 逐题：根据策略得出当前题目的选择结果。
     - 鼠标轨迹：使用贝塞尔曲线在 1.5-2.5s 内移动到选项。
     - 随机停顿：`random.normalvariate(3, 0.5)`，最小 1s。
     - 分页：寻找“下一页/提交”按钮，点击后 `await page.wait_for_load_state("networkidle")`。
  4. 提交成功后写入 `submission_record`，失败则捕获截图和错误原因。
- 结束条件：达到目标份数或任务被用户终止，任务进入 `COMPLETED/FAILED/CANCELED`。

### 3.4 IP/UA 策略
- 代理来源支持三类：静态代理池、第三方 API、内网自建代理。
- `ProxyPool` 维护可用列表（健康检查成功才可用），策略配置字段：
  - `rotation_interval`：每 N 份切换一次。
  - `cooldown_minutes`：被使用的代理在冷却期内不可再次分配。
- `UAProvider` 维护 PC/Mobile UA 列表，支持按任务级别锁定或每次随机。

### 3.5 日志与报告
- 实时日志通过 WebSocket 推送（Redis Pub/Sub），等级：INFO（进度）、WARN（重试）、ERROR（失败）。
- 任务完成后生成 `TaskReport`：
  - 总览：成功/失败数、平均耗时、使用代理统计。
  - 明细：每份提交的时间线、IP、UA、耗时。
  - 导出：`/api/tasks/{id}/report`，返回 JSON + 可选 PDF。

## 4. 数据模型
| 表 | 主要字段 | 说明 |
| --- | --- | --- |
| `questionnaires` | `id`, `url`, `hash`, `title`, `structure_json`, `status`, `parsed_at` | 保存一次解析结果，`structure_json` 包含题目数组。 |
| `tasks` | `id`, `questionnaire_id`, `target_count`, `concurrency`, `proxy_strategy`, `ua_strategy`, `status`, `created_by` | 任务主表。 |
| `strategies` | `task_id`, `question_id`, `type`, `payload_json` | 每题策略（单选概率数组、多选约束、填空模板组等）。 |
| `template_libraries` | `id`, `name`, `category`, `values` | 填空题数据源；`values` 可为 JSON/CSV。 |
| `executions` | `id`, `task_id`, `worker_id`, `state`, `started_at`, `finished_at`, `error_type`, `screenshot_path` | worker 执行实例。 |
| `submission_records` | `id`, `task_id`, `questionnaire_id`, `proxy_id`, `ua`, `duration_ms`, `result`, `payload_digest` | 每份提交记录。 |
| `logs` | `id`, `task_id`, `level`, `message`, `created_at`, `extra` | 前端实时显示与审计。 |

## 5. 接口设计（示例）
| 方法 | 路径 | 描述 |
| --- | --- | --- |
| `POST` | `/api/questionnaire/parse` | 解析问卷，返回结构。 |
| `POST` | `/api/tasks` | 创建任务（含策略）。 |
| `GET` | `/api/tasks/{id}` | 查询任务详情与实时统计。 |
| `POST` | `/api/tasks/{id}/control` | 操作：`start/pause/stop`. |
| `GET` | `/api/tasks/{id}/logs` | 分页查询日志；WebSocket 订阅实时日志。 |
| `GET` | `/api/tasks/{id}/report` | 导出报告。 |
| `POST` | `/api/templates` | 上传填空题模板库。 |

认证可用简单 Token/账号密码，后续可扩展 OAuth。

## 6. 核心算法与策略
1. **概率归一化**：`normalized = raw / sum(raw)`，若 sum=0 则均分；UI 上实时校验并提示。
2. **多选约束**：
   - 步骤一：依据 `min/max` 利用加权随机决定勾选数量。
   - 步骤二：按照独立概率排序，用轮盘赌算法抽取候选，若不足则随机补齐。
3. **填空生成**：针对姓名/手机号等字段配置不同模板正则，支持自定义 Python 表达式（受限沙箱）或从库中随机抽取。
4. **节奏控制**：任务层面设置 `rate_limit = target_per_minute`，在调度时根据当前成功率适当增减。

## 7. 非功能实现手段
- **并发 ≥5 Session**：worker 进程池默认大小 = min(配置并发, CPU 核数)，Playwright `BrowserContext` 复用浏览器实例以降低开销。
- **容错**：网络错误自动重试 3 次；若遇验证码/风控，记录并将任务置为 `ATTENTION_REQUIRED`。
- **稳定性**：健康检查探活（/healthz），监控指标（Active tasks、成功率、平均耗时）暴露 Prometheus。

## 8. 部署与运维
- **开发**：Docker Compose 启动 `frontend`, `api`, `worker`, `postgres`, `redis`.
- **生产**：
  - API 服务以 `gunicorn -k uvicorn.workers.UvicornWorker` 运行。
  - Worker 采用 `systemd` 或容器化横向扩展，代理池可独立服务。
  - 日志集中到 Loki/ELK，截图与报告上传到对象存储。
- **桌面封装**：若需离线版，可将 API + Worker 打包为 PyInstaller，可视化层用 Electron 调用本地 HTTP API。

## 9. 安全与合规
- 所有配置与任务历史需基于 RBAC 控制（操作员/管理员）。
- 存储代理账号时使用 KMS 加密，避免明文。
- 提供任务级审计日志（谁在何时创建、启动、终止任务）。

## 10. 风险与待定问题
1. **问卷星防刷策略**：若后续引入图形验证码，需要额外集成打码平台或人工介入。
2. **代理资源稳定性**：需确认可用代理供应和成本，避免 IP 被封导致成功率下降。
3. **模板库敏感信息**：需建立数据脱敏策略，防止用户上传真实隐私数据被误用。
4. **桌面版 vs Web 版**：若最终决定桌面化，需评估离线运行的授权、更新、日志采集方案。

> 本技术方案覆盖了 PRD 所有功能与非功能需求，为后续评审、排期与实现提供依据。
