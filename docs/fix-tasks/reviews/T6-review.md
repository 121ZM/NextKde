# T6 审查报告 — 不可见渲染收敛

日期：2026-09-20
分支：test/t1-t4
审查：两轮子代理只读审查（第一轮发现 2 个 major，修复后第二轮通过）

## 改动摘要

| 文件 | 改动 |
|---|---|
| `DockIcon.qml` | `ContextMenu`/`DockWindowPreview` 由每图标常驻改为 `Component` + `createObject` 懒加载（`ensureContextMenuLoaded()`/`ensurePreviewLoaded()`），未触发前不存在 QWindow |
| `DockWindowPreview.qml` | 两个缩略图 `Image` 去掉 `cache:false`，加 `sourceSize`（thumbnailBox×2 ≈ 416×296），不再全尺寸解码 |
| `DockInfoCarousel.qml` | 4 个 page 新增 `pageActive` 绑定（`page===X && hasXxx`） |
| `DockMusicPlayer.qml` | 新增 `pageActive`（默认 true），两处 marquee `running` 追加 `widget.pageActive &&` |
| `DockClockWidget.qml` | 新增 `pageActive`，`ambientTexture.live` 改为 `widget.pageActive`（非当前页停止逐帧重采样） |
| `DockTemperatureWidget.qml` | 新增 `pageActive`，activityCanvas 三个 `requestPaint` 门控 + `onPageActiveChanged` 补一帧 |
| `DockWeatherWidget.qml` | 新增 `pageActive`，cloud/sun/rain 三个装饰层 `visible` 追加 `pageActive` |
| `DeskCenterWindow.qml` | 13 个卡片 Loader `active` 追加 `card.visible &&`；music 卡 250ms Timer 与 musicNotes 动画追加 `card.visible` 门控 |
| `OverviewWindow.qml` | `previewImg` 加 `asynchronous:true`；删除点击后多余 `requestThumbnail`；打开时缩略图请求改 80ms pacer Timer（每 tick ≤3 个），不再瞬时扇出 |

## 第一轮审查发现并已修复

- **major**：in-flight 计数队列依赖 `thumbnailRevision` 递减，失败/被拒请求不发事件 → 队列永久卡死；无关窗口关闭的 prune 也会误递减。→ 重写为无结算信号的节奏队列（80ms Timer，每 tick 发 3 个），失败请求只留占位符。
- **major**：同上误递减路径已随 in-flight 计数整体删除。

## 第二轮审查结论

通过。无 blocker/major；minor 提示（`preview` 属性可为 null 已防护、popup 首用后常驻为预期折衷、`cache` 移除依赖 KWinBridge 递增文件名去重）均非缺陷。

## 验证记录

- `./tools/kosctl build`：通过（ninja no-op + mo/ts 生成）。
- `./tools/qmllint-changed.mjs`：9 文件无语法错误。
- `node tools/qml-duplicate-handlers.mjs`：169 文件无重复声明。
- `kosctl install && kosctl start`：shell 重启后无 QML 错误；两次 `kosctl start` 中旧进程退出路径崩溃（`~ShapeProtocol` → `wl_proxy_marshal` on dead proxy，pid 33965/35035 栈一致）为既有问题，与本改动无关。
- 空闲 CPU：qs pid 34007 在 5s 窗口内消耗 2 jiffies ≈ 0.4% CPU。
- 未做实际右键/hover 手动验证（无交互环境）；逻辑路径保持原有 `openDockPopup` 协调器，仅实例化时机后移。

## 验收对照

- ☑ DockInfoCarousel 非当前页 marquee（music compact/hover）、live ShaderEffectSource（clock）、Canvas repaint（temperature）、装饰层（weather）停止
- ☑ DockIcon 不右键/不悬停时无对应 popup QWindow（懒加载）
- ☑ 预览缩略图不再全尺寸解码（sourceSize 416×296，bridge 侧已压 720×440）
- ☑ DeskCenter 隐藏卡片（placement=null → card.visible=false）其 Loader 卸载、Timer/动画停止
