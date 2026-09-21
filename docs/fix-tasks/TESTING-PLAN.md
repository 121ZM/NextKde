# 测试与 CI 规范

> 状态：**已实施**。实施日期：2026-09-21。
> 立项文档保留于此；日常用法见 `README.md` 的「提交前必须运行」与
> `docs/ProjectArchitecture.md` 的 Testing layers 一节。
> 数据来源：本机实测（见文末「实测基线」）。

## 1. 为什么要做这件事

三个已确认的事实，构成做这件事的理由：

1. **`kosctl install` 在编测试，浪费约 28 秒。** 根源是 `tools/kosctl:348` 的
   `cmake --build` 没有 `--target`，于是构建 ninja 的默认 `all` 目标，把
   98/304 个测试目标一并编译。文档三处（`docs/ProjectArchitecture.md:62`、
   `PROJECT_CONTEXT.md:102`、`tools/kosctl:102`）都定义 `install` 只做
   「构建产物 + 部署 + 启用 systemd 单元」，不含测试环节。

2. **仓库没有任何 CI。** `ls .github/` 不存在；`.gitlab-ci.yml`、`.drone.yml`、
   `.cirrus.yml`、`.woodpecker.yml`、`Jenkinsfile` 均不存在。

3. **测试有真实的、没人发现的回归。** 本机实测 31 项测试，2 项因源码回归失败
   （详见 §3.2）。同时 README:378-384 的「提交前建议运行」清单里**不含 `ctest`**。

结论：测试写了，但**没有归宿**——没人自动跑，也不在提交清单里，于是回归会静默积累。

## 2. 目标与非目标

### 目标

- **G1**：提供一条 CLI 命令，一键跑数据/服务层的测试，本地和 CI 用同一套。
- **G2**：文档明确写清「提交 PR 前必须跑什么」，且其中包含测试。
- **G3**：数据/服务层（不做崩溃）的测试达到规范标准：契约明确、可离线跑、失败可定位。

### 非目标（本期明确不做）

- **N1**：不规范化界面/视觉层测试。`kos-ui.visual-contract`、`kos-shell.squircle-mask`、
  `kos-shell.liquid-glass-panel` 这类依赖 QML 引擎/显示环境的测试，本期不动。
- **N2**：不追求「全部测试绿」。本期的成功标准是**数据/服务层可独立绿**。
- **N3**：不做 Nix 侧的 CI（`nix/kos-settings.nix` 等仍只拷 `shared/qml/controls` 的问题另记）。

## 3. 现状：实测基线

### 3.1 测试全景（31 项，按层次分）

配置：`-DBUILD_TESTING=ON -DKOS_BUILD_KWIN_PLUGINS=OFF`，apps 全 OFF，`-j12`。
构建 64.5 s，测试总耗时 31.2 s。

| 层次 | 测试名 | 依赖 | 状态 |
|---|---|---|---|
| **数据/服务** | `kos-data-service.go` | Go，离线 | 通过（1 个失败是沙箱 `/tmp` 满，见 §5） |
| **数据/服务** | `kos-pim.store` | Qt6，临时目录 | 通过 |
| **数据/服务** | `kos-pim.dbus` | Qt6 + dbus-run-session | 通过 |
| **数据/服务** | `kos-pim.client-dbus` | Qt6 + dbus-run-session | 通过 |
| **数据/服务** | `kos-application.preferences` | Qt6 | 通过 |
| **数据/服务** | `kos-weather.client-snapshot` | Qt6，网络 mock | 通过 |
| **数据/服务** | `kos-music.core` / `.engine` / `.mpris` | Qt6 + gstreamer | 通过 |
| **平台** | `kos-platform.window-placement` | node | 通过 |
| **平台** | `kos-platform.contracts` | Python | 通过 |
| **Shell 逻辑** | `kos-shell.appearance-config`、`dock-adaptive`、`dock-autohide`、`date-buckets`、`wallpaper-color-source` 等 | node | 通过 |
| **Shell 回归** | `kos-shell.window-placement-updates` | node | **失败（真回归，见 §3.2）** |
| **界面/视觉** | `kos-ui.visual-contract` | node，断言 `apps/settings/main.qml` 源码 | **失败（真回归，见 §3.2）** |
| **界面/视觉** | `kos-shell.squircle-mask`、`liquid-glass-panel` | QML 引擎 | 已知恒失败（无显示环境） |
| **锁屏** | `kos-lockscreen.theme-resolution` | KF6::Package | 通过 |

### 3.2 两项真实回归（本期必须修）

**回归 A：`kos-shell.window-placement-updates`**

```
TypeError: svc._pruneThumbnails is not a function
    at Object._rebuild  (test_window_placement_updates.mjs:38)
```

根因：该测试用 `vm` 执行生产 QML 函数，但**用硬编码白名单**挑选要提取的函数
（`test_window_placement_updates.mjs:10-12`）：

```js
const names = ["_newWindowId", "_presentationEqual", "_placementEqual",
    "_updatePlacement", "geometriesEqual", "_rebuild"];
```

`WindowService.qml` 的 `_rebuild`（:423）现在调用了 `_pruneThumbnails`，但它不在白名单里，
mock 的 `svc` 对象上就没有这个方法。**这是测试基础设施的设计缺陷**——白名单会随源码演进失效。

**回归 B：`kos-ui.visual-contract`**

```
AssertionError: the theme card derives its height from the gallery and the embedded page
    at shared/qml/test_visual_contract.mjs:207
```

根因：断言（`shared/qml/test_visual_contract.mjs:204-210`）要求 `apps/settings/main.qml` 里存在

```qml
implicitHeight: 16 + styleGallery.height ... themeMaterialSettings.implicitHeight
```

但 `main.qml` 当前的 `implicitHeight` 绑定不符（最近一次改动的遗产）。注意
此测试同时断言 `main.qml:5-6` 的 `import "../../shared/qml/controls"` 结构——
与 PR #87 是同一片代码区域，**修的时候要和 #87 一起看**。

## 4. 建议方案

### 4.1 CLI 入口（对应 G1）

新增 `tools/run-tests.sh`，作为**唯一的测试入口**（本地与 CI 共用）：

```sh
./tools/run-tests.sh              # 默认：数据/服务层（离线、无需显示环境）
./tools/run-tests.sh --all        # 全部 31 项（含需要显示环境的视觉测试）
./tools/run-tests.sh --layer data # 只跑数据/服务层
```

**关键设计点**：默认跑「数据/服务层」而不是「全部」。理由：
- 数据/服务层**不需要显示环境**，本地和 CI 都能跑，且是你要求「不能崩」的部分；
- 视觉层测试在有/无显示环境下结果不同，放进默认集会让人习惯性忽略失败（这正是当前
  `visual-contract` 和 `window-placement-updates` 失败的现状）。

实现要点（必须内建，否则沙箱复现的问题会反复出现）：

```sh
# /tmp 在本机是 10MB tmpfs，Go 与 gcc 都会写爆它
export TMPDIR="${TMPDIR_OVERRIDE:-$PWD/.build/tmp}"
export GOCACHE="$PWD/.build/tmp/go-cache"
export GOTMPDIR="$PWD/.build/tmp"
```

`kosctl` 全文目前**没有一处设置 `TMPDIR`**，这是必须一并修的隐患。

### 4.2 CI（对应 G1/G2）

GitHub Actions，一个 workflow：`.github/workflows/tests.yml`。

- **选 GitHub Actions 而非 Drone**：仓库已在 GitHub；Drone 需自托管维护，
  对单人维护的 KDE 桌面项目不划算。
- **跑什么**：`./tools/run-tests.sh`（即数据/服务层），`--all` 留给手动。
- **配置**：用现有 `debug` preset（`CMakePresets.json:8-14` 已把
  `KOS_BUILD_KWIN_PLUGINS` 设为 `OFF`）—— 说明作者已考虑过 CI 场景，只是没写 workflow。
- **缓存**：缓存 `.build/tmp/go-cache` 与 ninja 构建目录。

### 4.3 文档（对应 G2）

改 `README.md:378-384` 现有的「贡献代码前建议至少运行」段落，从「建议」升级为「要求」，
并把 `ctest` 纳入：

```sh
git diff --check
python3 platform/tests/test_contract.py
python3 tools/check-docs.py
./tools/run-tests.sh          # ← 新增：数据/服务层测试
```

同步更新 `README.en.md`。`docs/ProjectArchitecture.md` 补一节测试分层说明。

### 4.4 修测试基础设施（对应 G3）

**优先修回归 B 的白名单缺陷**，因为它是"结构性"的：

把 `test_window_placement_updates.mjs` 的硬编码 `names` 白名单，改成**自动提取**
`WindowService.qml` 里所有 `function _xxx(` 定义。否则每次改 `WindowService` 都要记得同步白名单——
这个测试已经因为这件事坏了一次。

具体做法：用正则扫描源码里所有 `^    function (\w+)\(`，全部注入 vm context。这样
`_pruneThumbnails` 之类的新函数自动可用，测试不再因"源码加了私有函数"而失败。

### 4.5 给测试打层次标签（对应 G3）

用 ctest 的 `LABELS` 属性给每个测试打标签：

```cmake
set_tests_properties(kos-pim.dbus PROPERTIES LABELS "data")
set_tests_properties(kos-ui.visual-contract PROPERTIES LABELS "ui")
```

这样 `ctest -L data` 就能精确跑数据层，`run-tests.sh --layer data` 直接用它实现。
**不新建测试框架，沿用 ctest**——它已经在那儿了。

## 5. 实测证据（可复现）

```sh
# 干净配置（apps 全 OFF，测试 ON）
cmake -S . -B .build/tmp/base -G Ninja -DCMAKE_BUILD_TYPE=Debug \
      -DBUILD_TESTING=ON -DKOS_BUILD_KWIN_PLUGINS=OFF

# 构建：64.5 s 墙钟（-j12）
cmake --build .build/tmp/base --parallel 12

# 测试：31 项，31.2 s
export TMPDIR=$PWD/.build/tmp GOCACHE=$PWD/.build/tmp/go-cache
ctest --test-dir .build/tmp/base --output-on-failure
# → 28/31 通过；2 项真回归（§3.2），1 项沙箱 /tmp 满
```

**注意**：`kos-data-service.go` 在高并行度下会因 `/tmp` 空间不足而失败（实测报
`write $WORK/b009/_pkg_.a: no space left on device`）。单独重跑（修正 TMPDIR）后 **51.6 s 通过**。
这说明 `GOTMPDIR` 必须显式设置，不能依赖默认。

## 6. 已裁决事项（2026-09-21）

| # | 决策 | 结论 |
|---|---|---|
| D1 | 默认只跑数据/服务层？ | **接受**，且 CI 再加跑 `platform` 层 |
| D2 | 用 GitHub Actions？ | **接受**，并用 `archlinux:base-devel` 容器（包名与 `kosctl` 一致） |
| D3 | 是否修那 2 项真回归？ | **都修**（已完成） |
| D4 | `kosctl install` 那 28 秒？ | **延后**（方案 C：独立 `BUILD_TESTING=OFF` 构建目录） |
| D5 | KWin 插件要不要保证编译？ | **要**：CI 加独立 job 只做 `KOS_BUILD_KWIN_PLUGINS=ON` 编译 |

### 实施结果

- **CI**：`.github/workflows/tests.yml`，两个 job。
  - `tests`：`data` + `platform` 层，实测 **11/11 通过，9.5 秒**。
  - `kwin-plugins`：编译 4 个插件，**26/26 全绿**，产物 4 个 `.so`
    （`kos_liquid_glass` / `kos_context_menu_input` / `kos_dock_window_animation` /
    `libkos_surface_shape`）。做了反向对照：向 `contextmenuinputeffect.cpp` 注入
    语法错误 → 编译报红；还原 → 恢复通过。
- **文档**：`README.md:378`、`README.en.md:311` 从「建议」升级为「必须」，并把
  `./tools/run-tests.sh` 纳入清单；`docs/ProjectArchitecture.md` 新增 Testing layers 一节。
- **连带修复**：`tools/run-tests.sh` 的 `GOCACHE` 导出是死代码（被
  `services/data-service/CMakeLists.txt:18,47` 的绝对路径覆盖）已删除，CI 改为缓存
  真正的目录 `.build/tests/services/data-service/go-test-cache`（实测 125 MB，
  而原先缓存的路径是空的 4 KB）。

### PR #87 与 Nix 侧同一处缺陷

PR #87 **在开工前就已经合入**（即 HEAD `ef7d725`），故 D2 的「合入」无需再做。
但它只修了 CMake 与 `tools/kosctl` 两条路径，**漏了 Nix 侧同一处缺陷**：
`nix/kos-settings.nix:35` 与 `nix/package.nix:91` 仍只拷 `shared/qml/controls`。
现已同步修正，并用双向对照验证：

- **反向**：旧写法对比 CMake 产物，漏 `colorize` / `foundation` / `glass` 三个目录
  （`colorize` 正是导致 Settings 窗口起不来的那个）；
- **正向**：新写法与 CMake `install()` 产物 `diff -rq` **递归完全一致**。

⚠️ 本机无 `nix`，上述验证是用真实 shell 模拟安装脚本的方式做的，未经 `nix build` 实跑。

## 7. 附：`kosctl install` 的修法（与测试规范化独立）

`tools/kosctl:348` 的 `cmake --build` 缺 `--target`。可选修法：

- **方案 A**：`build()` 显式传自定义目标（如 `kos-deploy`），把所有 `install()` 依赖的
  目标挂进去。最干净，但需要新增目标定义。
- **方案 B**：给测试目标加 `EXCLUDE_FROM_ALL`。改动小，但会让 `ctest` 前的构建编不出
  测试二进制，反而更难用——**不推荐**。
- **方案 C**：`install` 用独立的 `BUILD_TESTING=OFF` 构建目录（如 `.build/kosctl-release`）。
  改动最小，职责靠目录分开。

**注意**：不能简单换成 `--target install`，因为 `kosctl install` 的 `CMAKE_INSTALL_PREFIX`
是 `/usr`（`kosctl:236`），而实际部署到 `~/.local` 靠的是 `deploy_artifacts` 自己拷贝。

## 8. 执行顺序建议

```
1. 修白名单缺陷（§4.4）        → 让 kos-shell.window-placement-updates 恢复
2. 修 visual-contract 回归（§3.2）→ 与 PR #87 一起处理
3. 打 LABELS + 写 run-tests.sh（§4.1/§4.5）
4. 加 CI（§4.2）
5. 改文档（§4.3）
6. 修 kosctl install（§7）    → 可与 1-5 并行
```

前两步是「让基线可信」，中间三步是「建立护栏」，最后一步是「顺手拿回 28 秒」。
