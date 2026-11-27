# macOS 支持：做到了哪里，以及哪些条件这台机器给不了

这份文件回答一个问题：仓库里已经有的 macOS 东西，哪些是真做完了，哪些只是因为手上没有那台机器而停在这里。

判断的标准只有一条：**在 Windows 上完成并验证过的，写在第一段；需要一台 Mac 或一个苹果开发者账号才能继续的，写在后面的段里，并标上「无对应条件」、说明缺的具体是什么。** 不把「没验证」写成「应该没问题」，那两句话对读者的用处完全不同。而「无对应条件」也不是「不做」—— 第六段说明这四个字的确切含义。

---

## 一、已完成，且在这台机器上可以核对

### 平台脚手架

`flutter create --platforms=macos --org com.nesarf .` 生成，28 个跟踪文件：runner、Xcode 工程、entitlements、资源目录。`Flutter/ephemeral/` 那 6 个由 `macos/.gitignore` 排除。

`tool/provenance.json` 里 `macos/**` 归 `platform` 类，与 `windows/**`、`linux/**` 同一个理由：host 文件是 Flutter 的模板，不声称是自己写的；里面改过的东西写在改它的那个提交里。

### 应用身份

`macos/Runner/Configs/AppInfo.xcconfig`：

```
PRODUCT_NAME = Hollow Court
PRODUCT_BUNDLE_IDENTIFIER = com.nesarf.hollowCourt
```

产物因此叫 `Hollow Court.app`，与 `packaging/portable/make_portable.ps1` 写进 portable 归档 README 的那个名字一致。这个名字通过 `project.pbxproj` 里 target 层的 `baseConfigurationReference` 生效，覆盖工程层的 `$(TARGET_NAME)`——不是靠模板的默认值。

### 权限

两份 entitlements 都加了 `com.apple.security.device.camera`；`Release.entitlements` 另外加了 `network.client` 与 `network.server`，因为模板的 release 配置一项网络权限都没有，而这个应用的局域网设备发现要靠它。

`Info.plist` 加了 `NSCameraUsageDescription`。**麦克风那一项没有加**：两处相机调用都是 `enableAudio: false`，要一个用不上的权限正是扫描页自己的注释里反对的那种多事。

### 图标

七个尺寸（16、32、64、128、256、512、1024）由 `art/render_icons.sh` 从 `art/mark-source.png` 经同一套 SVG 层级渲染，与其他两个平台同一张源图。`Contents.json` 由模板带来，没有改。

### 构建系统里的位置

`.github/workflows/macos.yml`：`workflow_dispatch` 触发，`macos-latest`，用 `ditto -c -k --sequesterRsrc --keepParent` 打包（`upload-artifact` 写的是条目不是符号链接，直接传目录会把 framework 里的版本链接压平）。

`packaging/portable/make_portable.ps1` 收 `build\macos\Build\Products\Release\*.app`；本机没有这个目录时，改用 `-MacArtifact` 指向 CI 上传的那份 ZIP。合并怎么做的、旧做法错在哪里，见下面「合并进 portable 归档」。

### 构建跑过一次，而且成功了

**2026-11-27，GitHub 的 `macos-latest` runner，`flutter build macos --release` 通过，四分钟三十九秒。** 产物 73 个条目、23.07 MB，全部在 `Hollow Court.app` 里 —— `PRODUCT_NAME` 那条覆盖确实生效了，不是模板默认值。

三件事因此从猜测变成事实：

- **符号链接保住了九个。** `ditto -c -k --sequesterRsrc --keepParent` 写出的条目带 `0o120000` 的 mode 位，`objective_c`、`FlutterMacOS`、`App` 三个 framework 的 `Versions/Current` 与它们的顶层链接都在。`ditto` 的选择是对的。
- **三个二进制都是 universal。** 主可执行文件、`FlutterMacOS.framework`（30.0 MB）、`App.framework`（23.9 MB）各自带 x86_64 与 arm64 两套代码。**这一条与原先的猜测相反** —— 原来写的是「Intel runner 产 x86_64，Apple Silicon 需要 Rosetta 2」。模板不设 `ONLY_ACTIVE_ARCH`，所以 Flutter 在 Intel 上也能出双架构。`.github/workflows/macos.yml` 里那段注释已经按实测改过。
- **整个平台脚手架能编译。** 之前这条只能在 Mac 上验证，现在有了一个替代路径。

产物在 `D:\DaShaoHuo\downloads\hc-macos-artifact\hollow-court-macos.zip`。**不要用 Windows 的解压去开它** —— 那会把九个符号链接压平成普通文件，bundle 看起来完整而加载不起来。要看内容用 `zipfile` 只读，要解开只能在一台 Mac 上或者用保留符号链接的工具。

### 合并进 portable 归档

**这一节记的是打包，不是应用。** 做完之后 portable 归档真的装得下三个平台；之所以值得单开一节，是因为上一版归档里有两个从没人看过的错误。

**旧归档 45 个条目的 `ExternalAttributes` 全是 0。** `Compress-Archive` 不写 Unix mode，于是两件事同时成立：`linux/hollow_court` 的可执行位没有记进归档（这是 README 要教读者 `chmod +x` 的由来），以及没有任何条目能说「我是一个符号链接」—— 一个 `.app` 解开之后会是九个装着路径文本的小文件，目录树完整，加载失败。

**新归档由 `packaging/portable/make_portable_zip.py` 写。** 它逐条构造 `ZipInfo`，`create_system = 3`，mode 自己声明，所以归档的含义与装配它的机器是哪一台无关。三个来源走三条路：

| 来源 | 怎么进来 | 为什么是这条路 |
| --- | --- | --- |
| `windows/` | `--tree` 直接读 `build\windows\x64\runner\Release` | 没有链接要处理，但 mode 仍要声明，否则解开后分不清文件与目录 |
| `linux/` | `--tree` 直接读 `build/linux/x64/release/bundle`，`hollow_court` 标 0755 | 可执行位只能在这里写进去 |
| `macos/` | `--zip` 把 CI artifact 的条目逐条重发，`external_attr` 一个字节不动 | 解压这一步在 Windows 上就已经把链接毁了，所以整条路不经过解压 |

**连「在一台 Mac 上跑」那条路也走 `--tree`，不走 `Copy-Item`。** `Copy-Item -Recurse` 跟随符号链接，在一台真有 Mac 的机器上把 `.app` 复制到暂存目录再打包，同样会把九个链接变成九个文件。`--tree` 用 `os.readlink` 自己读、自己写回链接条目，中间没有一步要信任复制工具。

**这一次装配能核对的：** 139 个条目（README 1、windows 33、linux 32、macos 73），九个符号链接，`create_system` 全为 3，51.4 MB。111 个非目录条目逐条与源比过 CRC：windows 20 个对 `build\windows\x64\runner\Release`，linux 18 个对 `build\linux\x64\release\bundle`，macOS 73 条对 CI artifact，零处不符。符号链接这件事由两个互不相关的实现分别确认 —— Python 的 `zipfile` 读出 `0o120000` 与目标路径，Windows 自带的 `tar.exe`（libarchive）把它显示成 `lrwxr-xr-x ... -> Versions/Current/Resources`。只看一个实现不算验证。

**没有做到的：** 把归档真的解开来、看那九个链接还原得对不对 —— **无对应条件（缺一台 Mac）**。归档说那九条是链接，两个实现都同意，而还原发生在 macOS 上。`-MacArtifact` 要手工指路径是另一回事：它缺的是一个自动取 artifact 的环节，与有没有 Mac 无关。

---

## 二、没有在 Mac 上使用过

**这里的「用过」指一次真实的双击与一轮使用，不是一次 CI 构建。** 第一节那次构建已经证明了四件事：脚手架能编译，图标能被 `xcodebuild` 接受，插件登记在 SPM 下能生成并链接，现有依赖树接受 12.0 这个部署目标。它没有证明的是这个应用打开之后的行为。

下面四条都只能在一台 Mac 上回答 —— **无对应条件（缺一台 Mac）**：

- **entitlements 够不够、有没有过量。** 沙箱实际拒绝什么只有运行才知道；构建只证明它们语法合法。
- **第一次打开会不会被 Gatekeeper 拦住，拦住之后右键打开能不能过。** 这是 ad-hoc 签名的包带着 quarantine 标记时的运行时行为。
- **窗口尺寸、字体、控件看起来对不对。** 桌面端的布局只在桌面端成立，Windows 与 Linux 的截图替不了它。
- **局域网发现能不能连上另一台设备。** `network.client` 与 `network.server` 都在 release entitlements 里，而沙箱放不放行要两家都跑起来才知道。

这里原来还列着 `GeneratedPluginRegistrant.swift`、SPM 与 CocoaPods 的选择、`MACOSX_DEPLOYMENT_TARGET = 12.0` 三项。它们是**构建期**的问题，2026-11-27 那次构建把它们变成了观测：插件登记生成了，SPM 这条路走通了，12.0 与现有依赖相符。**而 SPM 那一条只说明「这一次没有问题」** —— 将来接入一个只支持 CocoaPods 的插件时，Flutter 会回退并生成 `Podfile`，那一步仍然没有发生过。

---

## 三、无对应条件：需要一台 Mac

**这一段缺的是同一样东西 —— 一台 Mac。** 这些条目记为「无对应条件」，因为推进它们需要的不是更多时间或更多代码，而是这台机器没有的硬件与操作系统。

- **在本机上构建与运行。** CI 的 `macos-latest` runner 已经能产出 `.app`（见第一节），所以「构建」这一格不再是缺口。缺的是本机做不了：Flutter 的 macOS 目标驱动 `xcodebuild`，而 `xcodebuild` 只在 macOS 上存在；Dart 的 AOT 步骤要一份 darwin 宿主的 `gen_snapshot`，它只在 macOS 上被下载。
- **交叉编译这条路，查过，通不了。** `osxcross` 与 `zig cc` 能从 Linux 产出 Mach-O 目标文件，`apple-codesign`（`rcodesign`）能在 Linux 上签名与公证，但没有任何东西能在没有 Xcode 的情况下组装一个 `.app`。Darling 把 Xcode 列在它跑不起来的软件里。能通的环节都通了，卡住的是中间那一段。**这一条查过一次就不必再查**，除非上面某个工具发生了变化。

---

## 四、无对应条件：需要一个苹果开发者账号

**这一段缺的是一份凭据。** 代码层面该做的已经在做了：产物是 **ad-hoc 签名**（`project.pbxproj` 里 `CODE_SIGN_IDENTITY = "-"`，这是模板自己的选择），portable 归档的 README 写清了第一次打开怎么过 Gatekeeper。

- **开发者证书签名。** 有证书，产物就不带 quarantine 的麻烦，读者不必先跑一遍 `xattr -dr com.apple.quarantine "Hollow Court.app"`。
- **公证与 `stapler`。** 去掉那一步的另一种办法是公证，那同样要账号。

没有账号时，ad-hoc 加一行说明是能给出的最好结果，这一行写在 portable 归档的 README 里。

---

## 五、需要接口层面的工作，缺的是一个官方实现

相机在 macOS 上不可用。`camera` 的实现只有 Android、iOS、Windows 与 web，macOS 与 Linux 都没有，`availableCameras()` 在这两个平台上会抛 `UnimplementedError`。

第三方有 `camera_macos`，但它的 API 与 `camera` 不同（给的是 `CameraMacOSView` 与 `CameraMacOSController`），接入等于在两个页面里重写相机那一段，而且它只能在一个 macOS 构建里被验证 —— **无对应条件（缺一台 Mac，也缺一个与 `camera` 同接口的实现）**。这件事在拿到一台 Mac 之前不动。

实际影响比听起来小：这个应用把「没有相机」当成正常路径，手动输入条码是第一等的输入方式，相机是后加的。所以 macOS 版能跑、能手动输入、点扫条码时说出「这台机器没有相机」。

---

## 六、这张表以后再改时

**「无对应条件」是一个状态，不是一句待办。** 它说的是：这件事已经想清楚、写下来了，而继续推进它需要某个这台机器没有的东西 —— 一台 Mac、一个 Apple 开发者账号。这样的条目不该读成「还没做」，也不该读成「不做」；条件出现时，它们就是下一批要做的事。**四个字是固定的，因为它要能被 grep**：`grep -rn '无对应条件（' docs/` 会列出全部条目，因为条目统一写成「这四个字紧跟一个括号，括号里是缺的那个条件」；定义句与段落标题后面跟的是冒号或句号，所以不会混进来。

每一项改动都应当能在上面五段里找到它的位置。新做到的一步，从第三段或第四段挪到第一段；新发现的、需要某个条件的，写清缺的是什么并标上「无对应条件」。**「应该能用」不属于任何一段。**
