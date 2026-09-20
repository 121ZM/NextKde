# 修复约束 · 2026-09-20

所有 `docs/fix-tasks-2026-09-20/` 下的工作必须遵守以下约束。

## 1. 架构红线（PROJECT_CONTEXT.md code-review gate）

- QML / Settings 代码**不得**新增执行桌面集成或系统控制命令：
  `qdbus6`、`kwriteconfig6`、`nmcli`、`wpctl`、`bluetoothctl`、`systemctl`、
  `gio`、`socat`、`sh -c`、`notify-send`（直发）。
- 需要新系统能力时：在 `shared/contracts/platform.v1.md` 增加有界版本化
  operation，在 kos-platform 实现，QML 经 `PlatformClient.qml` 调用。
- 修复**不得**引入新违规；阶段二（R10–R15）专门收敛存量违规。
- 配置持久化的 `sh -c` 模板统一收敛到 daemon `state.read/write` op（R10/R11），
  不再新增复制。

## 2. 不破坏既有 workaround 与不变量

- `AppLauncher.qml` 常驻窗口是 Qt 6.11 输出切换崩溃 workaround，禁止改回
  随 open 销毁。
- `kos-shell.service` 的 `KillMode=process`、启动顺序依赖不要动。
- `install` 必须保持非热加载语义（不重启运行中服务、不热载 KWin effect）。
- 数据服务状态根 `$XDG_STATE_HOME/quickshell/shell-data-service/` 用户历史
  不得删除/丢数据；改 persist 逻辑时保证向后兼容读取旧 state.json/snapshot.json。
- 契约变更必须版本化并同步 `shared/contracts/platform.v1.md`，
  保持 `{ok,result,error}` 响应模型；socket 权限维持 0600。
- 注释标注"不要改/有意为之"的行为（拖拽 offset、屏幕生命周期保活、
  Qt 6.11 workaround、刻意复制的 LockClock）保持原语义。
- **锁顺序**：data-service 修 P0-1/P0-2 时不得引入新死锁——marshal 移锁内
  要保证锁内不做阻塞 IO；conn 写互斥不能持有 subscriber 锁做长写。

## 3. 范围控制

- 一次只做一个任务（R<n>），不夹带无关重构；保留 worktree 无关改动。
- 每个任务独立分支 `fix/2026-09-20-<slug>` + 独立 commit（`fix(scope): …`，
  关注 why）；阶段内多任务可同 PR 但各自独立 commit。
- 不修改 git 配置、不 push 到 origin（只推 fork 提 PR）、不 force-push、
  不动分支保护。
- **阶段隔离**：阶段 N+1 分支从 `origin/main` 干净拉，不带阶段 N 未合并 commit。

## 4. 验证

- 改动后能构建：`./tools/kosctl build`（或对应子集 preset）。
- QML 改动跑 `./tools/qmllint-changed.mjs`；契约改动跑 `./tools/check-docs.py`。
- Go 改动跑 `go test ./services/data-service/`，竞争修复补 `-race` 用例。
- C++ daemon/KWin 改动保证 daemon/effect 重启后 shell 无永久卡死。
- Shell 行为改动用 verify skill（`qs -p shell` / `kosctl dev`）实测。
- 性能任务给前后对比（fork/exec 每分钟、RSS、写盘字节、帧时间）记入提交信息。

## 5. 审查（强制，每次完成后）

- 每个任务完成后**必须调用只读 `code-reviewer` 子代理**审查 `git diff`，
  复核：正确性、是否引入新问题、是否遵守本约束、是否夹带范围外改动。
- 发现问题→修复→再审，直到通过；审查结论记入提交信息 / 任务卡。

## 6. 安全

- 不提交 secret/凭据；不改 socket 0600 与路径校验。
- 拼接进 shell/argv 的外部输入必须校验或改 argv 形式（R13）。
- 密码不得走进程 argv（R14：Wi-Fi/802-1x 改 D-Bus settings dict）。
- 下载（ArtworkColorSource）必须有大小上限、协议白名单、取消逻辑。
