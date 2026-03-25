# EnglishAPP

当前仓库已移除英语文章阅读、朗读、小测、在线文章导入与后台文章管理功能，保留的主要能力为：

- 用户注册、登录、登出与账号管理
- 生词本查看与掌握状态管理
- 用户行为统计与个人数据查看
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
uvicorn app.main:app --reload --port 8000
```

## Windows 客户端启动

```powershell
cd desktop_app
flutter pub get
flutter run -d windows
```

## Demo 账号

- Email: `demo@englishapp.dev`
- Password: `Passw0rd!`

## 测试

```powershell
cd backend
python -m pytest tests -q
```

```powershell
cd desktop_app
flutter analyze
```
