# The licence situation, in one place

Written on 2026-09-30, after the owner put two character pieces into `art/` and asked about the combination.
Every claim below is quoted from the source rather than paraphrased, because the difference between "not for
commercial use" and what PCL actually says is the whole of this page.

## The layers

| What | Licence | Where it is stated |
| --- | --- | --- |
| **The application's code** | **MIT** | `LICENSE` at the repository root |
| **The artwork in `art/`** | **PCL**, where it depicts a Piapro character | `art/LICENSE`, and the credit in 关于空庭 |
| **Flutter's platform hosts** | BSD-3, theirs | `windows/`, `linux/`, `android/**` -- see `docs/asset-provenance.md` |
| **The IBA's names and proportions** | © IBA, cited not redistributed | each file's own `note` under `data/` |

**The split is not a convenience, it is required.** PCL Article 3.4, *"the user may not sublicense to a third
party the rights licensed under this licence"* (「利用者は、当社が本ライセンスで許諾した権利を**第三者に再許諾する
ことはできない**」): a grant under PCL cannot be sublicensed, and MIT's whole purpose is to let a recipient
redistribute and relicense. So the same file cannot carry both, and the boundary has to be drawn per file.

**Article 4.2 is what makes drawing it possible**, *"where the character or its derivative work is incorporated
into another work as an independent element, this licence applies only to that incorporated portion"*
(「当社キャラクターおよびその二次創作物が他の著作物の一部に**独立した一要素として組み込まれた**とき、本ライセンスは
その組み込まれた…部分に限定して適用されます」).

## What PCL permits, quoted

From the licence itself (https://piapro.jp/license/pcl) and the guideline (https://piapro.jp/license/character_guideline).

**Permitted**: create a derivative work, and reproduce / publicly transmit / exhibit / distribute it (Article 3.1).

**The three constraints that bind this project**:

1. **No compensation, under any name, not even for a non-profit use.** Article 3.2(1), *"the user shall not use a
   derivative work of the Company's character for profit, and shall not use it while collecting consideration
   under any name or receiving remuneration, even for a non-profit purpose"*:
   「利用者は、当社キャラクターの二次創作物を**営利目的で利用してはならず**、また**非営利目的であっても、
   あらゆる名目の対価を徴収しまたは報酬を受けて利用してはならないものとします**」.
   *This is the narrowest of the three and the one that changed a screen.* A donation link attached to this
   application would be asking for exactly what this clause forbids; a link to a profile page is not, because
   nothing flows from the work to the author. That is why 关于空庭 (About Hollow Court) says 作者 rather than 支持.
2. **No sublicensing** -- Article 3.4, quoted above.
3. **Credit is to be given** -- Article 3.3, *"shall endeavour to display ... by a reasonable and readily visible
   method"* (「…表示するよう努めるものとします」). The wording is an obligation to endeavour rather than a
   condition, and it is honoured anyway — **and this is the one quotation that is reproduced in full, in the
   licence's own language, because the guideline gives the sentence verbatim and a credit is not ours to word**:

   > この作品は[ピアプロ・キャラクター・ライセンス](https://piapro.jp/license/pcl/summary)に基づいて
   > クリプトン・フューチャー・メディア株式会社のキャラクター「初音ミク」を描いたものです。

**And what is not permitted** -- uses requiring a separate contract (guideline D-2) include *"any use by a
**corporation**, whether for profit or not"* (「(1) **法人**による、営利、非営利の別を問わないあらゆる利用」). A
corporate use of any kind needs a separate contract.

## What this repository does about it

- **`LICENSE`** covers the code, MIT.
- **`art/LICENSE`** states that the artwork there is under PCL, names the character, and repeats the credit.
- **关于空庭 (About Hollow Court)** carries the credit itself, so a reader who never opens the repository still sees it.
- **The three author links are profiles and not payment pages**, and the row is labelled 作者 rather than 支持 --
  the reasoning is in `about_section.dart` beside the constants, where somebody changing them will read it.

## What is deliberately not decided here

**Whether the profile pages themselves carry paid content is not something this repository controls or
inspects.** Article 3.2(1) is about collection; a link to a page is not collection, and what is on that page is
the owner's to keep clean. Written down so that it is a thing to keep rather than a thing nobody thought about.

**This page is not legal advice and is not written by a lawyer.** It quotes sources so that a reader can check
them, which is the most this project can honestly do.
