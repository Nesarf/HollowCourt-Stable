# 空庭 Hollow Court 变更日志

**版本号住在 `pubspec.yaml` 里 ✓**，写成 `1.0.0+NNNN` ✓ —— **前面是给读者看的版本 ✓，`+` 后面是构建号 ✓**。
**打包脚本就是从那一行推出产物名的 ✓**（`1.0.0.1020` ✓），**所以改版本＝改那一行 ✓✓**。

**而这份文件是给「这一版变了什么」用的 ✓** —— **一次发布的核心就是它 ✓**。

---

## 1.0.0 —— **第一次公开发布** ✓（2026-09-28 ✓）

**这是第一次公开发布，而它就叫 1.0.0** ✓✓ —— **在本版之前，这个仓库从来没有发布过一次 release，也没有一个 tag** ✗✓ ——
**bundle 里那些 `1.0.0.514` 到 `1.0.0.1020` 的产物是真的 ✓，但它们只在这台机器上存在过 ✓**。
**所以这一条覆盖的是**从头到现在的全部** ✓ —— 而不是对某个更早版本的修补 ✓✓。**

**而构建号仍在 ✓**：`pubspec.yaml` 写 `1.0.0+2184` ✓，**产物叫 `1.0.0.2184`** ✓，而**标签是 `v1.0.0.2184`** ✓✓ ——
**同一条信息写了三遍 ✓，因为有三个不同的读者 ✓**：**pubspec 用 `+` 把「版本」与「构建」分开 ✓、产物名与标签用点 ✓、而标签多一个 `v`** ✓。

**而先前这里写的是「标签只要前者（`1.0.0`）」✗ —— 那条理由本来是冲着**加号**去的 ✓✓**：
**`1.0.0+2184` 这样的标签会在每一个提到它的 URL 里带一个加号 ✓。** **而 `v1.0.0.2184` 里没有加号 ✓** —— **点号在任何地方都不用转义 ✓ —— 所以那条理由对它不适用 ✓✓。**
**owner 于 2026-09-29 定了这个格式 ✓，样板就是 `v1.0.0.2184` ✓，而后面每一版照此 ✓**：**`v1.0.0.2221` ✓ `v1.0.0.2880` ✓ `v1.0.0.3028` ✓ `v1.0.0.3640` ✓ `v1.0.0.3939` ✓ `v1.0.0.44100` ✓ `v1.0.0.48000`（CL ✓）✓✓。**

**这一版挂出来的产物，来自哪一个提交 ✓✓ —— 而这句话不写号，因为号会过期 ✗。**

**先前这里写了一个字面的提交哈希 ✓，而那是个**循环** ✗✓：变更日志属于源码 ✓，所以写下它的那个提交会改变 HEAD ✓，
于是刚写下的号立刻就旧了 ✓✓。**所以要指的不是「那串字符」✓，而是**去哪儿读它**** ✓✓ —— **而有两处能读到，两处都永远是最新的 ✓✓：**

| 从哪读 | 为什么它不会过期 |
| --- | --- |
| **应用里的「关于 → 构架自提交」** ✓✓ | **那个字符串是构建时编译进去的 ✓（`--dart-define=BUILD_COMMIT` ✓），所以它说的就是**这一个二进制**自己的来源 ✓** |
| **产物包里的 `.commit` 回执** ✓✓ | **每个产物旁边一份 ✓，由 `packaging/write_receipt.sh` 写出 ✓，字段是 `head` / `src-commit` / `src-subject` / `src-paths` ✓** |

**而 `tool/release.py` 现在会在发布前读那份回执 ✓，`head` 与 HEAD 不一致就拒绝挂上去 ✓✓** ——
**因为上一个版本正是那样出去的** ✗：**说明写着「酒保已撤」✓，而挂着的 APK 来自一个它还在的提交 ✗✓。**

### 它是什么 ✓

**一个你真正拥有的饮品仓库** ✓ —— 跨平台 ✓、离线优先 ✓、**Windows ✓ Linux ✓ Android 三端可装** ✓。

### 已经有了什么 ✓（`DESIGN.md` §14 的 P0–P4 ✓）

| | |
| **P0 地基** ✓ | 领域层：单位 ✓ 配比 ✓ 匹配评分 ✓，**都有测试 ✓** |
| **P1 单机可用** ✓ | 事件日志 ✓ 种子导入 ✓ 库存与配方页 ✓ **液体颜色渲染 ✓** |
| **P2 视觉完成** ✓ | 货架摆放 ✓ 吧台页 ✓ 价格与统计 ✓ —— **这一条现在的验收标准是「能一边调一杯一边用」✓** |
| **P3 局域网** ✓ | 二维码配对 ✓ 星形同步 ✓ 操作日志合并 ✓ —— **手机与电脑共用一个酒柜 ✓** |
| **P4 三端打包** ✓✓ | **Windows 的 `.msi` ✓、Linux 的 `.AppImage` ✓、Android 三个 ABI 的 `.apk` ✓** —— 三端都构建过、装过、跑过 ✓ |

### 还有一些不在路线图里、但这版有的 ✓

- **四个主题** ✓，**每个都有自己的「世界」而不是换色** ✓
- **声音轴** ✓：同一语言的另一种人格文案 ✓（`heiress` ✓ `minister` ✓ `heiressJa` ✓）
- **设备发现** ✓：按名字找到对方 ✓，像蓝牙那样 ✓
- **`.courtpack`** ✓：一种行分隔的 JSON 包 ✓，可以导出与核对 ✓
- **本地化的边界** ✓：港繁／台繁是生成的 ✓，而机器做不完的那一半写明了 ✓

### 这版**不**声称什么 ✓（说清楚，而不是让人自己发现 ✓）

- **P5 网络层只是部分** ✓：**酒保在 2026-09-23 建过 ✓，又在 2026-09-26 撤掉了** ✗✓ —— **因为它要靠一台跑在读者自己机器上的模型 ✓，那是部署而不是应用的功能 ✓，所以不属于 Stable 的基本内容 ✓**（`DESIGN.md` §11 保留着当时为什么先做它的论证 ✓）；**比价适配器与条码扫描仍是声明 ✓，且按设计关闭 ✓**
- **新设备用配对码配对** ✓ —— **六码比对那个更好的体验还没定 ✓**（它需要你拍板 ✓）
- **走隧道的 VPN** ✓：**已定为第四种链接模式 `tunnel` ✓，而实现还没做 ✓**
- **蓝牙秤／IMU／手柄** ✓：等各自的设备协议 ✓
- **咖啡相关的东西** ✓：还没定 ✓

### 怎么验的 ✓✓

**两个 job，都在 GitHub 的 runner 上跑，都是绿的** ✓：

```
job HMA tools    success ✓   四个阶段：语法 ✓ 工具测试 ✓ 美术规矩 ✓ 美术渲染 ✓
job the product  success ✓   67 个检查步骤：pub get ✓ analyze ✓ 116 个测试文件按目录与按文件拆开跑 ✓
```

**而这件事本身就是这一版最该说的一件** ✗✓：**在 2026-09-27 之前，那条流水线**跑都没跑过** ✓ ——
它被创建了 13 次 ✓，每次一个 job 都没产生 ✓✓。**修好之后它连续逮到七个缺陷 ✓，全部是「只有第二台机器才能发现」的那一类 ✓** ——
**而「能在别人的机器上被证明是好的」正是这版对「完善」的定义 ✓✓**（`docs/HMA.md` §四之一 ✓）。

### 产物

**三端产物在 `E:\Hollow Court Bundle` ✓，一个版本一个文件夹 ✓，默认只留最近三版 ✓✓**
（`tool/keep_bundle.py` ✓ —— **默认演练 ✓，加 `--apply` 才删 ✓**）。
**每个产物旁边一个 `.commit` 旁注 ✓**，记着源提交 ✓、构建时间 ✓ 与 sha256 ✓✓。

### 发布怎么做 ✓

```
python tool/release.py --version 1.0.1+1021            # 演练：只说会做什么
python tool/release.py --version 1.0.1+1021 --apply    # 真做
```

**它先拒绝三件事再动手** ✓✓：**工作树不干净 ✓**（**`MANIFEST.txt` 自己的规矩：脏树让清单没有意义 ✓**）、
**版本没变 ✓**（**那说明这次不该发 ✓**）、**标签已存在 ✓**。
**然后它跑流水线 ✓、发布 ✓、在**镜像那个提交**上打标签 ✓**（**镜像是强推的合成快照 ✓，本地标签会指向不存在的东西 ✓**），
**最后停在需要 token 的那一步并说清剩下什么 ✓✓。**

---

## 1.0.0 —— 构建号 51541（2026-11-26）

**这一版没有新功能。** 它做的是把「东西放在哪」和「哪份源码产出了它」两件事重新说准 —— 前一件事在十一月仓库从 E 盘搬到 D 盘时被打断，后一件事在产物比 HEAD 落后八条提交时被打断。

### 变了什么

- **Windows 的安装位置从 `E:\Hollow Court Win` 迁到 `D:\Hollow Court Win`**。旧那份用 `msiexec /x` 卸载，同一份 `1.0.51540.msi` 重装到新路径；开始菜单快捷方式、防火墙入站规则、注册表卸载项都跟着走。`packaging/windows/hollow-court.wxs` 的默认值同步改成 D，注释里那段论证也一起改 —— 只改默认值不改理由，会留下两句互相打架的话。
- **三平台产物从 `E:\Hollow Court Bundle` 改到 `D:\hollow-court\dist`**。`build_all.sh`、`android/build.sh`、`windows/build.sh`、`make_manifest.sh`、`staleness.sh` 的默认值一起改。
- **`dist/` 与 `keys/` 进了 `.gitignore`**：前者可重建而且太大，后者是 Android 的签名身份。

### 修了什么

- **产物追上 HEAD**。`dist` 里上一版产物来自 `af8d667`，而 HEAD 已经走到 `b166909`。同版本重建在 Windows 上不算替换（同版本同 ProductCode 是一次修复），所以版本号与 `ProductCode` 一起动，产物才真的换了内容。
- **Linux 在 CMake 4 下能构建了**。`linux/CMakeLists.txt` 原来靠 `CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT` 兜安装前缀，CMake 4.3.2 不再为这份模板置这个变量，安装阶段就去写 `/usr/local/hollow_court` 并被权限挡下。现在 `/usr/local` 也算「没人选过前缀」。
- **工具链路径清理**。`JAVA_HOME`、`ANDROID_HOME`、`ANDROID_SDK_ROOT` 原先指向搬盘后剩下的空壳目录，现在指回 D 盘的完整副本；九个脚本里指向旧仓库根与旧产物目录的默认值一并改正。
- **Android 构建适配这台机器**：Gradle 堆从 8G 降到 4G，并关掉 Kotlin 增量缓存 —— 每次都是全量构建，它省不下东西，而它失败一次要十六分钟。

### 不声称什么

- **没有动产品行为**。这一版装的还是同一个应用：界面、配方、同步都没有变。
- **Linux 那份 AppImage 只在 WSL 里构建过**，没有在真实的 Linux 桌面上跑过。构建环境的 glibc 是 2.43，而那个发行版接下来要全量升级；升级之后需要重新验一次它还能起窗口。
- **WiX 必须是 5.x**。7.x 会要求在装机时接受一份收费的 OSMF 条款，并为此停下（`WIX7015`），这个仓库没有也不需要那份协议。

---

## 1.0.0 构建号 51541 之后：Linux 与 macOS 只走 portable（2026-11-27）

**这一条写在同一版构建之后，因为它改的是发行形态，代码没有变。**

- **不再构建 AppImage**。Linux 的那份改为 `hollow-court-<version>-portable.zip` 里的 `linux/` 目录，也就是 `build/linux/x64/release/bundle`（18 个文件、29.9 MB）。`packaging/linux/build_appimage.sh` 留在树里但不再被调用，所以这个决定用一行就能改回来。
- **新增 portable 归档**，由 `packaging/portable/make_portable.ps1` 生成：`windows/` 收 `build\windows\x64\runner\Release` 整个目录，解压即用，没有安装步骤也没有卸载步骤；`linux/` 收上面那份 bundle；`macos/` 收 `.app`，条件是这台机器上真的构建过。归档里附一份 `README.txt`，说清每个平台跑哪个文件，以及解压工具丢掉执行位时该 `chmod +x` 哪一个。
- **macOS 目前只有 portable 这一条路**，而且前提是先在一台 Mac 上构建：Flutter 的 macOS 目标要走 xcodebuild，没有跨平台构建的路径。本机是 Windows，所以今天的归档里没有 `macos/` 那一份，`README.txt` 里写的是「没有构建过」，而不是把缺的当成有。

**不声称什么**：归档里的 Windows 与 Linux 两份没有分别做过启动测试 —— 它们是各自平台构建输出的原件，与 MSI 装出来的内容同源，Linux 那份与旧 AppImage 的内层相同。

---

## 构建号 51541 之后：伊丽莎白的对话（2026-11-27）

**这一条写在同一版构建之后，因为它改的是应用，产物还没有重建。**

### 变了什么

- **回复不再是一段纯文本。** `lib/ui/chat_render.dart` 把回复解析成段落、标题、无序与有序列表、围栏代码块和表格；粗体、斜体、行内代码画出来而不是剥掉。四张图（折线、K 线、柱状、饼）由一个围栏代码块里的 JSON 画出来，用的是画布，不是图表库。数据读不出来时原文留在图上并附一句说明。
- **图标。** 句子里写 `:wine:` 会变成一个小图标。表在 `lib/ui/chat_icons.dart`，四十个名字，都是这个应用真正关心的事情。名单外的一律原样显示成冒号和字母 —— 猜错一个名字应当看起来是错的，而不是让一个词消失。
- **两个只读工具。** `read_recipe` 按名字或 id 读一条完整配方（含做法与步骤）；`recipe_strength` 走 `domain/dosing/abv.dart` 与 `dilution.dart`，按每条原料自己的酒精度和做法算成品度数。测试里那杯琴蕾：未稀释 26.7%，加冰后 22.7%。原料没写酒精度时会在答案里被点名，而不是当作零。
- **对话可以重开，也可以中途喊停。** 标题栏一个按钮清掉当前这一段（内存与磁盘一起）；流式回复期间发送键变成「停」，说过一半的话留作一条回复。
- **附件先缩再发。** `lib/data/image_compress.dart` 把长边压到 1280、重新编码成 JPEG，在后台 isolate 里跑。认不出的字节原样送出去。
- **提示词带日期。** `elizabethSystemPromptOn(DateTime)` 在前面加一句今天几号。模型没有钟，问「今年」时它会拿训练数据里的年份当现在。

### 修了什么

- **`_busy` 卡死。** `chat_client` 只把 `SocketException` 转成 `ChatFailure`，而 `HandshakeException`（代理、中间证书）与 `HttpException`（服务端半途断开）都是 `IOException` 的兄弟，会原样穿到界面上，`_busy` 停在 true，除了重启应用没有别的出路。现在两者都归到 `unreachable`，界面另有一个兜底。
- **请求没有超时。** `connectionTimeout` 只管握手，之后服务端不说话就一直等下去。现在两个事件之间超过六十秒算超时，keep-alive 行会把它重置。
- **附件一律声明成 JPEG。** 相机写的就是 JPEG，而相册里选的可能是 PNG、WebP、HEIC。现在按 magic bytes 认六种，认不出才退回 JPEG。
- **每一轮重发全部历史。** `ChatClient.trimHistory` 只发最近八轮，切在 user 消息上，绝不切进工具往返中间 —— 一条 `tool_calls` 少了它的 `tool` 回答，整个请求会被直接拒。被裁掉的只是发给模型的那一部分，屏幕和磁盘仍然完整。
- **`converse` 没有测试。** 五条既有用例走的是 `stream`，而界面走的是 `converse`。现在有 14 项，最要紧的一项把 `tool_calls` 的 arguments 按三个字符一片喂进去，验证能拼回一个完整对象。
- **相机缺席是 Error 不是 Exception。** `camera` 没有 Linux 与 macOS 实现，`availableCameras()` 落到接口默认体抛 `UnimplementedError`；两个相机页面只 `on Exception`，所以 Linux 上点「用摄像头扫」会抛未捕获异常，而那句早已写好的「这台机器没有相机」一直没被用上。
- **`macos/` 缺 provenance 规则。** 它随平台一起进来，`principles_test` 在下一次完整测试里报了出来：二十八个未分类的跟踪文件。

### 不声称什么

- **`dist` 里那八份产物还是旧的。** 它们全部显示 `OTHER:b166909`，而这是真话：这一轮改了 `lib/`，它们不含这些改动。要让 manifest 重新全绿只有提升版本号重建 —— 同版本重建在 Windows 上什么也换不掉，那句话已经写在 `b166909` 的提交信息里。
- **macOS 那一份没有在真 Mac 上构建过。** `macos/` 平台、entitlements、`NSCameraUsageDescription` 与一份手动触发的 workflow 都在树里，但没有一次真实构建。相机在 macOS 上仍然不可用，`camera_macos` 是第三方包且 API 与 `camera` 不同。
- **图表与图标只在她的回复里生效。** 读者自己打的字仍然按纯文本显示 —— 一个人说的话不该被当成标记来解释。

---

## 构建号 51541 之后：macOS 的第一次真机构建（2026-11-27）

**这一条也写在同一版构建之后。这一次不是推测，是一次跑通的记录。**

`flutter build macos --release` 在 GitHub 的 `macos-latest` runner 上跑了一次，四分三十九秒，通过。

### 变了什么

- **图标。** `art/render_icons.sh` 一直只给三个平台装图标，macOS 那份还是 Flutter 的占位图。现在七个尺寸（16 到 1024）从同一张源图的同一套 SVG 层级装进 `AppIcon.appiconset`，文件名照模板带来的 `Contents.json`。源码里没有 macOS 平台时这一段跳过。
- **提示词里那句「Intel runner 产 x86_64」被实测推翻。** 产物是 universal：主可执行文件、`FlutterMacOS.framework`（30.0 MB）、`App.framework`（23.9 MB）各自带 x86_64 与 arm64。模板不设 `ONLY_ACTIVE_ARCH`，所以在 Intel 上也能出双架构。`docs/macos.md` 与 `macos.yml` 的注释都按实测改过。

### 修了什么

- **144 那一档的图标每次渲染字节都不同。** 两次实测 `56869b03` 与 `671d6998`，而旁边的 256 稳定。原因是 144 是唯一要过 `magick` 减半的一档，而 `magick` 会往 PNG 的文本块里写 `date:create` 与 `date:modify`。加上 `-define png:exclude-chunks=date,time` 之后两次一致。Android 的 xxhdpi 启动图标从同一个文件装，所以这一条以前每渲染一次就留下两个没头没脑的 diff。

### 从那一次构建里能核对的

- 73 个条目全在 `Hollow Court.app` 里 —— `PRODUCT_NAME` 那条覆盖生效了，不是模板默认值。
- 九个符号链接都保住了：`objective_c`、`FlutterMacOS`、`App` 三个 framework 的 `Versions/Current` 与它们的顶层链接都在，`ditto` 的选择是对的。
- 产物在 `D:\DaShaoHuo\downloads\hc-macos-artifact\hollow-court-macos.zip`。

### 不声称什么

- **没有在任何 Mac 上启动过。** 构建成功与能运行是两件事，中间隔着签名、quarantine 与一次真实的双击。
- **这一次只产出了 `.app` 本身。** 合并进 portable 归档是下一件工作，记在下面那一节里。
- **相机在 macOS 上仍然没有。** `camera` 没有 macOS 实现，`camera_macos` 是第三方且 API 与它不同。
- **签名是 ad-hoc 的。** 没有 Apple Developer 账号，从网上下来的包第一次打开要 `xattr -dr com.apple.quarantine`。

---

## 构建号 51541 之后：portable 归档拿到 macOS（2026-11-27）

**这一条同样写在同一版构建之后。它记的是打包这一步，不是应用本身。**

portable 归档现在真的装得下三个平台。`packaging/portable/make_portable.ps1` 多了一个 `-MacArtifact` 参数，收的是 macOS 那个 job 上传的 ZIP；本机自己的 `build\macos\Build\Products\Release\*.app` 仍然优先，所以在一台 Mac 上跑时行为不变。

### 变了什么

- **归档不再由 `Compress-Archive` 写。** 新的 `packaging/portable/make_portable_zip.py` 逐条写 `ZipInfo`，每条都明说 `create_system = 3` 与自己的 Unix mode。理由与实测数字见 `docs/macos.md` 第一节「合并进 portable 归档」。
- **Linux 的可执行位现在记在归档里。** 旧归档 45 条全是 `ExternalAttributes = 0`，`linux/hollow_court` 也在其中 —— 那正是 README 要教读者 `chmod +x` 的原因。现在它是 `0o100755`，保留 Unix mode 的解压器不需要那一步。README 也按这个事实重写了。
- **macOS 那一段的 README 按有没有 `.app` 分两种写法。** 有就写双击、被 Gatekeeper 拦住怎么办；没有就说这一份不在归档里。以前那句「build it on a Mac first」是写死的，两种情况下都印。

### 修了什么

- **`writestr` 的第二个参数是数据，不是文件名。** 第一版写成 `sink.writestr(info, path)`，于是 windows/ 与 linux/ 每一个条目的内容都成了它自己的路径字符串。产物 23.6 MB，比被它替换掉的 27.8 MB 还小，脚本一句抱怨都没有。改成显式 `open(path, 'rb').read()` 之后 51.4 MB。
- **三个平台都齐时，README 的 `Not included:` 下面是空的。** 空列表读起来像漏写，现在那一行写 `nothing -- all three platforms are in this archive`。

### 从那一次装配里能核对的

- 139 个条目：README 1、windows 33、linux 32、macos 73。九个符号链接，`create_system` 全是 3。
- 111 个非目录条目逐条与源比过 CRC：windows 20 个文件对 `build\windows\x64\runner\Release`，linux 18 个对 `build\linux\x64\release\bundle`，macOS 73 条对 CI artifact，零处不符。
- 符号链接这件事由两个互不相关的实现分别确认：Python 的 `zipfile` 读出 `0o120000` 与目标路径，Windows 自带的 `tar.exe`（libarchive）把它显示成 `lrwxr-xr-x ... -> Versions/Current/Resources`。只看一个实现不算验证。

### 不声称什么

- **没有在一台 Mac 上解开过。** 归档的条目说它们是符号链接，两个实现都同意，而真正把九个链接还原出来这件事发生在 macOS 上，那一步这台机器做不到。
- **这一批产物的版本号是 `1.0.0.zipcheck`。** 它是一次装配检查，不进 release；正式的那一份要等下一次改 `pubspec.yaml` 并全量重建。
- **`-MacArtifact` 要手工指路径。** 没有自动去 GitHub 取最新 artifact 的那一步，因为那需要 token 与一次网络调用，而这两样在打包脚本里都是新的失败面。

---

## 模板（下一版从这里开始 ✓）

```
## <版本> —— <日期>

### 变了什么
-

### 修了什么
-

### 不声称什么
-
```
