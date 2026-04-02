# EnglishAPP

当前仓库以实际代码为准，当前可用的主要能力为：

- 用户注册、登录、登出与账号管理
- 英语文章阅读、重点句解析与基础阅读小测
- 点词查词、生词本查看与掌握状态管理
- 个人学习数据与行为统计查看
- 外部文章搜索导入、文章编辑与发布到阅读库
- FastAPI 后端与 Flutter Windows 客户端基础架构

## 项目结构

```text
EnglishAPP/
  backend/        # FastAPI 服务端
  desktop_app/    # Flutter Windows 客户端
  README.md
```

## 后端启动

```powershell
cd backend
python -m pip install -e .[dev]
Copy-Item .env.example .env
uvicorn app.main:app --reload --port 8000
```

建议至少显式配置以下环境变量：

- `JWT_SECRET_KEY`
- `ADMIN_EMAILS`
- `SEED_DEMO_DATA`
- `CORS_ALLOWED_ORIGINS`

## Windows 客户端启动

```powershell
cd desktop_app
flutter pub get
flutter run -d windows
```

## Demo 账号

仅开发环境默认种入：

- Email: `demo@englishapp.dev`
- Password: `Passw0rd!`

生产环境请关闭 `SEED_DEMO_DATA`，并自行创建管理员账号。

## 测试

```powershell
cd backend
python -m pytest tests -q
```

```powershell
cd desktop_app
flutter analyze
```
