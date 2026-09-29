# 与《IBA 官方鸡尾酒列表》的交叉核对（2026-09-23）

owner 的指示是：*「除了 IBA 的酒单，你记得从『鸡尾酒列表』取更多东西」*。做下来的结果是三件事：
**名字改对了 83 处、发现了 16 款官方酒我们根本没有、并留下了一份可复用的三语参照表**。

## 一、来源与方法（都可复现）

| 来源 | 用途 | 取法 |
| --- | --- | --- |
| `zh.wikipedia.org/wiki/IBA官方鸡尾酒列表` | **准绳**：官方三分类、每款的中文名 | `?action=raw` 拿维基文本（含 `noteTA` 的地区转换规则），再取 `?variant=zh-hans / zh-hk / zh-tw` 三个渲染版本，按顺序对齐得到**同一款酒的三地写法** |
| `zh.wikipedia.org/wiki/鸡尾酒列表` | 补充英文名与更多酒款 | 同样三个变体，取正文 `.div-col` 区块内的条目（650 条，其中 354 个唯一英文名） |
| `wikidata.org` | 反查只有中文条目的英文名 | `Q96413607` → `VE.N.TO`（「风铎」） |

**这台机器上维基要走代理**（`zh.wikipedia.org` 的 DNS 在本机被指向 `2001::1` 与一个 Twitter 段地址，直连必失败）：
`curl -x http://127.0.0.1:10090`。

抓下来的三语文档存成 `docs/reference/iba-official-wikipedia.json`（**参照用，不进 app 包**；来源与许可写在文件头，
CC BY-SA 4.0；我们只取「名字」这类事实性内容）。

## 二、改掉的 83 处名字（32 款酒）

原则是**分地区**，而不是拿一个「标准答案」盖三遍——那张表是 zh-hant 条目，它的 `zh-Hans` 列常常只是台港
用名的字形转换（`柯梦波丹`、`凤梨可乐达`），直接用会把大陆读者看惯的名字改坏。所以：

* **三地都改**（原名是机器音译或直译，官方/惯用名明显更好）：`大道之王→花花公子`、`卡西诺→赌场`、
  `汉基帕基→翻云覆雨`、`黑风暴→月黑风高`、`裸体与闻名→一脱成名`、`维斯帕→薇丝朋`、`法式75→法式七五`、
  `白兰地克鲁斯塔→白兰地库斯塔`、`坎昌查拉→坎昌恰拉`、`费尔南迪托→斐南迪多`、`玛丽璧克馥→玛丽·毕克馥`、
  `特立尼达酸→千里达沙瓦`、`纽约酸→纽约沙瓦`、`俄罗斯春酒→俄罗斯之春潘趣`、`苦命私生子→痛苦混蛋`、
  `汤米玛格丽特→汤米的玛格丽特`、`辣五十→辛辣五十`、`柠檬滴马天尼→柠檬糖马丁尼`、`法国贩毒网→法兰西集团`、
  `咖啡马天尼`、`约翰可林斯`、`薄荷朱利→薄荷茱利普`
* **只改台港**（大陆用名本来就对）：`大都会 / 柯夢波丹`、`椰林飘香 / 鳳梨可樂達`、`皮斯科酸 / 皮斯可沙瓦`、
  `性感沙滩 / 性感海灘`、`金菲士 / 琴費士`、`莫吉托 / 莫希托`
* **只改一处错字**：`牀笫之間 → 床笫之間`（港繁）、`蒂珀雷裡 → 蒂珀雷里`（台繁，官方三地皆用「里」）
* **`马丁尼` 的两种写法被官方 `noteTA` 证实**：`zh-cn:马天尼 / zh-hk:马天尼 / zh-tw:馬丁尼` ✓ 我们先前
  只把台繁改成 `馬丁尼` 是对的，这次按同一规则处理了 `馬丁尼茲`、`檸檬糖馬天尼`、`咖啡馬天尼` 等

## 三、我们缺的官方酒：**15 款已补、1 款经查证不该补**（2026-09-23 收尾）

**补进库里的 15 款**（名字取本文件的官方三语表、做法文字四语由我们自己写、计量取 IBA）：

| 库里 id | 英文 | 简体 | 类别 |
| --- | --- | --- | --- |
| ibaOldFashioned | Old Fashioned | 古典 | The Unforgettables |
| ibaWhiskeySour | Whiskey Sour | 威士忌沙瓦 | The Unforgettables |
| ibaSazerac | Sazerac | 萨泽拉克 | The Unforgettables |
| ibaSidecar | Sidecar | 边车 | The Unforgettables |
| ibaWhiteLady | White Lady | 白色佳人 | The Unforgettables |
| ibaStinger | Stinger | 毒刺 | The Unforgettables |
| ibaTuxedo | Tuxedo | 燕尾服 | The Unforgettables |
| ibaVieuxCarre | Vieux Carré | 老广场 | The Unforgettables |
| ibaRustyNail | Rusty Nail | 锈钉 | The Unforgettables |
| ibaPlanter's Punch | Planter's Punch | 殖民者潘趣 | The Unforgettables |
| ibaPortoFlip | Porto Flip | 波特菲丽普 | The Unforgettables |
| ibaParadise | Paradise | 天堂 | The Unforgettables |
| ibaRamosGinFizz | Ramos Gin Fizz | 拉莫斯琴费士 | The Unforgettables |
| ibaGoldenDream | Golden Dream | 金色梦幻 | Contemporary Classics |
| ibaYellowBird | Yellow Bird | 黄鸟 | New Era |

另需两种原料：**triple sec**（白橙皮酒）与**通用 brandy**（白兰地）——两者此前都只有近亲条目
（橙味利口酒／橙味力娇酒、苹果白兰地／桃白兰地）。库规模因此 **88 → 103 款**、**187 → 189 种**。

**Barracuda 不加，而且理由本身是个发现。** 本文件第二节那张表把它标成了 ✪（IBA 官方），但那是旧信息：
意大利文维基的条目写着 `|Estromissione = 2024`（2024 年被移出官方名单，引用 AIBM Project 的
*IBA Official Cocktails 2024*），这与另外两条证据一致——`iba-world.com` 上它的页面现在 404，
英文维基条目也不再有官方配方信息框。**所以中文维基那张清单是滞后的**：照它补库会把一款已除名的酒
当成官方酒收进来。这条也说明「交叉核对」不能只比一张表。

## 三之旧、我们当时以为缺的 16 款官方酒

我们的库共 88 款，与官方列表逐条对表（先按英文名、再按中文名匹配）后，**确认缺失 16 款**——其中包括
`Old Fashioned`、`Whiskey Sour`、`Sazerac`、`Sidecar`、`White Lady` 这些最基本的经典：

| 英文 | 简体 | 港繁 | 台繁 |
| --- | --- | --- | --- |
| Old Fashioned | 古典 | 古典 | 古典 |
| Paradise | 天堂 | 天堂 | 天堂 |
| Planter's Punch | 殖民者潘趣 | 殖民者潘趣 | 殖民者潘趣 |
| Porto Flip | 波特菲丽普 | 波特菲麗普 | 波特菲麗普 |
| Ramos Gin Fizz | 拉莫斯琴费士 | 拉莫斯琴費士 | 拉莫斯琴費士 |
| Rusty Nail | 锈钉 | 鏽釘 | 鏽釘 |
| Sazerac | 萨泽拉克 | 薩澤拉克 | 薩澤拉克 |
| Sidecar | 边车 | 邊車 | 邊車 |
| Stinger | 毒刺 | 毒刺 | 毒刺 |
| Tuxedo | 燕尾服 | 燕尾服 | 燕尾服 |
| Vieux Carré | 老广场 | 老廣場 | 老廣場 |
| Whiskey Sour | 威士忌沙瓦 | 威士忌沙瓦 | 威士忌沙瓦 |
| White Lady | 白色佳人 | 白色佳人 | 白色佳人 |
| Golden Dream | 金色梦幻 | 金色夢幻 | 金色夢幻 |
| Barracuda | 梭子鱼 | 梭子魚 | 梭子魚 |
| Yellow Bird | 黄鸟 | 黃鳥 | 黃鳥 |

**补齐它们不是翻译问题，是内容问题**：每一款都要给出计量、技法、杯型、装饰，而 section 14.1 定下的规矩是
**做法文字要我们自己写、不能照搬来源**。所以这件事需要 owner 点头后再单独做一轮，语言资产（名字）已经就位。

反过来，我们库里有若干款**不在这张维基列表上**（`Chartreuse Swizzle`、`Pisco Punch`、`Cardinale`、
`Ve.N.To`、`Sherry Cobbler`、`Don's Special Daiquiri`、`Missionary's Downfall`、`Three Dots and a Dash`、
`IBA Tiki`、`Illegal`、`Gin Basil Smash`、`Grand Margarita`…）——这张维基列表比 IBA 现行清单旧，
两边差异是**双向**的，不是我们漏了或多了。

## 四、本地模型那一轮复核的结论（值得单独记）

用本机 Ollama `qwen3:8b` 把 **88 款酒 + 187 种原料**全部过了一遍「读着自不自然」（每批 6–8 条，共约 260 条），
它标出 **62 条「不自然」**。逐条判过之后——**只有 1 条该采纳**：

* `Rabo de Galo` 我们写成「鸡尾」（葡语意为**公鸡尾**）→ 已改为 **公鸡尾 / 公雞尾** ✓

其余 61 条的分布是：**想把官方名改回我们原先的直译**（`花花公子→大道之王`、`法兰西集团→法国连结`、
`一脱成名→裸体与闻名`）；**与现状相同**（建议「金酒」而库里本就写「金酒」）；**错误**（说 `White grape`
该译「葡萄」、说 `调和陈年朗姆` 该改成它现在的写法）；以及**它把我提示词里的分隔符当成了数据**
（抱怨「去掉多余的斜杠」）。

**这正是我不让模型直接改文件的原因**：8B 档次的模型在「这个中文读着顺不顺」上偶有可取，
在**术语与地区词**上会稳定地给出一个「默认中文」并当作通用答案（earlier: cream/cherry/gram/ounce 三地同词，
与维基的转换表和重定向都冲突）。所以流程固定为：**名字的事实以维基这类可比对的来源为准，模型只当筛查信号**。
