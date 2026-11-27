# macOS 支持：做到了哪里，以及哪些条件这台机器给不了

这份文件回答一个问题：仓库里已经有的 macOS 东西，哪些是真做完了，哪些只是因为手上没有那台机器而停在这里。

判断的标准只有一条：**在 Windows 上完成并验证过的，写在第一段；需要一台 Mac 或一个苹果开发者账号才能继续的，写在后面的段里，并说明缺的具体是什么条件。** 不把「没验证」写成「应该没问题」，那两句话对读者的用处完全不同。

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

`packaging/portable/make_portable.ps1` 已经在收 `build\macos\Build\Products\Release\*.app`，这个脚本不用改。

---

## 二、已写好，但没有在 Mac 上跑过一次

**上面第一节的每一项都属于这一段。** 没有任何一次 `flutter build macos` 发生过，`macos.yml` 也从未被触发。写下的配置是按 Flutter 模板与本项目的实际情况填的，不是按一次成功构建的输出校对的。

具体来说，下面这些在 Windows 上无从验证：

- 第一次 `flutter pub get` 在 macOS 上生成的 `macos/Flutter/ephemeral/GeneratedPluginRegistrant.swift` 是否正确登记了各个插件。
- SPM 与 CocoaPods 的选择。这套脚手架目前走 Swift Package Manager（没有 `Podfile`），如果以后接入一个只支持 CocoaPods 的插件，Flutter 会回退并生成 `Podfile`。那一步没有发生过。
- `MACOSX_DEPLOYMENT_TARGET = 12.0` 是否与将来的依赖相符。模板给的是 12.0。
- entitlements 是否够用、是否过量。没有一次运行去观察沙箱实际拒绝了什么。

---

## 三、需要一台 Mac，缺的就是这台机器

- `flutter build macos --release`。Flutter 的 macOS 目标驱动 `xcodebuild`，而 `xcodebuild` 只在 macOS 上存在。
- Dart 的 AOT 步骤需要一份 darwin 宿主的 `gen_snapshot`，它只在 macOS 上被下载。
- 关于交叉编译：`osxcross` 与 `zig cc` 能从 Linux 产出 Mach-O 目标文件，`apple-codesign`（`rcodesign`）能在 Linux 上签名与公证，但没有任何东西能在没有 Xcode 的情况下组装一个 `.app`。Darling 把 Xcode 列在它跑不起来的软件里。这条路是通的环节已经通了，卡住的是中间那一段。

---

## 四、需要一个苹果开发者账号，缺的是那份凭据

- 开发者证书签名。没有它，产物是 **ad-hoc 签名**（`project.pbxproj` 里 `CODE_SIGN_IDENTITY = "-"`，这是模板自己的选择），从网上下载之后带 quarantine 标记，第一次打开要先 `xattr -dr com.apple.quarantine "Hollow Court.app"`。
- 公证与 `stapler`。去掉上一步的办法是公证，而那需要账号。

没有账号时，ad-hoc 加一行说明是能给出的最好结果，这一行写在 portable 归档的 README 里。

---

## 五、需要接口层面的工作，缺的是一个官方实现

相机在 macOS 上不可用。`camera` 的实现只有 Android、iOS、Windows 与 web，macOS 与 Linux 都没有，`availableCameras()` 在这两个平台上会抛 `UnimplementedError`。

第三方有 `camera_macos`，但它的 API 与 `camera` 不同（给的是 `CameraMacOSView` 与 `CameraMacOSController`），接入等于在两个页面里重写相机那一段，而且它只能在一个 macOS 构建里被验证。这件事在拿到一台 Mac 之前不动。

实际影响比听起来小：这个应用把「没有相机」当成正常路径，手动输入条码是第一等的输入方式，相机是后加的。所以 macOS 版能跑、能手动输入、点扫条码时说出「这台机器没有相机」。

---

## 六、这张表以后再改时

每一项改动都应当能在上面五段里找到它的位置。新做到的一步，从第三段挪到第一段；新发现的、需要某个条件的，写清缺的是什么。**「应该能用」不属于任何一段。**
