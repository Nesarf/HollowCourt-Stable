# 声音文案 24 件 · 读样

**给 owner 读的。** 三批共 **24 个 `CopyLine` × 3 种声音 = 72 句**，全部已在 `c6cb118` 落地，原句一并列出，好让你看清「重写」不是「加语气词」。

**三种声音**：伊丽莎白（简体中文，`Voice.heiress`）／ツンデレお嬢様（日语，`Voice.heiressJa`）／Yes, Minister（英文，`Voice.minister`）。

**判据的状态**：`voice_facts_test`（改写不许丢事实）、`voice_test`（不许回落到普通文本）、`voice_register_test`（语气）三支探针全绿，`flutter test` 1109 条全过。**测试只能证明「没丢事实、没回落」，证明不了「口气对不对」——那正是要你判的。**

**一个要留意的记号**：`␠` 表示**句尾有一个空格**（`barcodeProblemCheck` 后面要拼校验位数字），三种声音都必须以空格收尾。

**语料的校核**：原句与三种声音**都从 `lib/ui/theme.dart` 的 `Translated` 对象里取**，不是从 `docs/TODO.md` 的对照表抄的（对照表是记录，代码是实现，两者可能脱钩）。那次核对还发现一处：对照表里 `usbCheck` 记的英文原句是「Check the USB connection.」，而**代码里的英文原句是「Check for a cable」**——本稿以代码为准。**另外，第三批那八条的英文原句对照表里没有列（只列了中文），本稿补全了。**

---

## 第一批 · 八件（空状态与「我替你看过了」那一路）

**1. `priceNone`**

- 原句（中）：还没有记过价格。
- 原句（英）：No price recorded yet.
- 伊丽莎白：价钱嘛……你还没告诉过我，所以我也不打算瞎猜。
- ツンデレお嬢様：値段？まだ教えてもらってないんだから、私だって当てずっぽうは言わないわ。
- Yes, Minister：No figure has been supplied, and it would not be appropriate to conjecture one.

**2. `cellarStatsEmpty`**

- 原句（中）：还没有可统计的。
- 原句（英）：Nothing to count yet.
- 伊丽莎白：要统计什么？桌上还什么都没有呢。
- ツンデレお嬢様：集計するものなんて、まだ何も並んでいないわ。
- Yes, Minister：There is at present no material on which a figure could be based.

**3. `cellarConsumptionEmpty`**

- 原句（中）：还没有消耗记录。
- 原句（英）：Nothing has been poured yet.
- 伊丽莎白：一滴都没倒出去过。杯子都还是干的。
- ツンデレお嬢様：まだ一滴も注いでいないの。グラスは乾いたままよ。
- Yes, Minister：No measure has been dispensed, and the record consequently shows nothing.

**4. `cellarShoppingNothing`**

- 原句（中）：计划里的东西架上都有。
- 原句（英）：Everything the plan needs is already on the shelf.
- 伊丽莎白：清单上的东西，我早都备齐了——不用你再吩咐。
- ツンデレお嬢様：リストのものなら、もう全部そろえてあるわ。指示されなくてもね。
- Yes, Minister：The requirements of the plan are, so far as can be established, already met.

**5. `barShelfEmpty`**

- 原句（中）：这层架子还空着。
- 原句（英）：Nothing stands on this shelf yet.
- 伊丽莎白：这一层还空着。摆什么，你自己挑。
- ツンデレお嬢様：この段はまだ空いているわ。何を置くかは、あなたが決めなさい。
- Yes, Minister：The shelf in question is at present unoccupied; the selection is a matter for you.

**6. `integrityClean`**

- 原句（中）：日志干净，没有发现问题。
- 原句（英）：The log is clean. Nothing was found.
- 伊丽莎白：我逐条看过来了——没有一处不对。不必谢我。
- ツンデレお嬢様：一本ずつ見てきたわ。おかしなところは一箇所もない。礼なんていいのよ。
- Yes, Minister：The log has been examined in full and no irregularity has been identified.

**7. `integrityNoLog`**

- 原句（中）：还没有日志可查。
- 原句（英）：There is no log to check yet.
- 伊丽莎白：查什么？你还什么都没记呢。
- ツンデレお嬢様：調べるって言われても、まだ何も記録していないじゃない。
- Yes, Minister：There is at present no record for which an examination could be undertaken.

**8. `bottleEditFailed`**

- 原句（中）：没能记下，再试一次。
- 原句（英）：That could not be recorded. Try again.
- 伊丽莎白：……没写进去。再来一次，这次我盯着。
- ツンデレお嬢様：……書き込めなかったの。もう一度やって。今度は私が見ているから。
- Yes, Minister：The entry was not, on this occasion, recorded. A further attempt would be advisable.

---

## 第二批 · 八件（「出了什么问题」那一族，含全部错误提示）

**9. `integrityFound`**

- 原句（中）：发现了问题，逐条列在下面。
- 原句（英）：Something was found, listed below.
- 伊丽莎白：有几处不对。都写在下面了，别想蒙混过去。
- ツンデレお嬢様：おかしなところがあるわ。下に全部書いてあるから、見てちょうだい。
- Yes, Minister：Certain irregularities have been identified and are set out below.

**10. `barcodeProblemCheck`**（原句句尾带空格）

- 原句（中）：校验位不对，最后一位应为␠
- 原句（英）：Check digit is wrong; the last digit should be␠
- 伊丽莎白：最后一位算错了。应该是␠
- ツンデレお嬢様：最後の一桁が違うわ。正しくは␠
- Yes, Minister：The check digit is not correct. It should read␠

**11. `stockVolumeProblem`**

- 原句（中）：容量要是一个正数。
- 原句（英）：The volume has to be a positive number.
- 伊丽莎白：容量得写个正数——零和负数我不收。
- ツンデレお嬢様：容量は正の数にして。ゼロやマイナスは受け取らないわ。
- Yes, Minister：A positive figure would be required for the volume.

**12. `barPlacedButEmpty`**

- 原句（中）：位置还记着，瓶子已经空了。
- 原句（英）：A position is recorded for a bottle that is empty.
- 伊丽莎白：位置还给你留着，瓶子却空了。等你有新的一瓶，它还在那儿。
- ツンデレお嬢様：場所は残してあるのに、瓶はもう空よ。次のが来たら、そこに戻してあげる。
- Yes, Minister：A position has been retained for a bottle which is no longer there.

**13. `barNothingToPlace`**

- 原句（中）：架上有东西，但还没记下位置。
- 原句（英）：There is stock and none of it has a position.
- 伊丽莎白：东西是有的——就是谁在哪儿，你还没告诉我。
- ツンデレお嬢様：物はあるのよ。ただ、どれがどこにあるか、まだ教えてもらっていないだけ。
- Yes, Minister：Stock is held, although no position has been recorded for it.

**14. `cellarShoppingNoPlans`**

- 原句（中）：还没有计划做的配方。
- 原句（英）：No recipe is on the plan yet.
- 伊丽莎白：你还没挑要做什么。挑一个，缺点儿什么我替你算。
- ツンデレお嬢様：まだ何を作るか決めていないのね。決めたら、足りないものを数えてあげる。
- Yes, Minister：No recipe has as yet been selected for the plan.

**15. `syncLinkNone`**（这一条曾被守卫测试抓过：中日两版把 **LAN** 丢了，`5786c51` 修好）

- 原句（中）：这台机器现在没有局域网地址。
- 原句（英）：This machine has no LAN address right now.
- 伊丽莎白：这台机器现在连地址都没有。先接上网，我再替你找。
- ツンデレお嬢様：この機械、今は住所も持っていないわ。先に繋いでちょうだい。探すのは私がやるから。
- Yes, Minister：This machine is not, at present, in possession of a LAN address.

**16. `syncWaiting`**

- 原句（中）：正在等待对方输入这串码…
- 原句（英）：Waiting for the other device to enter this code…
- 伊丽莎白：在等那边把码敲进去……你念，我看着。
- ツンデレお嬢様：あちらが打ち込むのを待っているわ……読んで、私が見ているから。
- Yes, Minister：We are awaiting the entry of this code on the other device.

---

## 第三批 · 八件（同步那一屏，一个屏一族）

**17. `syncLinkTunnelNote`**（「广播」是事实，三个版本都保住了）

- 原句（中）：隧道里广播过不去，所以两边要靠配对码、或者以前见过面。附近的设备列表会是空的。
- 原句（英）：A broadcast does not cross a tunnel, so the two ends meet by pairing code or by having met before. The nearby list will be empty.
- 伊丽莎白：隧道挡得住广播。两边想见上，只能靠配对码，或者你我本来就认得。所以附近那栏，你不会看到任何东西。
- ツンデレお嬢様：トンネルはブロードキャストを通さないの。だから両端はペアリングコードか、以前に会ったという事実だけが頼りよ。近くの機器の一覧は空になるわ。
- Yes, Minister：A broadcast will not cross a tunnel; the two ends must therefore rely on a pairing code or on a previous acquaintance. The list of nearby devices will be empty.

**18. `syncLinkModeNote`**

- 原句（中）：选了哪一条，就只走哪一条 —— 不会回落到别的链路。
- 原句（英）：The one you choose is the only one used; it does not fall back to another.
- 伊丽莎白：你挑哪一条，我就只走那一条。别的链路我不会替你偷偷试。
- ツンデレお嬢様：選んだ一本だけを使うのよ。他に落ちるなんてことはないわ。
- Yes, Minister：The link selected is the only link used; there is no fallback to another.

**19. `syncConnectRememberedNo`**

- 原句（中）：陌生——这台机器没见过它
- 原句（英）：no -- this machine has never met it
- 伊丽莎白：没见过。这台机器不认识它。
- ツンデレお嬢様：初対面よ。この機械は相手を知らないわ。
- Yes, Minister：Unknown -- no prior acquaintance with this machine is recorded.

**20. `firewallCheck`**

- 原句（中）：检查这台机器能不能被连上
- 原句（英）：Check whether this machine can be reached
- 伊丽莎白：看看外面连不连得进这台机器。
- ツンデレお嬢様：この機械に外から届くかどうか、確かめてみるわ。
- Yes, Minister：Establish whether this machine can be reached.

**21. `firewallRuleLabel`**

- 原句（中）：覆盖这个程序的入站规则
- 原句（英）：Inbound rules covering this program
- 伊丽莎白：管着这个程序的入站规则。
- ツンデレお嬢様：このアプリに効いている受信の規則よ。
- Yes, Minister：Inbound rules applying to this program.

**22. `syncTokenLabel`**

- 原句（中）：自己定令牌（可留空）
- 原句（英）：A token of your own (may be left empty)
- 伊丽莎白：令牌自己写一个（留空也行）。
- ツンデレお嬢様：トークンは自分で決めていいの（空でも構わないわ）。
- Yes, Minister：A token of your own choosing, which may be left empty.

**23. `syncLinkAny`**

- 原句（中）：不限，哪条链路都可以
- 原句（英）：Any link
- 伊丽莎白：哪条链路都行，我不挑。
- ツンデレお嬢様：どの経路でも構わないわ。
- Yes, Minister：No restriction; any link will serve.

**24. `usbCheck`**（**USB** 是事实，三个版本都保住了）

- 原句（中）：检查 USB 连接
- 原句（英）：Check for a cable
- 伊丽莎白：USB 有没有接上，我看一眼。
- ツンデレお嬢様：USB が繋がっているか、見てくるわ。
- Yes, Minister：Check the USB connection.

---

## 读完以后要定的两件事

**一、这 24 件的口气认不认。** 不认就说哪里不对（太嗲／太硬／丢了事实），我改了把三支探针重跑。

**二、剩下那 171 条两到六字的标签要不要也各写三句。** 它们不长到算散文（最长 14 字），例如 `条码（可手动输入）`、`同步时使用的名义`、`先选一味配料。`。**注意第十二节里那条边界**：导航栏标签、按钮、单位与数字属功能区，68px 的栏装不下长标签，**不能被声音改写**——所以这 171 条里有一部分按设计就该保持原样。

**没有第四批可续**：散文池在 2026-09-26 就空了。
