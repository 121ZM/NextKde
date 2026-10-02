# 壁纸后续修正

- 主题图库通过 MultiEffect 的圆角 alpha mask 裁切，不仅设置卡片 radius。
- 服务页采用现有 LiquidGlassSwitch；只保留启用、状态、2 GB 自动缓存说明与必要错误，移除手动清理入口和删除资源弹窗。
- AI worker 返回生成资源前按缓存组淘汰最旧目录，保留当前组；2 GiB 上限包括深度图和 spatial-v3 资源。超过上限且无法清理时拒绝保留新组。此 C++ 修改尚未构建部署。
- 空间服务未开启的预览入口使用从回收站确认框提取的 DesktopConfirmDialog，同一材质、间距与按钮；用户确认后初始化服务。
- 黑洞 PNG 材质增加沿视界角向的旋流位移与移动亮纹，保留 PNG 大轮廓。qsb 已编译，观感需人工确认。
- 服务未启用：当前页面原有 available=false 禁用开关，运行平台服务已持续运行 15 小时；仓库平台源码已有 spatial.resources，但现有安装二进制不含该标识。需要构建部署最新平台/worker 才能实现初始化，不能仅改 QML。
- 最近崩溃报告 ffs3qzm9mt: SIGSEGV，QQuickItem::polish / QQuickWindow::physicalDpiChanged / updateDevicePixelRatio；98o3mbm9mt: SIGSEGV，QQuickItemPrivate::derefWindow / setParentItem / deleteChildren，发生于配置热重载附近。栈指向 Qt Quick 窗口与控件生命周期，尚不能锁定具体 QML 控件，未断言是显卡或粒子导致。
- 修正 themeOptions 的 height/implicitHeight 绑定循环，用 contentHeight 表达文本高度。

未启动图形会话或运行自动化测试。后续需要构建并更新平台及 AI worker，人工确认服务可启用和缓存淘汰行为；崩溃定位仍需具体触发操作与更精确调用栈。

## 空间壁纸服务部署完成

2026-10-02 已针对源码 mtime 早于旧对象文件导致的增量构建遗漏，刷新相关编译单元并重新构建 kos-platform、kos-ai-worker 和 kos-settings。三个目标编译、链接完成后原子更新 ~/.local 中对应二进制，平台/worker 的 RUNPATH 指向 $ORIGIN/../lib。同步设置页 QML 和共享控件，补充 kosctl 部署清单的 ServicesSettingsPage 与 ThemeWallpaperTile，同步安装目录的 SpatialResourceService。重启的只有 kos-platform.service，未启动新 Quickshell/图形会话，未运行自动化测试。

通过现有 shell 的 initializeSpatialService 执行实际服务初始化；最终 snapshot 返回 available=true、enabled=true、ready=true、busy=false、checking=false、error=""。模型字节数 277740276，生成缓存 491240112。空间壁纸效果本身未自动开启，沿用用户当前主题；预览时可按需生成。

旧二进制和设置文件备份：/home/amao/.local/state/kos/deploy-backups/spatial-20261002-145232。实际平台实例 MainPID=191955，二进制路径未带 deleted，依赖使用已安装的 libonnxruntime.so.1。
