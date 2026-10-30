# 工程地图：HC-S 与 HMA

这份文件回答一个问题：**想改某样东西，该去哪个文件**。

它不是设计文档（那是 `DESIGN.md`），也不是待办（那是 `TODO.md`）。它是一张索引，写给第一次进这个仓库的人，也写给三个月后忘了自己把东西放在哪的自己。

---

## 一、两个工程，一个仓库

| 名字 | 是什么 | 在哪 |
| --- | --- | --- |
| **HC-S**（Hollow Court Stable） | 跨平台饮品库存应用本体 | 仓库根目录 |
| **HMA**（Hollow Court / Harumi's Maintenance Assistant） | 这个仓库自己的开发平台：诊断、模型调用、验证、发布 | `tool/hma*.py` |

它们是**两个镜像分支上的两份东西**：`HC-Stable` 带应用本体，`HMA` 带文档与工具。发布由 `tool/publish_public.sh` 从本仓库合成快照推上去，**任何一个分支的提交历史都不是本仓库的历史**。

一句话记住：**HC-S 是产品，HMA 是怎么维护它。**

---

## 二、HC-S 的五层

```
lib/
├── main.dart          入口：建 app、装 provider
├── ui/        78 个   画面与交互。只有这一层认识 Flutter 的 widget
├── domain/    71 个   规则。纯 Dart，不 import flutter，不碰文件
├── data/      24 个   落盘、文件、网络之外的 IO
└── adapters/  8 个    对外面世界的四道门，每道门自带一份披露
```

顺序是**依赖单向**：`ui` 知道下面四层，`domain` 谁都不认识。`test/` 的目录结构照着这个分层走（adapters 4、data 26、domain 59、ui 60、tooling 2）。

### ui —— 画面

| 想改的 | 文件 |
| --- | --- |
| 底部五个 tab 怎么装 | `ui/app.dart`（`IndexedStack`，顺序即 tab 顺序） |
| 底部栏本身 | `ui/hollow_nav_bar.dart` |
| 颜色、字号、全部文案 | `ui/theme.dart`（`HollowPalette`、`HollowType`、`Copy` 全在这一个文件里） |
| 文案怎么随语言与声音解析 | `ui/l10n/`（`dual_copy.dart` 是核心：`CopyLine` 与 `Voice`） |
| 酒窖 / 配方 / 原料 / 记录 / 设置 | `ui/` 下同名 `*_page.dart` |
| 记一瓶的表单 | `ui/stock_page.dart` |
| 对话（伊丽莎白的房间） | `ui/chat_page.dart`、`ui/chat_seam.dart`、`ui/chat_providers.dart` |
| 对话的三项设置 | `ui/chat_settings_section.dart` |
| 扫码 | `ui/barcode_scanner_page.dart`；解码在 `data/barcode_decoder.dart` |
| 拍一张照片 | `ui/photo_capture_page.dart` |

### domain —— 规则

| 子目录 | 文件数 | 管什么 |
| --- | --- | --- |
| `events/` | 12 | **整个应用的事实来源**：事件、HLC 时钟、库存账本、日志压缩 |
| `model/` | 17 | 原料、配方、瓶子、条码、货币、集合 |
| `sync/` | 13 | 配对、短码、加密通道、握手 |
| `pricing/` | 7 | 价格、成本、货币换算 |
| `units/` | 6 | `Volume`（微升为整数）、计量单位 |
| `dosing/` | 4 | 配方用量与稀释 |
| `overlay/` | 3 | 读者自己的覆盖层（改名、自建条目） |
| `stats/` | 3 | 收支与消耗统计 |
| `preferences/` | 2 | 设置的数据形状 |
| `archive/`、`consumption/`、`matching/`、`parsing/` | 各 1 | 归档、消耗曲线、名字匹配、解析 |

**入口在 `events/`。** 库存不是一个可变对象，是一条事件日志折叠出来的结果；想理解「为什么这瓶显示 700 毫升」，从 `domain/events/stock.dart` 的 `StockLedger` 开始。

### data —— 落到磁盘或出去

`event_log.dart`（追加写）、`event_store.dart`（读写与锁）、`cellar_lock.dart`（两个进程抢一个酒窖）、`archive_package.dart`（打包与恢复）、`barcode_registry.dart`（码到原料的本地表）、`chat_settings.dart`（三项设置，密钥加封）、`chat_history.dart`（对话，最多两百轮）、`camera_permission.dart` / `image_picker_channel.dart`（两条平台通道）。

### adapters —— 四道门

`declared.dart` 里声明四道：比价（未实现）、条码（可用）、外设（未实现）、对话（可用）。`registry.dart` 持有开关与披露，`barcode_catalog.dart`（Open Food Facts）、`chat_client.dart`（OpenAI 兼容 + 工具循环）、`web_search.dart`（DeepSeek Search）、`cellar_tools.dart`（她读得懂的东西与她的提议）、`update_check.dart`（GitHub releases）。

每道门的披露回答同一件事：**什么会离开这台机器**。条码是一个数字，对话是对话加上她读过的库存 —— 这两句不一样，所以 `sendsAnythingAboutTheCellar` 一个是 false 一个是 true。

---

## 三、一条数据怎么走

```
屏幕点下「记下」
   → ui/stock_page.dart 校验
      → domain/model 与 domain/units 换算成微升
         → data/event_log.dart 追加一条 StockEvents.bottleAdded
            → 文件（cellar.ndjson）
               → 折叠回 domain/events/stock.dart 的 StockLedger
                  → ui 重新画
```

**没有服务器，没有账号，没有网络。** 联网只发生在适配器那几道门里。条码与对话这两道自 2026-10-22 起默认打开，另外两道（比价、外设）还没有实现，所以不出现在界面上。

**默认打开不等于默认发送。** 对话那道还要读者自己填 key；填之前，一个字节都不会出去。

两条旁路：`domain/sync/` 让两台设备交换缺失的事件（同一份日志，不是同一份文件）；`adapters/` 让外面的事情进来（一个码是什么、她说了什么）。

---

## 三之二、平台通道：三条缝

Dart 做不到的三件事，各用一条 `MethodChannel` 交给平台，**都不引第三方插件**。三条都在 `MainActivity.kt`。

| 通道 | 干什么 | Dart 侧 |
| --- | --- | --- |
| `com.nesarf.hollow_court/open_url` | 在系统浏览器里打开一个地址 | `ui/open_url.dart` |
| `com.nesarf.hollow_court/camera_permission` | 要相机权限（运行时） | `data/camera_permission.dart` |
| `com.nesarf.hollow_court/picker` | 从系统选择器选一张图 | `data/image_picker_channel.dart` |

**为什么是手写而不是插件。** 相机那两条最初都用插件试过：`permission_handler` 要求 compileSdk 37，而本工程在 36；选图那个 `image_picker` 是同一个风险面。为一个权限或一张照片把整条工具链升一级，不划算，所以改成二十行 Kotlin。代价写在各自文件里。

**选图那条用的是 `startActivityForResult`**，不是 `registerForActivityResult` —— 后者在这个工程的 `FlutterActivity` 上解析不到，要 `activity-ktx`。代价是：选择器开着时转屏会丢回执。选择器只开几秒，这个失败可见，可接受。

---

## 四、测试：地图的另一半

| 目录 | 断言什么 |
| --- | --- |
| `test/domain/` | 规则。59 个文件，不需要 Flutter，跑得最快 |
| `test/data/` | 落盘、加解密、打包、兼容旧文件 |
| `test/ui/` | 画面。多，而且慢，因为要起 widget 树 |
| `test/adapters/` | 四道门。**全部用注入的传输层，一个测试都不碰网络** |
| `test/tooling/` | 工具本身（例如 `sync_assets.sh` 的产物与 `data/` 一致） |

有几项测试**专门用来防止事情退回去**，改代码时它们会先叫起来：

- `test/data/seed/shipped_assets_match_the_data_test.dart` —— `assets/` 与 `data/` 必须逐字节一致
- `test/ui/voice_repetition_test.dart` —— 声音里那几种套话收尾不许回来
- `test/ui/world_art_fidelity_test.dart` —— 背景插画不许是 `const`
- `test/data/chat_settings_test.dart` —— 「空 key 保存不许抹掉已存的 key」。这条是补的，因为它是真的发生过：一个空字段抹掉了一把填好的 key
- `test/adapters/chat_client_test.dart` —— 工具调用与 `reasoning_content` 的回传，以及 200 里夹着的错误
- `test/adapters/update_check_test.dart` —— 三种写法的版本号要比出同一个数
- `.github/workflows/verify.yml` —— 每个 `*_test.dart` 都必须真的被某一步跑到

---

## 五、打包与发布

| 想做的 | 命令 |
| --- | --- |
| 三平台一起构建 | `bash packaging/build_all.sh`（三个 worktree 并行，产物到 `E:\Hollow Court Bundle`） |
| 单个 Windows 安装器 | `bash packaging/windows/build.sh`（需要 `WIX=` 指向 wix.exe） |
| 生成产物清单 | `bash packaging/make_manifest.sh`（脏树会拒绝） |
| 推镜像 | `bash tool/publish_public.sh --push`（HMA 加 `HMA=1`） |
| 切一个 release | `python tool/release.py --version X.Y.Z+NNN`（默认演练，`--apply` 才动） |

**版本号两处**：`pubspec.yaml` 的 `+NNN` 与 `packaging/windows/hollow-court.wxs` 的 `Version`/`ProductCode`。同版本同 ProductCode 在 Windows 上是修复而不是替换，所以两者必须一起动 —— 构建脚本会比对，不一致就拒绝。

---

## 六、HMA 是什么

十个命令，都在 `tool/hma.py`（另外几个 `hma_*.py` 是它的实现）：

| 命令 | 干什么 |
| --- | --- |
| `hma doctor` | 这台机器上有什么 |
| `hma fix` | 只看不动；`--apply` 才真动，而且坏文件只让开不改写 |
| `hma undo` | 把最近一次让开的文件搬回去 |
| `hma status` | 测试、美术、待办计数各是什么状态 |
| `hma models` | 哪几家模型配好了（key 从不打印） |
| `hma ask <家> <话>` | 问一句答一句 |
| `hma agent "<问题>"` | 让 agent 在仓库里查了再答（只读工具） |
| `hma report` | 收一个诊断包 |
| `hma scaffold` | 写一个新命令的骨架 |
| `hma help` | 全部命令 |

扩展住在 `tool/hma_commands/`。**HMA 不装进应用**，它只是这个仓库的维护工具。

---

## 七、文档该读哪一份

| 问题 | 文件 |
| --- | --- |
| 这个应用长什么样、为什么这么做 | `docs/DESIGN.md` |
| 现在有什么没做、为什么没做 | `docs/TODO.md` |
| 维护工具本身怎么用 | `docs/HMA.md`、`docs/HMA-getting-started.md` |
| 怎么测、测什么 | `docs/testing.md` |
| 界面语言与美术的规矩 | `docs/design-language.md`、`docs/art-and-ui-plan.md` |
| 声音轴是什么 | `docs/voice-archetype-notes.md`、`docs/voice-reading-copy.md` |
| 饮品的年代判据 | `docs/drink-eras.md` |
| 依赖与许可 | `docs/licensing.md`、`docs/asset-provenance.md` |
| 系统结构与数据通路 | `docs/architecture.json`（配 `architecture.html`，也有渲染图） |

---

## 八、第一次进来，按这个顺序

1. `docs/architecture.json` 的三张视图 —— 先看形状
2. `lib/domain/events/stock.dart` 的 `StockLedger` —— 再看事实从哪来
3. `lib/ui/theme.dart` 的 `Copy` —— 文案全在一个文件里，改字只需要去那里
4. `flutter test test/domain` —— 规则跑得最快，先确认基线是绿的
5. `bash packaging/build_all.sh` —— 想看到东西，这一步最快

---

*最后更新：2026-10-30。文件计数会随时间变，改结构时顺手核对一次。*

*本轮补进来的三样：平台通道那一节、两条默认打开的适配器、以及对话与条码那几个新文件在清单里的位置。*
