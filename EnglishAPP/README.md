# EnglishAPP

基于 PRD/TECH 的 Windows-first 英语分级阅读项目。

## 项目结构

```text
EnglishAPP/
  backend/        # FastAPI 服务端（已接入 SQLAlchemy + Alembic + JWT）
  desktop_app/    # Flutter Windows 客户端（V1 骨架）
  APP_UI_ARCH.md
  BACKEND_IMPL_SPEC.md
  TECH_DESIGN.md
  TASK_SLICES.md
  英语分级阅读软件prd.md
```

## 1) 后端启动（FastAPI）

```powershell
cd backend
python -m pip install -e .[dev]
uvicorn app.main:app --reload --port 8000
```

访问：

- API: `http://127.0.0.1:8000/api/v1/...`
- Swagger: `http://127.0.0.1:8000/docs`

说明：默认使用本地 `sqlite:///./englishapp.db` 便于快速启动；生产环境请在 `.env` 提供 PostgreSQL 连接。

## 2) 数据库迁移（Alembic）

```powershell
cd backend
alembic -c alembic.ini upgrade head
```

当前已提供初始化迁移：`backend/alembic/versions/0001_initial_schema.py`。

## 3) Windows 客户端启动（Flutter）

当前仓库已提供 `desktop_app/lib`、主题与路由骨架。
如果本机尚未安装 Flutter，请先安装 Flutter SDK 并启用 Windows desktop：

```powershell
flutter config --enable-windows-desktop
cd desktop_app
flutter pub get
flutter run -d windows
```

## 4) Demo 账号

- Email: `demo@englishapp.dev`
- Password: `Passw0rd!`

## 5) 测试

```powershell
cd backend
python -m pytest tests -q
```

桌面端基础检查：

```powershell
cd desktop_app
flutter analyze
flutter test
```

## 6) 环境变量

- 根目录：`.env.example`
- 后端：`backend/.env.example`

可按需复制为 `.env` 使用。

## 7) 当前已落地内容

- Windows-first 的客户端架构与统一主题骨架（Noto Sans）
- Windows 客户端已接入真实 API：登录、首页推荐、文章列表/详情、我的统计、收藏、生词本
- FastAPI 模块化 API（auth/content/vocab/favorite/reading/quiz/me/home）
- SQLAlchemy 模型、自动建表、种子数据
- JWT 鉴权（登录、刷新轮换、登出撤销、受保护 `/users/me`）
- Alembic 迁移骨架与初始迁移
- 后端集成测试（30 条，已通过）

## 8) CI 与发布

- 代码仓库已按 `backend` / `desktop_app` 两条链路准备 CI 入口
- 发布与回滚流程见 [发布与回滚SOP.md](D:/AI/EnglishAPP/发布与回滚SOP.md)

