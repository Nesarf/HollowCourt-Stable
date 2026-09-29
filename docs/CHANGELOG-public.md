# 空庭 Hollow Court — 公开发布说明 / Public release notes

**这份文件是给使用者的，不是给开发者的。** 开发过程中的决定、工具与教训写在 `docs/CHANGELOG.md`，
而那份文件是内部的：它记的是「谁定的、哪个工具在守、上一次哪里出了错」。

**This file is for people who use the application. The development history — who decided what, which tool enforces it, what
went wrong last time — lives in `docs/CHANGELOG.md`, which is an internal document.**

**两边都写，因为读者不止一类。** 中文在前，英文在后，与应用自己的双语文案同一个规矩。

---

## 1.0.0 — 第一次公开发布 / First public release

**2026-09-28**

### 它是什么 / What it is

**一个真正属于你的饮品仓库。** 跨平台、离线优先、没有账号，也没有服务器。
Windows、Linux 与 Android 三端都能装。

**A drinks cellar that is actually yours.** Cross-platform, offline-first, with no account and no server.
It installs on Windows, Linux and Android.

### 已经有了什么 / What is already there

| | |
| --- | --- |
| **地基** | 领域层：单位、配比、匹配评分，都有测试 |
| **单机可用** | 事件日志、种子导入、库存与配方页、液体的颜色渲染 |
| **视觉完成** | 货架摆放、吧台页、价格与统计 —— 验收标准是「能一边调一杯一边用」 |
| **局域网** | 配对、星形同步、操作日志合并 —— 手机与电脑共用一个酒柜 |
| **三端打包** | Windows 的 `.msi`、Linux 的 `.AppImage`、Android 三个 ABI 的 `.apk` |

| | |
| --- | --- |
| **Foundations** | The domain layer: units, ratios, match scoring — all tested |
| **Usable alone** | Event log, seed import, the stock and recipe screens, liquid colour |
| **Visually complete** | Shelf layout, the bar, prices and statistics — complete enough to mix a drink while using it |
| **On a LAN** | Pairing, star-shaped sync, log merging — a phone and a computer share one cellar |
| **Packaged** | An `.msi` for Windows, an `.AppImage` for Linux, and three `.apk` files for Android |

### 还有一些不在路线图里、但这版有的 / Also in this version

- **四个主题** —— 每个都有自己的「世界」，而不是换一套颜色
- **声音轴** —— 同一种语言的另一种人格文案
- **设备发现** —— 在局域网里按名字找到对方，像蓝牙那样
- **`.courtpack`** —— 一种行分隔的 JSON 包，可以把酒窖导出、也可以核对
- **本地化的边界** —— 港繁与台繁是生成的，而机器做不完的那一半写明了，不假装

- **Four themes** — each a world of its own rather than a recolouring
- **A voice axis** — the same language written in a different register, or in another one
- **Device discovery** — find the other machine on your network by name, the way Bluetooth does
- **`.courtpack`** — a line-delimited JSON bundle you can export a cellar to and check
- **Honest localisation** — the Traditional Chinese variants are generated, and the half a machine cannot do is stated

### 这版不声称什么 / What this version does not claim

**说清楚，而不是让人自己发现。**

**Said plainly, rather than left for you to find out.**

- **网络层只是部分。** 比价适配器与条码扫描在本版里是声明，且按设计关闭。
- **新设备用配对码配对。** 另一种更好的方式（两台设备各显示六位数字、对一眼即可）需要你拍板。
- **走隧道的 VPN 还不能用。** 它已经被定为一种独立的连接方式，实现还没有做。
- **蓝牙秤、IMU 与手柄还不能用。** 它们在等各自的设备协议。
- **咖啡相关的东西还没有做。**

- **The network layer is partial.** Price comparison and barcode scanning are declarations in this build, off by design.
- **New devices pair by code.** A better way — both screens show six digits and you compare them — is not settled yet.
- **VPN tunnels are not usable yet.** A tunnel is settled as its own kind of link; the implementation is not written.
- **Bluetooth scales, IMUs and gamepads are not usable yet.** Each is waiting on its device's protocol.
- **Nothing coffee-related is done.**

### 怎么验的 / How it was verified

**两件事，都在 GitHub 的机器上跑，都是绿的：**

**Two jobs, both on GitHub's machines, both green:**

| | |
| --- | --- |
| **工具的四个阶段** | 语法、工具自测、美术规矩、美术渲染 |
| **产品** | 取依赖、静态分析，以及 116 个测试文件逐目录逐文件地跑 |

| | |
| --- | --- |
| **Four stages for the tooling** | Syntax, the tools' own tests, the art rules, art rendering |
| **The product** | Dependencies, static analysis, and all 116 test files run by directory and by file |

**这件事本身就是这一版最该说的。** 在此之前，那条流水线从来没有跑起来过一次 ——
它被触发过十三次，每次一个任务都没产生，而这件事是**在一台别人的机器上**才暴露的。
修好之后它连续逮到七个缺陷，全部属于「只有第二台机器才能发现」的那一类。

**That is the thing worth saying about this release.** Before it, the pipeline had never once run: it had been triggered
thirteen times and produced no jobs at all, and that only became visible on a machine that was not ours. Once it ran, it
found seven defects in a row, every one of them the kind that only a second machine can see.

**这就是这一版对「做完了」的定义**：不是「在我这儿能用」，而是**能在别人的机器上被证明是好的**。

**Which is this release's definition of done**: not "it works here", but *it can be shown to work on somebody else's machine*.

### 产物 / The artifacts

**三端产物各有两种形式**：给 Windows 的 `.msi`、给 Linux 的 `.AppImage`、给 Android 的三个 `.apk`（一个 ABI 一个）。
**每个产物旁边都有一份记录**，写着它是从哪个源提交构建的、什么时候构建的、以及它的 sha256 ——
所以「我手上这个文件是不是那一个」是可以自己核对的。

**Each platform has its own two ways in**: an `.msi` for Windows, an `.AppImage` for Linux, and three `.apk` files for
Android, one per ABI. **Every artifact carries a record beside it** naming the commit it was built from, when it was built,
and its sha256 — so "is this file the one that was published" is a question you can answer yourself.

**而这一版与上一份的区别，可以在应用里看到**：打开「关于」，那里印着这个二进制自己的源提交。
**它的版本号是 `1.0.0.2184`。**

**And the difference between this release and the previous set is visible in the application itself**: open About, where the
binary prints the commit it was built from. **Its version is `1.0.0.2184`.**

**Android 的版本号有两种写法**：显示的是 `1.0.0.2184`，而安装器比较的是一个整数 ——
三种 ABI 各自不同，这样每一份都能独立升级。这是 Android 的规矩，不是本项目的。

**Android names the version twice**: the displayed one is `1.0.0.2184`, and the installer compares an integer that differs
per ABI so each can be upgraded on its own. That is Android's rule, not this project's.
