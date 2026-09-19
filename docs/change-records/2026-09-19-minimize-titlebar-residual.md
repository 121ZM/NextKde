# 最小化动画标题栏残留修复记录

日期：2026-09-19
状态：**已提 PR（临时修复）** —— 只让 `glass` 材质随动画淡入淡出，不动动画形态、
不动几何、不加配置项。真凶（`glass` 按窗口 `frame` 画的那块背景模糊）已被消除。
**尚未完美**：彻底修复要么需要 KWin 侧把"变换后的窗口区域"暴露给 backdrop
效果，要么就得改动最小化动画形态；见文末"完美修复方向"。

## 问题描述

窗口最小化时，液态玻璃标题栏（kos_liquid_glass 装饰）会留下一条
"模糊栏"：本该随窗口一起消失，却一直残留到动画结束才消失。
该条带含有窗口标题文字和红绿灯按钮，半透明，横跨原窗口宽度。

## 已确认的事实

1. 残留条**不是 KWin blur 特效**（`glass`）画的独立模糊。
   - 卸载 `glass` 后残留条依然出现（变成不透明白条，红绿灯仍在）。
   - 残留条内有标题文字+红绿灯按钮——模糊不可能画出这些。
2. 残留条 = 重定向纹理（OffscreenEffect FBO）中**标题栏所在的最顶行网格**。
   - 最小化时 `kos_dock_window_animation` 把窗口重定向到 FBO，
     整窗（含装饰）烘进一张纹理，再用 `applyBottomGenie` 的网格变形
     把它"捏"进 Dock。
   - 网格变形对每行顶点施加延迟 `delay = (1.0 - v) * k`：
     底行（v=1）先走，顶行（v=0，即标题栏）最后走。
   - 标题栏半透明 + 有 blur region，视觉上读起来就是"残留模糊栏"。
3. 仅 SSD 装饰窗口（kos_liquid_glass）明显；CSD 窗口（QQ）同样
   有顶行滞后，但因标题不透明不显眼。
4. 残留条随窗口透明度一起渐隐（纹理用 `data.opacity` 绘制）。

## 特效链背景（KWin 6.7.5）

- `glass` chain position=20（外层），`kos_dock_window_animation`=50。
- 重定向窗口的 drawWindow 链在 kos_dock 处终止（不转发
  `effects->drawWindow`），`finalDrawWindow`/真实 item 树不会在
  屏幕上绘制——残留只可能来自我们自己画的纹理。
- `BackgroundEffectItem`（glass 用）只扩展重绘区域，不参与渲染。

## 已尝试的修改（`integrations/kwin/dock-window-animation/dockwindowanimationeffect.cpp`）

### v1（失败）：垂直/水平相位解耦
- 垂直塌陷改用 `t^1.2` + 顶行延迟 0.18；水平保持 `t^1.65` + 延迟 0.36。
- 结果：标题栏提前下移，但**仍以全宽漂浮在半路** → 仍像残留条，
  且动画形态奇怪，用户不满意。

### v2-v5（被否决的中间尝试，留档）
- v2：水平进度绑定行自身垂直进度（t^1.2 曲线 + 行延迟 0.18）。残留仍在。
- v3：自定义 shader 做整窗自上而下的透明衰减。实测证明纹理确实被 shader 处理
  （status 里 `genieDissolve:ready` + 200 次 uniform 写入），但残留依旧 →
  **残留不来自我们的纹理，而是 glass 按窗口 frame 画的那块背景模糊**。
- v4/v5：改为只溶解客户区以上的装饰带（含 absorb/fade/hide 三种模式），
  并抑制 glass 模糊。残留消失，但用户看到标题栏会闪/会变样。
  原因：模糊抑制是开关式的，材质（模糊 vs 锐利墙纸）在开关瞬间跳变。
- 结论：任何移除装饰带的方案都会让标题栏自身发生可见变化，用户不接受；
  开关式抑制也必然有跳变。→ 只有**让材质平滑过渡**才行（见最终方案）。

## 最终方案（本次收尾，已提 PR）
**只做一件事：让 `glass` 材质随动画淡入淡出，不动标题栏本身。**

- 背景：`glass` 的背景模糊区域来自窗口 `frame`（KOS 的"整窗 glass" + 装饰声明
  的 blur region），它**不跟本 effect 的网格变形走**。窗口一开始飞，那块模糊就
  留在原地：最小化 → "残留模糊条"；恢复 → "窗口还没到、模糊先到"。
- 做法：本 effect 每帧往窗口写一个共享角色 `EffectWindow::data(0x4b4f5342)`
  （0 = 材质全透明，1 = 完全不透明，**未设置 = 1**）：
  - minimize：`1 - smoothstep(t / 0.35)`，前 35% 内淡出（此时窗口已在流动，
    材质变化被运动掩盖，也不会留下残留）。
  - restore / open：`smoothstep((1 - t - 0.65) / 0.35)`，最后 35% 淡入
    （窗口快到位时才出现材质，不会"模糊先到"）。
  - `finishAnimation()` 复位为 1。
- glass 侧（`vendor/kwin-effects-glass/src/blur.cpp`）：最终合成 pass 的
  `modulation` 乘上该角色；未设置时恒为 1.0，**其它窗口零影响**。
- 规模：动画侧 +29 行，glass 侧 +17 行；不改几何、不改时序、不新增配置项。

### 取舍：为什么不再继续"把标题栏消掉"
KWin 的 genie 会把窗口顶部整段（含半透明玻璃装饰条）钉在原位直到最后一刻，
所以"零残留"与"装饰条看起来完全没变化"在数学上不可兼得。本轮实测过：
整窗透明衰减、装饰带溶解（fade / hide / absorb 三种）、开关式抑制模糊——
用户对**每一个**都会感知为"标题栏在变 / 在闪"。最终改为"材质平滑过渡"：
没有突跳、没有残留模糊条，代价只是动画期间玻璃质感随动画淡出淡入。

## 为什么这是暂时方案 / 完美修复方向（有机会继续研究）
根因只有一个：**backdrop 效果的区域无法跟随本 effect 的变形**。彻底解决方向：

1. **让 backdrop 效果拿到"变换后的窗口区域"**（最本质）。`glass` 目前从
   `w->frameGeometry()` / `decoration->blurRegion()` 取区域，而本 effect 的变形
   只存在于离屏纹理的四边形上。若 KWin 能把场景项的实际变换（或 effect 提供的
   形状）暴露给 backdrop 效果，模糊就能真正跟着漏斗走。需要 KWin 上游新接口。
2. **把装饰带的网格行绑定到主体顶行进度**，让它随窗口一起流走（不改 alpha、
   不改形态）。之所以没采用：顶行本身被 genie 钉到很晚，"整条顶边留到最后"
   在半透明玻璃上仍会被读成残留。
3. **重写最小化形态**（不用"顶部钉住"的 genie，而是整体下坠 + 收窄）。顶部从
   第一帧就移动，frame 与可见形状的偏差小到可以接受。代价是改变 NextKde 现有
   动画观感，用户明确要保留原动画，故搁置。
4. **glass 侧逐窗口裁剪模糊区域**到窗口当前可见形状（需要变形后的形状，即 1 的
   另一半）。

## 候选"一劳永逸"方案（研究记录，A 已实现并否决）

按推荐度排序：

### A. 自定义着色器：按纹理行做透明衰减（最可靠）
`OffscreenData::setShader(window, shader)` 已存在接口。
给重定向纹理换自定义 shader：按纹理 v 坐标 × 动画进度做 alpha 衰减，
让顶部（标题栏）区域**优先消散**，几何上怎么滞后都不可见。
- 优点：彻底——残留本质是"半透明像素停留可见"，直接让它不可见。
- 需确认 KWin 6.7 shader 编译/Uniform 传递方式
  （`GLShader` + `ShaderManager` 或自带 GLSL），
  以及如何在 paint 前传进度 uniform（
  `OffscreenData::setShader` 后 uniform 如何设置？
  可能需要在 apply() 里能拿到 shader 句柄）。
- 参考：`integrations/kwin/dock-window-animation/` 现有代码、
  `/usr/include/kwin/opengl/glshader.h`、`ShaderManager` traits。

### B. 把装饰排除出重定向纹理
最小化时对 `window->decorationItem()` 建 **exclusive ItemTreeView**
（`SceneView::addExclusiveView` 机制），`shouldRenderItem` 会让
装饰项在主视图和 FBO 渲染中都被跳过 → 标题栏完全不进纹理。
- 效果：标题栏在动画开始瞬间消失，身体做 genie。无残留可能。
- 风险：需要拿到 `WindowItem`/`DecorationItem`/`SceneView` 内部对象，
  Effect 层 API 未必暴露；可能需 hack。
  查 `window->windowItem()->decorationItem()` 是否可达、
  `ItemTreeView`/`ItemView` 头文件是否在 /usr/include/kwin 中可链接。

### C. 纹理分两半绘制
body 正常 genie；标题栏区域单独一组 quad 用独立透明度快速淡出。
- 问题：`OffscreenEffect::drawWindow` 只调一次 `apply()`+`paint()`，
  单次 draw 无法给不同 quad 不同 alpha（`WindowVertex` 无 alpha 分量）。
  需要绕开 OffscreenEffect 自己实现 paint，改动大。

### D. 简单几何兜底
让顶行"先于"身体到达图标（反向延迟），或把顶行折叠进漏斗内部被
身体纹理盖住。观感可能怪，作为备选。

### E. 缩短存在时间
标题栏行在动画极早期（前 15%）就完成全部位移冲进图标。
配合现有淡出，视觉上=标题栏瞬间融进 Dock。
即对 v < titlebarFraction 的行用独立更早的相位。

## 构建与验证

```sh
# 编译（输出 .build/kosctl/integrations/kwin/dock-window-animation/kos_dock_window_animation.so）
cd .build/kosctl && ninja integrations/kwin/dock-window-animation/kos_dock_window_animation.so

# 安装（必须 rm-then-cp 换新 inode，原地覆盖会崩 kwin_wayland；需 sudo）
sudo rm /usr/lib/qt6/plugins/kwin/effects/plugins/kos_dock_window_animation.so
sudo cp .build/kosctl/integrations/kwin/dock-window-animation/kos_dock_window_animation.so \
    /usr/lib/qt6/plugins/kwin/effects/plugins/
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect kos_dock_window_animation
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect kos_dock_window_animation

# 调试：把动画拉长到 1200ms 便于抓中间帧
kwriteconfig6 --file kwinrc --group Effect-kos_dock_window_animation --key GenieDuration 1200
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect kos_dock_window_animation
# 恢复：同命令写 300

# 状态查询
qdbus6 org.kde.KWin /KOSDockWindowAnimation status

# 窗口列表/操作：unix socket /run/user/1000/kos-platform.sock
# operation: kwin.subscribe（快照）; kwin.command {id, action: activate|minimize}
# 截屏：spectacle -b -n -o /tmp/xx.png
```

## 注意事项

- `shell/desktop/modules/dock/DockIcon.qml` 有一处用户遗留改动，勿动。
- GenieDuration 调试后需恢复 300。
- 验证目标：**动画任意时刻截图都不出现分离的标题栏/模糊条**。
