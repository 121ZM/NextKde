# KWin 6.8 升级修复（2026-10-17）

## 已确认的原因

用户将 KWin 升级到 6.8.0 后，安装的 Glass、KOS Bridge、Stage 和菜单输入
特效仍携带 `org.kde.kwin.EffectPluginFactory6.7.5`。本次启动日志明确报告
期望 `org.kde.kwin.EffectPluginFactory6.8.0`，因此拒绝加载。
Liquid Glass 失效的直接原因是旧插件二进制，而非窗口列表脚本。

只读诊断已收到 6 个窗口，KWin 窗口脚本加载标志为 true，Shell 日志也记录了
窗口激活、最小化和缩略图成功回执。这台机器没有复现其他用户的“只有 pinned”；
该症状不能直接归因于特效加载失败，仍须在对应环境检查快照与 Shell 模型。
用户确认项目已安装最新版，不再以缺少旧修复作为排查前提。

## 源码修复

- Bridge、Dock 动画、Stage、Glass：根据实际 KWin 头文件检测绘制回调返回值，
  支持 6.8 的 bool，同时保留旧版本的 void 签名。
- Bridge：离屏源绘制失败时不把空缓存当作有效内容；保持缓存 dirty，回退并重试。
- Dock：传递离屏绘制和补底绘制结果，保留原有窗口 capture role 的恢复。
- Glass：传递绘制结果，主动隐藏的内容视为成功的空绘制；替换 6.8 已删除的
  像素对齐函数，保持按矩形边缘对齐。
- Stage：传递 6.8 的屏幕绘制返回值；保持 main 现有的卡片渲染回退策略。
  本机工作分支已有的实时渲染端口及其他 Stage 改动没有包含在本次 main 合并中。
- 菜单输入及其余特效：补齐／保持 KWin 工厂宏的 AutoMoc 注册。
- `tools/check-kwin-api.py`：替换头文件时也切换新的绘制返回值编译定义，
  避免拿当前构建的宏误判旧版头文件。

此前补的窗口脚本重连、有限重试、信号连接保护和 desktopsChanged 监听属于
独立防御性改动，未部署为这次 Glass 的修复，也未证明是其他机器空 Dock 的根因。

## 构建与部署

用户明确要求在更新后的本机运行诊断并修复。已完成 KWin 6.8.0 下六个目标的
编译和链接：`glass`、`kos_bridge`、`kos_dock_window_animation`、
`kos_context_menu_input`、`stageanim13`、`kos_decoration`。
五个特效的新二进制均已检查包含 `EffectPluginFactory6.8.0`。

安装文件及带 SHA-256 检查的脚本位于 `.build/kosctl/kwin-6.8-install/`。
安装脚本先在 `/var/backups/kos-kwin-6.8-*` 备份旧文件，再用原子替换安装
系统插件；不覆盖正在映射的旧 inode，不重启任何服务，也不加载／卸载特效。
系统管理员认证通过，六个插件已安装到 `/usr/lib/qt6/plugins/`，
每个安装文件的 SHA-256 与构建产物一致。旧文件备份位于
`/var/backups/kos-kwin-6.8-bvrxgpt0`。注销并重新登录后加载新插件；
没有重启 KWin 或热加载特效。

没有运行测试、启动额外 Shell 或进行图形验证。尚未在新登录会话确认视觉效果。
本轮本机执行基于用户此次明确授权，不改变长期“验证在虚拟机执行”的偏好。
外部 `kwin4_effect_shapecorners` 仍为 6.7.4 构建，需由其维护方更新。

## 后续诊断工具

`python3 tools/diagnose-dock-windows.py` 只查询窗口脚本加载标志和订阅平台已有
快照，不加载脚本或特效，不修改窗口，不重启服务。输出不含标题、应用 ID 或 UUID。
快照可能来自缓存，不能单凭收到快照判断实时发布健康。

## 上游依据

- [KWin 6.8 Effect](https://github.com/KDE/kwin/blob/v6.8.0/src/effect/effect.h)：绘制回调返回 bool。
- [KWin 6.8 OffscreenEffect](https://github.com/KDE/kwin/blob/v6.8.0/src/effect/offscreeneffect.cpp)：离屏绘制失败传播。
- [KWin 6.8 Scripting](https://github.com/KDE/kwin/blob/v6.8.0/src/scripting/scripting.cpp)：QTimer、callDBus 和脚本运行环境。
- [KWin 6.8 Workspace](https://github.com/KDE/kwin/blob/v6.8.0/src/scripting/workspace_wrapper.h)：windowList 仍存在。
- [6.8 官方变更记录](https://kde.org/announcements/changelogs/plasma/6/6.7.5-6.8.0/)：合成器取消桌面 OpenGL 支持。
