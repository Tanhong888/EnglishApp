# 英语分级阅读 App 界面架构规格（V1）

## 1. 文档目标

把 PRD 与 TECH 里的功能，落成可直接开发的 Flutter 界面规格，重点保证：

- 视觉简约美观
- 字体统一
- 信息层级清晰
- 状态反馈一致

---

## 2. 设计原则

1. 简约优先：单屏只保留主任务，弱化装饰。
2. 阅读优先：正文与学习动作（查词、朗读、解析、小测）高于次要信息。
3. 一致优先：间距、字体、按钮、卡片、弹窗统一规范。
4. 可恢复优先：错误场景都提供重试或降级路径。

---

## 3. 视觉与字体规范

## 3.1 统一字体方案（全局）

- 字体家族：`Noto Sans`
- 字重：`400 / 500 / 600`
- Flutter 全局：`ThemeData(fontFamily: 'NotoSans')`
- 禁止页面级单独改字体；仅允许调字重与字号。

说明：`Noto Sans` 同时覆盖中英文，跨 iOS/Android 一致性高，符合“字体统一”要求。

## 3.2 色彩 Token（简约风）

- `color.bg = #F7F8FA`
- `color.surface = #FFFFFF`
- `color.text.primary = #111827`
- `color.text.secondary = #6B7280`
- `color.brand = #2563EB`
- `color.brand.soft = #E8F0FF`
- `color.success = #16A34A`
- `color.warning = #D97706`
- `color.error = #DC2626`
- `color.border = #E5E7EB`

## 3.3 字号与间距 Token

- 标题大：`24/32`
- 标题中：`20/28`
- 标题小：`18/26`
- 正文：`16/24`
- 次级正文：`14/22`
- 说明文本：`12/18`
- 统一间距：`4pt` 栅格，常用 `8 / 12 / 16 / 20 / 24`
- 圆角：`12`（卡片），`10`（输入），`999`（胶囊标签）

---

## 4. 信息架构与路由

## 4.1 底部主导航（4 Tab）

1. 首页 `/home`
2. 分级阅读 `/articles`
3. 生词本 `/vocab`
4. 我的 `/me`

## 4.2 顶层路由

- `/splash`
- `/login`
- `/home`
- `/articles`
- `/articles/:articleId`
- `/articles/:articleId/analysis`
- `/articles/:articleId/quiz`
- `/quiz/attempts/:attemptId/result`
- `/vocab`
- `/vocab/:entryId`
- `/me`
- `/me/favorites`
- `/me/history`
- `/settings`

## 4.3 路由守卫

- 未登录仅允许访问：`/splash`、`/login`
- 已登录访问 `/login` 自动跳 `/home`
- Token 过期优先尝试刷新；刷新失败跳 `/login`

---

## 5. 页面架构（按核心流程）

## 5.1 首页 `/home`

模块顺序：

1. 顶部欢迎与搜索入口（可先占位）
2. 今日推荐卡片（主 CTA：继续学习）
3. 分级快捷入口（四级/六级/考研）
4. 热门主题入口
5. 最近学习记录
6. 生词本快捷入口

关键交互：

- 点击推荐卡片进入阅读详情
- 点击最近学习回到断点位置

## 5.2 分级阅读列表 `/articles`

模块：

1. 筛选条（阶段/难度/主题）
2. 排序条（推荐/最新/最热）
3. 文章卡片列表（分页加载）

分页契约：

- 默认 `page=1,size=20`
- 上拉加载下一页
- `size` 最大 50
- 有 `has_next=false` 时显示“已到底部”

## 5.3 阅读详情 `/articles/:articleId`

模块：

1. 顶部信息区（标题、难度、主题、时长、收藏）
2. 正文区（段落 + 可点击词 + 重点句高亮）
3. 底部工具栏（全文播放/分段播放/句子解析/加入生词本/开始小测）

关键交互：

- 点击单词弹出释义卡片（不跳页）
- 点击重点句进入解析浮层或页面
- 收藏按钮幂等

## 5.4 小测与结果

- 小测页：题干、选项、进度、提交按钮
- 结果页：正确率、错题回顾、返回文章、下一篇推荐

## 5.5 生词本 `/vocab`

模块：

1. 搜索框
2. 来源筛选（文章来源）
3. 生词列表（默认按词去重）
4. 单词操作（标记掌握/取消收藏）

## 5.6 我的 `/me`

模块：

1. 学习统计（阅读篇数、学习天数、生词数、完成率）
2. 最近学习记录
3. 收藏文章入口
4. 设置入口

---

## 6. 全局状态与反馈规范

每个页面必须覆盖 5 种状态：

1. `loading`：骨架屏
2. `success`：正常内容
3. `empty`：空态插画 + 文案 + 主按钮
4. `error`：错误文案 + 重试按钮
5. `offline`：弱网提示 + 降级策略

禁止行为：

- 使用纯 Toast 代替错误恢复动作
- 页面无反馈直接失败

---

## 7. 关键组件清单

- `AppScaffold`：统一页头与安全区
- `SectionCard`：首页模块卡片容器
- `ArticleCard`：列表卡片
- `FilterChips`：筛选控件
- `WordMeaningSheet`：点词释义弹层
- `AudioControlBar`：朗读控制条
- `SentenceHighlightText`：重点句高亮文本
- `EmptyState` / `ErrorState` / `LoadingSkeleton`

---

## 8. 音频失败降级（强制）

当 `GET /articles/{articleId}/audio` 返回 `failed`：

1. 隐藏播放主按钮
2. 显示文案：`音频暂不可用，可先进行文本阅读`
3. 提供按钮：`稍后重试`
4. 不阻塞点词、解析、小测链路

---

## 9. 前端状态管理分层（Riverpod）

- `presentation`：页面与组件（仅 UI）
- `application`：状态控制器（业务流程）
- `domain`：实体与用例
- `infrastructure`：API/Hive/音频插件适配

Provider 规范：

- 页面级状态：`AsyncValue<T>`
- 交互动作：`StateNotifier` 或 `Notifier`
- 全局用户态：`authProvider`

---

## 10. UI 验收口径（V1）

1. 全局字体仅使用 `Noto Sans`。
2. 阅读页核心动作（查词/朗读/解析/小测）3 步内可达。
3. 列表分页、收藏、生词筛选、音频失败降级均有明确反馈。
4. 深色模式不在 V1 范围，先保证浅色主题一致性。

