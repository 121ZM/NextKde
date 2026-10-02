# 窗口按钮：测量、缓存与分发

> **已废弃（2026-09-28）。** 下文第 1、2 步（像素扫描定位 + 外观签名缓存）已实现并被推翻：
> 扫描在真实窗口上不可靠 —— 自绘标题栏左端的 logo 比右侧真正的控件"信号"更强，而钉钉那类
> 应用的控件是细笔画、间距很大，与工具包画的实心圆按钮毫无共同之处，两者都无法用同一组阈值
> 分辨。`integrations/kwin/kos-bridge` 已改回配置固定的 `offset` 定位，只保留"读真实像素定
> 明暗"这一项（`windowbuttons/titlebarmetrics.cpp`），因为标题栏的颜色是整个栏的属性，与栏
> 内有什么无关。下文的协议调研（为什么无法"问"只能"量"）仍然有效，故保留。

## 背景

`integrations/kwin/kos-bridge` 现在把一块**不透明圆角面板**盖在 CSD 窗口的标题栏上，位置
100% 由 `~/.config/kos/window-buttons.json` 算出（`windowbuttons/panelgeometry.cpp:panelRect()`，
后加的拖拽微调写在 `~/.local/share/kos/window-buttons-rules.json` 里），与应用
实际把按钮画在哪里没有任何关系。

两个可观测的缺陷：

1. **覆盖区域不准。** 面板高 = `buttonSize + 2×panelPadding`，默认 23px；而 Breeze GTK4 的
   headerbar `min-height` 是 46px，GTK 把控件在其中垂直居中，24px 的控件纵向跨
   `[11, 35]`。面板底边在 29 —— 应用自己的按钮从下沿露出 6px。横向同理，只是碰巧接近。
   **每个工具包、每个主题、每个自绘标题栏的应用都不一样，不存在一组对所有应用成立的 offset。**

2. **明暗判断原理上不可能对。** `windowIsDark()` 读 `Window::palette()`，而
   `Window::colorScheme()` 的文档原文是 *"the default palette from **kdeglobals**"* —— 这是
   **KDE 自己的配色方案**，与 GTK 应用的 headerbar 主题无关。`preferredColorScheme()` 是
   `virtual`，X11 下能从 `_KDE_NET_WM_COLOR_SCHEME` 拿到应用请求的配色，**Wayland 下没有对应
   通道**。所以该函数在 Wayland 上返回的实际是全局配色，per-window 差异约等于零。

### 为什么不能"问"，只能"量"

合成器无法得知 CSD 窗口的标题栏几何。逐条排除过：

| 来源 | 携带的信息 |
| --- | --- |
| `xdg-decoration` / `org_kde_kwin_server_decoration` | 只有 mode（client/server） |
| `xdg_toplevel.set_window_geometry` | 一个矩形 = 可见窗口边界 |
| `_GTK_FRAME_EXTENTS` | 四个值 = **阴影边距**，且仅 X11 |
| `_NET_FRAME_EXTENTS` | WM 画的边框宽度 |
| `GtkHeaderBar` / `GtkWindowControls` | 进程内，不导出 |
| `gtk-decoration-layout` | 是**输入**（告诉应用怎么排），不是回读 |

KWin 侧同样堵死：`EffectWindow::decoration()` 对 CSD 窗口返回 null —— `XdgToplevelWindow::
configureDecoration()` 在 `DecorationMode::Client` 时会 `destroyDecoration()`。这也是
**kos-bridge 必须是 effect 而不能是 decoration 插件**的原因：KDecoration 插件只在 Server 模式
被实例化，macOS 风格的装饰插件永远画不到 CSD 窗口上。

**结论：唯一可行的对齐方式是测量合成后的像素。**

### 为什么不用模型

本方案**不使用**神经网络，理由记录在此以免反复讨论：

- 要预测的三件事里，明暗是均值/中位数的算术；headerbar 底边和按钮簇包围盒是**受限输入上的
  边缘检测** —— 输入是一条约 40px 高、几千像素宽的横带，结构高度规整。经典 CV 能确定性地解
  掉，每一步可解释。
- 模型失败时是**自信地错**：给出一块盖住用户 UI 的矩形。确定性算法失败时能读日志、加
  per-app override、推因果。
- 这跑在 KWin 渲染路径上。测量每窗口一次，延迟可忍；**可变性不可忍** —— 面板必须每帧落在同一
  个位置。
- 往 KWin 进程里引入推理运行时（ONNX Runtime 等）会显著增加崩溃面。这个项目已经被 KWin
  崩溃咬过一次（shader 编译失败 → `reconfigure` 断言 → `abort` 掉 `kwin_wayland`）。
- 现有 `experiments/depth-poc` 的 Depth Anything V2 是**逐像素深度**模型，本任务没有深度语义
  可用。它的**架构模式**（进程外推理 + 内容哈希缓存）才是值得借鉴的部分 —— 但本方案连推理都
  不需要。

"自动学习"由下面的**外观签名库**承担：它是基于实例的学习（最近邻），可审计、可人眼验证。

---

## 设计原则

1. **测量是权威，库只是种子。** 任何库条目都可能过期；过期条目只允许影响**首帧**，随后必须被
   测量覆盖。反过来把库当权威，等于把 bug 固化成数据库。
2. **测量失败降级为"不画"，而不是"画错"。** 今天的实现是无论如何都画，所以错的时候是可见的
   错。新实现里，量不出按钮簇就不画面板。
3. **程序永不写用户手写的文件。** `~/.config/kos/window-buttons.json` 是人写的意图；机器学到的
   东西写到别处。
4. **渲染路径不碰模型、不碰网络、不做 IO。** 所有重活都在测量阶段一次性完成。
5. **确定性。** 同一窗口的测量结果必须稳定；不稳定就说明启发式不可信，应落到"待确认"而不是
   抖动。

---

## 第 1 步：测量（纯收益，无新概念）

**目标：修掉覆盖不准和明暗不准。不引入库。**

### 新增

- `integrations/kwin/kos-bridge/windowbuttons/titlebarmetrics.h/.cpp`
  - `struct TitlebarMetrics { qreal headerbarBottom; QRectF buttonBox; bool dark; qreal confidence; bool valid; }`
  - `TitlebarMetrics measure(renderTarget, viewport, window, clipRegion, sideHint)`
- `buttonrenderer` 增加 `QHash<EffectWindow*, TitlebarMetrics> m_metrics` 与失效逻辑。

### 读数时机（关键）

在 `ButtonRenderer::paint()` **最开头**读，此时 `Effect::drawWindow()` 已经放过窗口自己绘制，
而**我们的面板还没画**，所以没有自污染。

今天的实现之所以"闪烁"，是因为它每 200ms 重采且采的是面板底下的区域 —— 采到了自己上一帧画
上去的面板。这两个错误都要避免。

**首帧保护：** 窗口刚出现时内容可能还没画好（读到全黑/全透明）。若测量结果退化
（方差低于阈值），不要采纳，标记为待重试，在随后若干帧内重试；超过上限则判定 `valid=false`。

### 算法

设探测条带为窗口顶部 `y ∈ [0, min(H, 80·scale))`、全宽，映射到设备坐标后与 `clip` 相交。

1. **headerbar 底边** —— 逐行横向边缘能量
   `rowEdge(y) = Σ_x |luma(y+1,x) − luma(y,x)|`
   在合理区间（`y ∈ [16·scale, 80·scale]`）取 `argmax`。
   `confidence` = 峰值 / 次峰比 或 峰值 / 均值。
2. **按钮簇包围盒** —— 在 `y ∈ [0, headerbarBottom]` 内逐列梯度能量
   `colEdge(x) = Σ_y |luma(y,x+1) − luma(y,x)|`
   取靠 `sideHint` 那一侧的一段连续高能量列，作为 x 范围；y 范围取该段内点状结构（圆/方块）的
   垂直跨度。`sideHint` 复用现有 `resolveSide()` 的结论。
3. **明暗** —— 在 headerbar 内、**排除按钮簇、排除中间三分之一**（标题文字所在）的剩余区域取
   luma **中位数**。中位数抗文字和图标的极值，均值不行。

### 多启发式投票

底边检测跑 3–4 个**互相独立**的判据（行边缘能量、行方差、颜色突变、alpha 突变），
**要求多数一致**才采纳。同意度直接作为 `confidence`，用来决定"能不能信"和"要不要问用户"。

比单一判据好在：可解释、可调试，且同意度天然是置信度。

### 失效条件

- 窗口 resize → 重测（`position: right` 的按钮簇 x 依赖窗口宽度）
- 输出缩放变化 → 重测
- `reconfigure()` → 清空全部缓存

### 验证

拿 QQ / 微信 / WPS / PhpStorm / VS Code 逐个看面板是否贴合，以及明暗是否正确。
这一步做完，"覆盖不准"和"明暗猜不准"两个问题应当都消失，且不依赖任何库。

---

## 第 2 步：外观签名 + 本地缓存

**目标：让测量结果跨窗口复用，避免每个新窗口都重测。**

### 为什么键是"外观"而不是"身份"

身份键在这批应用上**全部失效**，这是实测结论：

```
QQ      exe=/tmp/.mount_linuxqbGABc7/qq      ← AppImage 随机挂载路径，每次启动都变
微信    /usr/bin/bwrap → wechat → WeChatAppEx ← bwrap 沙箱，且窗口可能属于子进程
WPS     /usr/lib/office6/wps → promecefpluginhost ← CEF 宿主是独立进程
```

- 二进制路径：被 AppImage 随机化
- 进程树：真正持有窗口的是 helper 进程
- `app_id`：不统一（firefox 填 `"firefox"`）
- `desktopFileName()`：AppImage 常常没有 .desktop

**没有任何身份键是可靠的。** 而几何由"应用怎么画标题栏"决定，其唯一可观测产物就是**它画出来
的样子** —— 所以用外观当键。

这同时解掉全部命名问题，并且**天然解决多窗口类型**：QQ 的图片预览窗口长得不一样 → 自动是另一
条记录。身份键永远解决不了这一点（同一个 app、同一个 pid，两个窗口类型）。

### 签名

- 取窗口顶部条带中**按钮那一侧的外三分之一** —— 这是**文字无关区**（`resolveSide()` 本来就
  在扫这一带）
- 降采样 + 量化 luma → 哈希
- 命中判定用汉明距离容差，不要求精确相等

### 两个必须处理的抖动源

不处理的话"量一次缓存"会退化成"每次 hover 都失效重测"，比不缓存还糟：

1. **hover 改变按钮外观** → 签名必须在**窗口刚创建、无 hover** 时计算；量化要粗到 hover 的色
   调变化不跨桶
2. **激活/非激活改变标题栏颜色** → 同一窗口两个哈希。只在**激活态**计算，或在签名里做归一化

### 存储

`$XDG_DATA_HOME/kos/window-metrics.json`（即 `~/.local/share/kos/window-metrics.json`）

条目字段：

```json
{
  "signature": "<hash>",
  "tolerance": 4,
  "headerbarBottom": 46.0,
  "buttonBox": { "x": 0, "y": 11, "w": 96, "h": 24 },
  "side": "right",
  "dark": false,
  "scale": 1.0,
  "samples": 3,
  "lastSeen": "2026-09-28",
  "thumbnail": "<base64 strip 缩略图，仅本地>"
}
```

`thumbnail` 让条目**能被人眼验证** —— 这是库能被社区维护的前提，否则面对一堆哈希无从判断。

---

## 第 3 步：库层与分发

### 三层查找

1. `~/.local/share/kos/window-metrics.json` —— 本地学到的（**优先**）
2. `/usr/share/kos/window-metrics.json` —— **种子库，随包分发，只读**
3. 都没有 → 测量，然后写入第 1 层

### 种子库怎么进包

`integrations/kwin/` 下目前**没有任何 `install(FILES ...)`**，插件只装 `.so`。需要新增：

```cmake
install(FILES data/window-metrics.json
        DESTINATION ${KDE_INSTALL_DATADIR}/kos
        COMPONENT kwin_plugins)
```

用 `COMPONENT kwin_plugins` 是为了搭上 `kosctl install_kwin_plugins()` 已有的
staging → manifest → prune 机制（`tools/kosctl:1037`），不需要新逻辑。Nix 侧
`nix/kwin-kos-bridge.nix` 无需改动，`cmake --install` 会带上。

### 社区数据：用既有的固定资产模式，不做运行时同步

仓库里已经有正确的先例 —— `LiquidAI::ModelManager`（`liquid-ai/src/ModelManager.cpp`，
文档 `docs/DepthEngine.md`）：

- URL 与 SHA-256 是**编译期常量**
- `ensureVerifiedModel()`：缓存存在且哈希匹配就直接用，否则下载到 `.download`、
  校验、再 rename
- **改常量即触发重新下载** —— 天然版本化

社区库应当**照抄这个模式**，而不是发明同步协议：

- 种子库优先**随包分发**（随版本更新，离线可用）
- 可选的联网更新走 `ModelManager` 模式：固定 URL + SHA-256 + 校验后落盘

**不做**双向实时同步。理由：要引入托管、版本协商、失败模式，换来的收益只是"省一次像素读 +
一帧"，不值得。`pci.ids` / `hwdb` / Wine AppDB 这一类社区怪癖库**没有一个是运行时同步的**。

### 隐私

`thumbnail` 会暴露用户的应用列表和主题。因此：

- 缩略图**只存在本地库**
- 导出时**默认剥离**缩略图，除非用户明确选择贡献

### 贡献流程

导出 → 用户贴进 issue/PR → 维护者合并进种子库 → 随下个版本分发。不需要任何服务端。

---

## 设置页集成

### 现状

- 设置 UI 全部在 `apps/settings/main.qml`（3991 行），每个页面是内联的
  `component XxxPage: ColumnLayout`
- 侧边栏 `SidebarEntry { pageIndex: N }`（`main.qml:3758-3827`），现有页面 0–8，
  **新页面用 9**
- 页面标题注册在 `contentByPage`（`main.qml:162-199`）
- 渲染用 `Loader { active: window.currentPage === N }`（`main.qml:3923-3985`）
- **注意**：`main.qml:3878` 有一处 `<= 8` 的守卫，加页面必须一并改，否则通用
  `Repeater` 分支（3877-3907）行为不一致
- 索引在三个地方重复（SidebarEntry / contentByPage / Loader），加页面要同步三处

现有的 KWin effect 设置先例：

- `GlassDebugPage`（`main.qml:1669`）→ `bridge.updateGlassDebugValue()`，回填走
  `glassDebugSnapshotChanged`
- dock 动画风格在 `ThemeSettingsPage`（`main.qml:2783-2848`）→
  `bridge.updateDockWindowAnimationStyle()`

### 通信链路（必须照走，shell 不直接调插件）

```
设置 QML 页面
  → SettingsBridge::updateXxx()            apps/settings/src/main.cpp:111（返回 void）
    → callShell(target, args, err, kind)   main.cpp:1236
      → QProcess: quickshell -c kos ipc call <target> ...
        → IpcHandler                        shell/desktop/DesktopEnvironment.qml
          → shell QML service
            → PlatformClient.request()      QLocalSocket $XDG_RUNTIME_DIR/kos-platform.sock
              → PlatformServer              platform/src/daemon/PlatformServer.cpp
                → kwriteconfig6 + reconfigureEffect 或
                  QDBusInterface 直连插件
```

新增一个方法要动四处（照 `updateDockWindowAnimationStyle` 抄）：

1. shell handler：`shell/desktop/DesktopEnvironment.qml` 的 `IpcHandler`
2. shell 服务：写属性 + 防抖 + 同步到 effect
3. `apps/settings/src/main.cpp`：`Q_INVOKABLE`（复用已有 `RequestKind` 就不必加枚举；
   新回复结构才需要加 enum + `handleReply`/`failKind` 各一个 case + 新信号 + 新 parser）
4. QML 页面：调 bridge，在 `onXxxSnapshotChanged` 里读结果

### 页面内容

核心不是"配置"，而是**把测量失败变成一个可见、可一键修复的队列**。用户不该被要求理解签名和
几何。

- **总开关**
- **每个应用一行**：图标 + 名称 + strip 缩略图预览 + "已识别 / 待确认" + 重新测量
- **待确认队列** —— 投票不一致的窗口在这里让用户点一下确认。这是"人眼验证"的落地点，
  也是唯一需要用户介入的地方
- **样式**：大小、间距、位置、明暗 auto/dark/light（现有配置项）
- **数据**：导出 / 导入 / 重置 / 贡献

**不一致时绝不能静默用错的** —— 这是整个产品体验的核心。

### 插件侧接口

kos-bridge 目前**没有任何 D-Bus 接口**。按既有先例加（`dock-window-animation`、
`context-menu-input` 两个现成模板）：

```cpp
Q_CLASSINFO("D-Bus Interface", "org.kos.KWin.WindowButtons")
QDBusConnection::sessionBus().registerObject("/KOSWindowButtons", this,
        QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
```

（注册在 `org.kde.KWin` 这个总线名下，因为 effect 跑在 KWin 进程里。）

拟暴露：`metricsSnapshot()`、`remeasure(quintptr windowId)`、`confirm(windowId, box)`、
`pendingQueue()`、`exportMetrics()`、`importMetrics(json)`。

### 插件如何独立于 shell 存活

`kos-bridge/windowbuttons/buttonconfig.cpp` 已经确立了模式：KWin 插件**直接读** kwinrc，
并**同时监听文件和它所在的目录**（`armKwinrcWatch()`），因为 kwriteconfig 和编辑器都是
换新文件而不是原地写，只盯文件会丢掉 watch。理由写在注释里：KWin 不会把"装饰器换了"
告诉 effect，所以插件只能自己看文件。

本方案的本地库是**插件自己拥有**的，比这还简单：插件读写自己的文件，不需要 shell 参与。设置页
只是通过 D-Bus 查询和修改它。

---

## 失效与边界

| 情况 | 处理 |
| --- | --- |
| 窗口 resize | 重测（`position: right` 的按钮簇 x 依赖窗口宽度） |
| 输出缩放变化 | 重测；缓存按 `scale` 分桶 |
| 主题变化 | 外观签名自然变化 → 自动失效，不会命中过期条目 |
| 应用/toolkit 升级 | 同上 |
| 首帧内容未就绪 | 退化检测 → 重试若干帧 → 仍失败则 `valid=false` |
| 测不到按钮簇 | **不画面板**（降级为"不画"，不是"画错"） |
| 无边框窗口 | 直接跳过 |
| 最大化 / 全屏 | 标题栏可能不同，需单独测量 |

---

## 非目标

- **不做神经网络。** 理由见上。
- **不做运行时双向同步。** 用固定资产模式，随版本分发。
- **不试图让 GTK 应用变成 SSD。** GTK3/GTK4 不实现 `zxdg_decoration_manager_v1`，KWin 6.6+
  的窗口规则（`noborder` = Force: No）只会让 KWin **额外**画一个装饰，结果是**两个标题栏**。
  对 GTK / Firefox / Chromium 这三类都不适用。那条路只在 Qt 上有效，而 Qt 本来就默认 SSD。
- **不改用户手写的 `window-buttons.json`。** 用户意图与机器学到的数据分开存放。

---

## 落地顺序

第 1 步是纯收益、无新概念、可独立验证 —— 先做完它，覆盖和明暗两个问题就都消失了。
第 2、3 步是在第 1 步产出真实测量数据之后才有意义的加速层；**库的内容必须从测量结果里长出来**，
先建库等于在猜的基础上再猜一层。
