# Hollow Court - design document

> Version: v1.0 (blueprint finalized)
> Date: 2026-09-17
> Status: **design confirmed 2026-09-17; implemented through `v1.0.0-rc.1` on 2026-09-24.** Sections 14.0-14.1
> carry the roadmap and the per-platform acceptance as measured, and `packaging/README.md` keeps the columns
> this document refers to. Where the two disagree, the packaging file is the one that was measured.

---

## 0. Naming

| Level | Chinese | Japanese | English |
| --- | --- | --- | --- |
| **Public-facing copy** | **空庭** | **空庭** (そらにわ) | **Hollow Court** |
| Technical identifier | - | - | `hollow-court` |

- Publicly, always use "空庭 / Hollow Court"; the formal full name serves only as an internal identifier and an easter egg.
- Android package name: `com.nesarf.hollow_court` -- see section 0.2
- Data file extensions: `.court` (single snapshot), `.courtpack` (exchangeable pack)

### 0.1 Stable uses 空庭 and Hollow Court, and nothing else

**The rule above was already written here when the interface broke it.** The
first version of `lib/ui/theme.dart` put the formal full name on the title bar,
and a test was written asserting that it had to be there -- so the copy and the
test were wrong in the same direction and neither caught the other. Where the name is exposed, and what each place says:

| Place | Shows | Why |
| --- | --- | --- |
| Android launcher label | `空庭` | display copy, so the reader's language -- section 12.4 |
| Windows window title | `Hollow Court` | display copy, in the language the rest of that platform's chrome is in |
| Windows `ProductName`, `FileDescription` | `Hollow Court` | what a person sees in a file-properties dialog |
| Linux window and header-bar titles | `Hollow Court` | same |
| `MaterialApp.title` | `空庭 · Hollow Court` | the pair, because Android's task switcher shows one string |
| `pubspec.yaml` name, `InternalName`, `OriginalFilename`, the Dart package | `hollow_court` | **identifiers, not display copy** -- section 12.4's first rule, ASCII and English |
| Formally nowhere | the full name | except this document |

**Localising the launcher label per locale is section 12.4's work and not this
change's.** The label is display copy and will eventually come from the
localization configuration like every other string; today there is one locale and
it is hardcoded, which is the state section 12.4 already describes.

### 0.2 A correction: the package name in this section was wrong

This section has claimed `app.hollowcourt` with `com.nesarf.hollowcourt` as the
alternative since it was written. **The build has always used
`com.nesarf.hollow_court`**, and the device has it installed under that name --
so neither of the two options listed here matched the application.

The implementation is the fact and this document is corrected to it. What the
section was right about is that the choice matters: an Android package name is
the identity an update is checked against, so **changing it after a release
orphans every install**. It is settled now, before there is a release to orphan,
which is the only comfortable time to settle it.

---

## 1. Positioning

**A private digital cellar.** It knows what you have, how much is left, what it is worth, and what you can pour right now.

Comparable applications on the market fall into two camps, each missing half:

| | another source | one source | **Hollow Court** |
| --- | --- | --- | --- |
| Stock management | Yes (Bottle/Shelf/Fridge) | **Entirely absent** | Yes |
| Data ownership | Server-side Firestore, crippled offline | Local plaintext JSON | **Local-first, direct LAN connection** |
| Account and subscription | Required | In-app purchase to unlock | **Not required, all features free** |
| Visuals | Bottle XY coordinates | Liquid colour | **Both** |
| Measurement depth | ABV / sugar / dilution | Uniform ml | Full set + calibratable units |

### 1.1 Goals

1. **Three platforms**: Windows / Linux / Android, from one codebase.
2. **Complete offline**: every core feature works with no network, no degradation.
3. **LAN sharing**: multiple devices on the same network share one cellar, no server, no account.
4. **Precise measurement**: volume and mass interconvert, recipes reverse-solve and scale, garnish and body weighted separately.
5. **Data sovereignty**: the library belongs to the user and can be exported whole as plain text at any time.

### 1.2 Non-goals

- No social network, no recipe community, no cloud account system.
- No e-commerce, no payments, no subscription wall.
- Not aiming to be the largest recipe library -- **aiming to be the one that knows your liquor cabinet best.**

---

## 2. Technology choices

**Framework: Flutter (Dart 3.x)**

The reason is not a default preference but evidence: reverse engineering shows one source (414 recipes, liquid colour rendering, `libapp.so` single-package offline) was delivered with Flutter, proving the framework fits "data-dense + visually fine + consistent across three platforms" applications.

Incidental advantages:

- **`dart:io` ships `HttpServer`**, so the LAN service needs no plugin at all -- the single most critical architectural requirement of this project.
- One codebase covers Windows / Linux / Android, with no platform-branching UI code.
- Strong typing plus compile-time checking, suited to logic like unit conversion where implicit casts are least tolerable.

| Concern | Choice |
| --- | --- |
| State management | Riverpod |
| Local persistence | File append-only event log (`path_provider` for paths), in-memory index |
| LAN service | `dart:io` `HttpServer` + WebSocket |
| Service discovery | `nsd` (Android needs `MulticastLock`) / `multicast_dns` on desktop |
| QR code | `mobile_scanner` (scan) + `qr_flutter` (generate) |
| Android background | `flutter_foreground_task` |
| Packaging | Windows -> WiX MSI - Linux -> AppImage - Android -> APK |

**Why not SQLite:** the data volume is too small. A cellar holds a few hundred SKUs and a few thousand pours a year -- the append-only event log doubles as **storage format, sync format and audit log** in one, eliminating an entire diff layer. Revisit migration at fifty thousand events, and because the log only grows and never mutates, that migration is painless.

---

## 3. Layered architecture

```
| UI layer (Flutter Widgets)                                                     |
| Stock - Bar - Recipes - Cellar                                                 |
| Visualization: liquid colour rendering - shelf bottles                         |
+--------------------------------------------------------------------------------+
| Domain layer (pure Dart, zero Flutter dependency, unit-testable standalone)    |
| Unit conversion - dosage solving - match scoring - CRDT merge - HLC            |
+--------------------------------------------------------------------------------+
| Data layer                                                                     |
| Event log repository - overlay layer merge - seed data loading                 |
+--------------------------------------------------------------------------------+
| Platform layer (dart:io)                                                       |
| LAN service - mDNS broadcast - QR pairing - foreground service                 |
+--------------------------------------------------------------------------------+
| Adapters layer (pluggable, all off by default)                                 |
| Net: DeepSeek - price comparison - barcode                                     |
| Peripheral: Bluetooth scale - external IMU - gamepad                           |
| Render: device capability probing - dynamic tiered degradation                 |
+--------------------------------------------------------------------------------+
| Pro Packs (optional asset packs, **data only, no code**)                       |
| 3D models - PBR textures - calibration parameter tables                        |
| Distributed over LAN or imported locally - core features unaffected when absent|
+--------------------------------------------------------------------------------+
```

Base app package size target: **without Pro assets <= 35 MB**.

**Iron rule: the Domain layer must not import `package:flutter/*`.** It must run its full test suite on a pure Dart VM -- unit conversion errors are the least forgivable defect in this class of application, and also the hardest to catch by clicking around the interface.

---

## 4. Domain model

Naming borrows another source's mature vocabulary (`Reagent` / `Bottle` / `Bar`), but field structure follows this project's requirements.

### 4.1 Ingredient

```
Ingredient {
  id              : String       // juiceLime / ginPlymouth (camelCase prefix scheme)
  name            : String       // display name
  category        : Enum?        // see 4.2; null when nobody has said
  aliases         : [String]
  abvPercent      : Rational?    // alcohol by volume
  sugarGPerL      : Rational?    // sugar g/L
  densityGPerMl   : Rational?    // density, the bridge between volume and mass
  defaultUnit     : Unit?
  bottleSizes     : [Int]        // common bottle sizes (ml)
  // provenance and personalization
  sourceBucket    : Enum?        // the source's own bucket, kept beside category
  extras          : Map<String, String>
}
```

**Rational, not Double.** This listing originally said `Double?` for the three
numbers above, which contradicts section 3 and section 5.1 -- the domain layer
has no floating point, and a density is multiplied into a volume by the
`DensityBridge` of section 5.4, which takes a `Rational`. A `double` arriving
here would have to be converted at exactly the boundary section 2 chose a
strongly typed language to protect. The arithmetic rule wins; it is the one
with a reason attached.

**`category` is nullable, and that is a finding rather than a convenience.**
The another source harvest carries 139 ingredient entries and not one of them has a
category: the taxonomy below was observed from the site, but the
per-ingredient assignment was never captured. Guessing one from the name is
precisely the silent guess the reverse-engineering record forbids, so the field
stays empty and an import reports how many are empty. one source's own bucket is
kept beside it in `sourceBucket` -- the two taxonomies do not line up, and
section 18 is a warning about forcing them to.

### 4.2 Ingredient categories (two layers, taken from another source evidence)

**Alcoholic**: Whisk(e)y - Gin - R(h)um - Tequila & Mezcal - Vodka & Similar - Brandy - Beer & Cider - Wine - Common Liqueurs - Vermouth - Port & Sherry - Aperitifs - Common Amaro - Common Bitters

**Non-alcoholic**: Citrus - Juices - Fruit & Veg - Syrups - Jams & Preserves - Herbs & Spices - Sodas - Pantry Items - Grocery Items - Mock Spirits - **Items You Can Make** (makeable at home) - **The Modern Bar** (preset configurations) - **Top 25 Most Used** (frequency)

### 4.3 StockItem / Bottle

```
Bottle {
  id              : String
  ingredientId    : String
  quantity        : Int          // integer microlitres, see section 5
  openedAt        : DateTime?
  expiresAt       : DateTime?
  // shelf visualization
  shelfId         : String?
  posX, posY      : Double?      // shelf coordinates
  // prices (see section 7)
  purchase        : Purchase?
  priceHistory    : [PricePoint]
  extras          : Map<String, String>
}

Purchase   { price, currency, date, shop, volumeMl }
PricePoint { date, pricePerMl, source: manual|scan|web }
```

### 4.4 Recipe

```
Recipe {
  id              : String       // <slug><5 digits>, same lineage as the existing ecosystem
  name            : String
  subtitle        : String?
  packId          : String?      // content pack
  description     : String?
  origin          : String?      // provenance, e.g. "Travel Finds, Casoni Bar, Italy, 1919"
  flavors         : [Flavor]     // three levels: primary/secondary/tertiary
  glass           : Glass
  ice             : IceKind
  method          : Method       // Stirred / Shaken / Poured / Built / Blended / ...
  methodSteps     : [String]
  liquid          : LiquidVisual // see section 12.1
  items           : [RecipeItem]
  rating          : Double?
  isSeed          : Bool         // seed or user-created
  extras          : Map<String, String>
}

RecipeItem {
  ingredientId    : String
  amount          : Int          // microlitres
  unit            : Unit         // original unit (preserved as-is)
  role            : ItemRole     // base | modifier | garnish | optional
  note            : String?
  substitutes     : [String]
}
```

### 4.5 Other entities

| Entity | Description |
| --- | --- |
| `Bar` | One cellar. Multiple may exist, each shareable separately (equivalent to another source's Bar switching) |
| `Batch` | One pour record: time, recipe, servings, actual amounts, rating, notes. **Consumption originates here** |
| `ShoppingList` | Generated automatically from "what is missing", editable by hand |
| `Device` | A device participating in sync (deviceId, name, last sync HLC) |

---

## 5. Dosage and unit system

**This is where the whole project needs the most care, and where the word "precision" lands.**

### 5.1 Internal base: integer microlitres

**Never use floating point for accumulation.** A recipe is essentially a ratio; after scaling by parts a dozen times, `0.1 + 0.2 != 0.3` becomes a deviation you can see in the glass.

| Physical quantity | Internal base | Description |
| --- | --- | --- |
| Volume | **ul (microlitres, integer)** | 1 oz = 29 573.5 ul |
| Mass | **mg (milligrams, integer)** | |
| Ratio | **fraction (numerator/denominator)** | `1/3 oz` is exactly 1/3, not 0.3333 |

### 5.2 Three tiers of units

| Type | Examples | Handling |
| --- | --- | --- |
| Absolute quantity | ml - cl - oz - tsp - tbsp - drop | Exact constant conversion |
| **Cultural units** | **dash - barspoon - part** | **User-calibratable, never hard-coded** |
| Discrete quantity | leaf - sprig - wheel - twist - peel - cube | Counted, never scaled |

### 5.3 Conversion ambiguities that must be faced

- `1 US fl oz = 29.5735295625 ml`, while `1 UK fl oz = 28.4131 ml` -- a 4% difference, a whole Negroni you can taste apart. **US default.**
- `1 dash` has no international standard. Angostura is about 0.6-0.8 ml, varying with bottle mouth, liquid level and hand pressure.
- `barspoon` is 2.5 ml at a Japanese bar and 5 ml at an American one -- exactly double.

**Countermeasure: make dash and barspoon "calibratable named units".** The user calibrates their own bottle of bitters once with a graduated cylinder and the whole library benefits. The system supplies suggested initial values, but marks them explicitly as estimates rather than facts.

### 5.3.1 A fourth state of matter: counted things, and why it is not a small change

**The question that started this:** *"如果我要计入 1 片柠檬 / 1 根肉桂棒，要怎么选"* -- how does a reader
enter something that is counted rather than measured? The catalogue already has the units (`slice`,
`wheel`, `wedge`, `cube`, `leaf`, `sprig`, `peel`, `twist`, `each`, all `UnitDimension.count`), and
`RecipeItem.count` has carried "how many whole things" since the beginning. **[decision] The owner chose
to add a fourth `MatterState` for counted things, with the count words localised.** It is queued rather
than done, and the reason is worth writing down, because it looks like an enum member and is not:

1. **A count word is language-dependent and every other unit symbol is not.** A millilitre is a
   millilitre everywhere, which is why `Unit.symbol` is a single string and why §12.4 says a unit is not
   translated. `slice` / `each` / `leaf` are English *words*: a Chinese interface that prints `1 slice`
   beside a bottle is not a cosmetic problem, it is the wrong language in the one place this design
   promised a reader would never see one. So the fourth state needs a **per-language symbol table for
   count units** -- a layer that does not exist yet, and it has to arrive with the state rather than
   after it, or the first screen to use it ships the English.
2. **There is no formatter for a count.** `volumeText` and `massText` are the two exits from the base
   units, and a count is neither: it has no base unit, no rounding rule, and nothing to convert. A third
   formatter is needed before anything can be printed.
3. **And there is nowhere to enter one.** The only entry form is 记一瓶 -- a *bottle*, which is a
   container of liquid. A lemon is not a bottle: it has no volume in the cellar, no pour, and no
   consumption curve. So the state, the symbol table and the formatter together still do not make the
   owner's example work; a countable **stock item** is a fourth thing after them.

**What is therefore needed, in order**: the enum member and a locale set per language (small); the
localised count words (a real table, twelve languages); a count formatter (small); and an entry form for
a countable item (not small, and the only part a reader would notice). Doing the first three without the
fourth is the "model ahead of the interface" gap this project has already recorded three times -- a
`massOf` with no caller, a `price.paid` reader with no writer, a `BottleRecounted` nothing wrote -- and
each of those waited for the screen that needed it. This one should too.

### 5.4 Density bridge (volume <-> mass)

Precision pouring uses a scale, not a measuring cup -- volume is affected by temperature and density, mass is not. Each ingredient stores `densityGPerMl`: water 1.000, simple syrup about 1.30, gin about 0.94. Thus "1 oz syrup" can be computed as 38.4 g.

### 5.5 Dilution model

Shaking introduces about 20-25% melt water, stirring about 15-20%, building 0%. Stir a Negroni and 3 oz of spirit is really about 3.5 oz of finished drink. **Skip this step and the ABV is simply wrong.**

### 5.6 Reverse solving

- Scale by parts
- Scale by target finished volume
- Scale by **effective container volume** (200 ml glass - ice displacement = 120 ml usable)
- Scale by **ABV ceiling** (driving tonight)

---

## 6. Stock and consumption

Three verbs: **stock -> mix -> consume**. another source stops at the first step; we walk all three.

```
stock:    enter a bottle -> Bottle created, purchase and priceHistory recorded
mix:      pick a recipe -> solve dosage -> record a Batch
consume:  Batch produces a consume event -> stock decremented -> restock reminders and expiry warnings derived
```

**Key design: stock decrement records an "operation", not a "state".**
When two devices mix drinks at the same time, A consuming 4 oz and B consuming 2 oz, the correct answer is 6 oz. Last-write-wins would silently discard one consumption. This is also the deeper reason section 2 chose an event log -- **the storage format is inherently the sync format**.

---

**Correcting what was recorded, which the first version of this section did not have.** Three of the
operations above existed in the domain from the beginning -- recounted, discarded, removed -- plus a
`price.paid` reader with no writer, and **nothing in the application ever called any of them**: the fold
reduced them, the log parsed them, and a bottle entered wrong stayed wrong. The writers are
`CellarNotifier.renameBottle` / `renameIngredient` / `recountBottle` / `discardBottle` / `recordPrice` /
`removeBottle`, and a long press on a bottle opens the sheet that reaches them.

| Correction | What it writes | Why that and not something else |
| --- | --- | --- |
| This bottle's name | An overlay field, `bottle.<id>.name` | A name is a label, not an event in the cellar's history. The *other* overlay field, `ingredient.<sku>.alias`, is the other half of the same question: one is about this object, one about the vocabulary, and the shelf reads the object first |
| What is left | `BottleRecounted` | A recount is an **observation**, so it replaces the remaining volume rather than adjusting it -- the person read the level off the bottle. The pours before it still stand: a recount says what is left, not what was drunk |
| What it cost | `PricePaid` | A price is a **series** (§7), so a correction is a new point and the old observation stays, dated. A screen that overwrote the last number would destroy the only thing the series is for |
| Poured away | `BottleDiscarded` | Separate from a pour on purpose: both reduce the shelf and only one was a drink |
| The whole line | `BottleRemoved` | **Refused once anything has been poured or discarded against the bottle**, and the refusal is in the writer rather than in the fold. The pour is in the log and the consumption curve counts it; deleting the bottle it came from would leave a drink belonging to nothing. Such a bottle needs a *discard*, and the sheet says so |

---

## 7. Prices and fluctuation

**A price is not a field, it is a time series.** Store only a single `price` and none of the following metrics can be computed:

| Derived metric | Algorithm |
| --- | --- |
| Cost per glass | amount (ul) x current price per ul |
| Total cellar value | sum of volume on hand x current unit price |
| Change | first PricePoint compared against last |
| Consumption curve | Batch history aggregated over time |
| Restock point | consumption rate x purchasing lead time |

Prices have three sources; the first version implements only the first:

1. **Manual entry** (most reliable, first version)
2. Barcode scan + online price comparison (phase two, via adapter)
3. Purchase receipt OCR (long term)

---

## 8. Personalization and overlay layer

**Core principle: the seed layer and the overlay layer are separate.**

The 502 built-in recipes (section 15) and ingredient entries are the **seed**; every user modification is the **overlay layer**. The seed can be updated with new versions and the overlay never gets lost. The event log is inherently an overlay layer -- another dividend of this architecture.

Personalizable dimensions:

- Any entity can carry `extras: Map<String, String>` custom fields
- Tags, notes, photos, ratings
- Custom categories and ordering
- Custom units and conversion factors
- Ingredient aliases ("I call it gin")

### 8.1 The data model, which is a key and two events

**One storage location, and it is the log above.** "The event log is inherently an
overlay layer" is taken literally: an overlay entry is an ordinary event in the same
file, so it has the same clock, the same merge and the same sync as a bottle. A
second file would be a second lifecycle for the same fact, and the two would
disagree about whether a note survives an update; a second cache would be a third.

| | |
| --- | --- |
| The key | `OverlayKey(kind, id, field)`, packed for humans as `kind:id.field` |
| Set | `overlay.field.set` -- the key in three payload fields, and the value |
| Remove | `overlay.field.cleared` -- the key alone |
| The fold | `Overlay.of(events)`: field-level LWW, which is what section 10.4 asks for |

**The key is the whole of the promise, so it is built from ids and never from
content.** A key derived from the seed's contents -- an index, a position, a display
name -- moves when the seed moves, which is precisely the occasion this layer exists
to survive. Section 4.4 already made that promise and made it against this section by
name: `recipe_id.dart` records that a running index "would have been simpler and
wrong: adding a recipe to the source would renumber everything after it, and section
8 keeps user data pointing at recipe ids."

**An id is minted; a name is a value.** That is the rule which lets the key be
validated at all. A user never mints a key: a custom category of their own gets an id
this project assigns, and the words they typed for it are the *value* stored under
that id. So `OverlayKey` refuses a malformed key and throws, while a value is the
user's own text and is never refused. `kind` is an open string rather than an enum,
for the same reason `Event.type` is -- two versions of the app meet during a sync and
the older one has to carry the newer one's entries rather than drop them.

**A removal is an event and not an absence.** A clear that left no trace would be
undone by the next sync, because a peer still holding the older `set` would hand it
straight back. There is no tombstone in the *state*, and that is a decision with a
reason: the fold sorts the whole log by clock and this project merges logs rather
than states, so a clear and an older set are always applied in the order that makes
the clear win. **Compacting the log is what would break that** -- dropping an old set
and the clear that superseded it is safe only while nothing older can still arrive,
and that is a claim about sync rather than about the file.

**An empty value is refused by the builder**, and read as a removal if one arrives
anyway: "set to nothing" and "removed" are the same state to a reader, so allowing
both would leave every screen guessing which one it was looking at. An empty value
written by a build that does not check is surfaced on the fold rather than smoothed
over.

**Built**: the key, the two events, the fold, the write path through
`CellarNotifier`, and one real consumer -- a note on a recipe, keyed by the recipe id
and edited in the Recipes sheet. The other dimensions in the list above are not wired
yet: what exists is the mechanism they will use. One of them already has its key
decided and nothing writing it yet, the string correction in 12.4, which is keyed by
language so that one correction cannot overwrite another.

---

## 9. Match scoring algorithm

Taken from another source's evidence-based design -- **no binary verdict, a weighted score**.

```
MatchScore = sum(weight of available items) / sum(weight of all items)
```

Weights are stratified by `role`:

| role | Weight | Description |
| --- | --- | --- |
| base | 1.0 | The base spirit; without it this is not the drink |
| modifier | 0.8 | Liqueurs, syrups, bitters |
| optional | 0.3 | Can be skipped |
| **garnish** | **scored separately** | **not counted in the main score** |

**Why garnish is scored separately**: a missing orange peel should not drop a Negroni from 100% to "cannot make".

| Main score | Presentation |
| --- | --- |
| >= 95% | **Makeable** (annotated with garnish completeness) |
| 70-94% | Close, missing items listed |
| < 70% | Insufficient ingredients |

Missing items flow automatically into `ShoppingList`.

---

## 10. LAN sync

### 10.1 Topology

**No pure P2P.** We use "switchable star + peer fallback":

- Desktop acts as the resident node by default (plugged in, online, no fuss)
- Android is a follower by default (battery saving), and can be temporarily promoted to host when needed
- When no host is found, any device can start its own service

### 10.2 Three discovery paths (degrading in stages)

1. **mDNS auto-discovery** -- reliable on desktop; Android needs `MulticastLock`, otherwise the system swallows multicast to save power
2. **QR pairing** (primary path)
   ```
   hollowcourt://pair?ip=192.168.1.23&port=7788&tk=<one-time token>
   ```
   The host displays the code and the phone scans it to complete pairing **and** key exchange at once. This sidesteps three pitfalls in one move -- mDNS keepalive, multi-NIC selection, AP isolation -- and finishes authentication along the way.
3. **Offline file exchange** -- export a `.courtpack`, transfer it over any channel, import and merge

### 10.2.0 Why the local network and not Bluetooth, in the owner's own reason

Asked and answered on 2026-09-22, and worth writing down because it decides the shape of everything below:

> 至于为什么我要选择局域网而不是蓝牙，主要是考虑到例如有些大型酒店内会统一布置全楼同源wifi，这时候或许就可以在15楼连上1楼的设备。

**That is a range argument, and it is the right one for this feature.** Bluetooth is a personal-area network:
ten metres, a room, and a pairing ritual per device. A building whose floors share one Wi-Fi network is a
*local* network in the sense that matters -- one broadcast domain -- and a device on the fifteenth floor
can reach one on the first without anybody walking anywhere. Two consequences that are easy to miss:

- **The design has no notion of proximity.** Nothing may assume two devices are near each other, so nothing
  may use signal strength, pairing-by-tap, or "the nearest device". The list is flat: whoever answers is
  equally far away, and a reader chooses by name.
- **The same building-wide network is where client isolation is most likely to be switched on.** A hotel
  that does not want guests' laptops talking to each other is exactly the hotel the owner is describing, so
  the pairing code path (§10.2, path 2) is not a legacy fallback: it is the answer for the network this
  feature was justified by. And a file (§10.2, path 3, `courtpack.dart`) needs no network at all.

### 10.2.0.1 And it must not go through a proxy, in any mode

The other requirement from the same message: *"记得实现同步工作不被代理影响（即便代理使用全局模式）"*.

**It holds by construction, and a test keeps it that way.** The sync path opens raw TCP and UDP sockets
through `dart:io`. A `Socket` has no concept of a proxy, nothing on the path reads `http_proxy` or
`https_proxy`, and no HTTP client is involved at any point -- so an HTTP proxy, including one in
system-wide global mode, cannot intercept a connection it is never asked to make. Two devices on the same
network by definition have no business sending their traffic out to a proxy and back.

`test/data/sync/no_proxy_test.dart` fails if any file on the sync path so much as mentions `HttpClient`,
`findProxy`, `http_proxy`, `https_proxy` or `package:http`. The property is easy to lose by accident -- one
convenience call, one dependency added for an unrelated feature -- and a comment would not survive a year.

**What this does not cover, said plainly.** A tool that captures the *routing table* rather than the HTTP
layer -- a VPN, or a proxy in TUN mode -- works below the socket API, and no choice in this application
prevents it. Two things mitigate it and neither is a guarantee: the sync listener binds to the LAN address
rather than to every interface (`listenForLanSync`), so the traffic has a definite route rather than one the
operating system picks; and **the discovery screen has to say what to check when nothing is found**,
because "the building's Wi-Fi and a VPN are on at once" is a failure a reader can act on while an empty list
is not. That sentence is part of stage 5 below and is not optional.

### 10.2.0.2 It is a closed network, and that is the point

The owner's own framing, and it is the sharpest description of this feature anyone has given:

> 其实说起来，这个功能算是传统意义上的VPN了，因为并不和外界互联网交互，类似医院内网的感觉（笑）

**A traditional VPN in the literal sense: a private network, not a tunnel to somewhere else.** Not "we are
careful about the internet" but *there is no internet in this path at all*. Nothing here has a server, an
account, a relay, a rendezvous point or a name service -- two devices that share a network talk to each
other, and that is the entire mechanism. Section 10.3's transport was built that way without this sentence
to justify it (a code and a key, no third party), and the sentence makes it a property to hold rather than
a consequence to enjoy.

What that buys, all of it testable:

| Property | Why it matters here |
| --- | --- |
| **A network with no route out still syncs** | a hospital intranet, an air-gapped switch, a guest network behind a captive portal that has not been accepted yet. Two 空庭 devices on such a network are exactly the case this feature exists for |
| **No name service is consulted** | `Socket.connect` resolves a hostname, so the transport parses the ticket's host with `InternetAddress.tryParse` and refuses anything that is not an address (`test/data/sync/socket_transport_test.dart`). A name would mean a resolver, and a resolver means the outside world |
| **No HTTP client is on the path** | so no proxy setting, in any mode, is even consulted -- `test/data/sync/no_proxy_test.dart` holds both this and the refusal above in place |
| **Nothing is announced to anybody who is not on the network** | the announcement is a UDP broadcast on the local subnet. It does not leave the link, which is a stronger statement than "we do not send it anywhere" |

**And the honest limits of "closed", because a hospital is also the example that shows them.**

- **A broadcast reaches one subnet.** A building whose floors are on separate VLANs is a building where
  discovery finds nobody, even though every device is one building away. The pairing code and the
  `courtpack` file are the answers; this is the same limitation §10.2 has always recorded, and the
  hospital example makes it concrete rather than theoretical.
- **Client isolation is most likely exactly where this feature is most wanted** -- a hotel that does not want
  guests' laptops talking to each other. Same two answers.
- **A device that captures the routing table (VPN, TUN-mode proxy) sits below all of this** and cannot be
  prevented from this side; §10.2.0.1 says what is done about it and what is not promised.

### 10.2.0.3 Wired, bridged, and over a real VPN

Asked for on 2026-09-22: *"记得做有线网络间的同步适配，也就是没有无线网络的时候，有网线接口的设备可以直接有线连接，且允许通过硬件网桥，也就是正儿八经的VPN"*.

Three arrangements, and they are not the same problem:

| Arrangement | What the network looks like | What has to change here |
| --- | --- | --- |
| **Two devices, one cable, no router** | each side agrees on a **link-local** address (`169.254.x.x`), because nothing answered a DHCP request | link-local addresses must be *advertised*, and must not be treated as unreachable |
| **Through a hardware bridge or a switch** | one broadcast domain, transparent at layer 2 | nothing: broadcast and unicast work as they do on any LAN |
| **A real VPN** (WireGuard, an overlay, a site-to-site tunnel) | a **routed** virtual network: each device has an address on it, and there is no broadcast domain across it | the interface must be selectable, and discovery cannot be relied on |

**The first row was a bug of ours, found by that sentence.** `chooseLanAddress` dropped `169.254.` along
with `127.`, and `looksReachableFromAnotherDevice` called it unreachable -- which would have made a direct
cable connection impossible *while looking like it worked*: the ticket would have named some other address
that the device on the other end of the wire had never heard of. Link-local is now a candidate, and one of
the two tests that asserted the opposite now asserts this instead, with the reason attached.

**The third row is where the ranking stops being enough, and the study already said so.** Red Alert 2 kept
`NetCard=0` beside its ports for the same reason: a machine with Wi-Fi, an Ethernet port, a container bridge
and a VPN adapter has several addresses, the automatic answer is right most of the time, and the times it is
wrong are exactly the times somebody deliberately plugged something in. So the score becomes a *default* and
`rankedLanCandidates` hands the reader the list -- `Wi-Fi 192.168.31.157`, `Ethernet 169.254.10.20`,
`Tailscale 100.101.102.103` -- because two bare addresses are a puzzle and two labelled interfaces are a
decision. The rule the ranking follows is stated once, in `lan_address.dart`:

> The ranking answers *"which address would a device I have arranged nothing with be able to reach?"* A
> private LAN address wins, because that is the network the whole building shares. Everything else is a
> **deliberate arrangement**, and a deliberate arrangement is a choice rather than a default.

**And the honest limit of the VPN case, which no amount of ranking fixes**: a broadcast does not cross a
router, so a tunnel has no broadcast domain and **discovery will find nobody across one**. Two devices on a
VPN sync by *address* -- the pairing code, or a device this one has met before -- which is precisely what
the code and the remembered key are for. The discovery screen has to say so rather than showing an empty
list, because "there is nobody here" and "there is somebody here and this network is the wrong shape to
shout in" are different sentences and only one of them is actionable.

### 10.2.0.4 Three modes, which cannot be used at once

The owner's design, in two messages:

> 把有线和无线分成两种模式（不可同时选择），有线模式下无法使用无线网络进行同步，反之亦然
>
> 而安卓端可以使用usb——所以干脆统一再加一个USB连接模式算了

**A mode rather than a list of adapters, and the difference is what the setting promises.** A list says
"prefer this one"; a mode says **"only this kind, and the other kinds are not a fallback"**. That is the
stronger and more useful statement for the case this feature exists for: on a cabled hospital intranet,
有线 has to mean that nothing leaves through the building's Wi-Fi, and a mode that quietly fell back when the
cable came out would be a promise kept only until it mattered.

| Mode | What it is | What it looks like |
| --- | --- | --- |
| **有线 `wired`** | copper or fibre: `Ethernet`, `以太网`, `eth0`, `enp3s0` | a cable between two machines gives **link-local** addresses (§10.2.0.3) |
| **无线 `wireless`** | radio: `Wi-Fi`, `WLAN`, `wlan0`, `wlp2s0` | the building's network, one broadcast domain, the case a hotel's shared SSID makes useful |
| **USB `usb`** | **a network over a USB cable**, which on Android is USB tethering: `rndis0`, `usb0` | the link exists only while that cable is in that device, and its address is the phone's to hand out (`192.168.42.x`) |

**The third one earns its place, and the classification had to change for it.** `usb0`/`rndis0` were
initially classified as *wired* -- physically true and operationally wrong: on a phone, choosing 有线 would
then silently mean "tethering", and a device can have both a tether and an Ethernet adapter with no way to
tell them apart by address. So USB is matched before wired, and the tests that asserted the old answer now
assert the new one with the reason attached.

**Exclusion is total, and the honest consequence is on screen.** An interface that is none of the three --
a container bridge, a VPN overlay, a name from a platform nobody has taught the classifier yet -- belongs to
**no** mode; it is not promoted into whichever mode happens to be selected. And **a mode with nothing in it
finds nothing and syncs nothing**: a reader who chose 有线 with no cable plugged in is told that, rather than
being quietly served by the radio. Two sentences, not one, because "no cable" and "no wireless" send a person
to two different places.

**One question this leaves open, and it is not being decided silently: where does a routed VPN go?** A
tunnel is none of the three -- it is not a cable, not a radio, and not a USB link, and nothing in `dart:io`
says which of them it rides over. The owner asked for VPN support on 2026-09-22 (10.2.0.3) and for three
modes in the same conversation, and those two requests do not yet meet. The options, none of them taken
yet: a fourth mode **隧道**; a separate "允许经由隧道" switch beside the mode; or tunnels excluded by
decision, with the pairing code and the pack file (which need no discovery) as the way to sync across one.
Until the owner says which, a tunnel interface is classified as none of the three, which is the option that
**silently does nothing rather than silently doing something**.

### 10.2.0.5 The USB cable carries IP two different ways, and the second one needs a tool

Asked and answered on 2026-09-22: the tunnel question went to a fourth mode (§10.2.0.4), and the USB
question became *"另外也做 ADB 端口转发"* -- so 有线/无线/**USB**/**隧道** are the four modes, and the USB one
has two carriers underneath it.

| Carrier | What it is | What the reader needs |
| --- | --- | --- |
| **USB tethering (RNDIS)** | the phone shares its network over the cable; both ends get real addresses on one segment (`192.168.42.x` on Android's side) | nothing but the cable and the tethering toggle. **This is the ordinary path**, and it needs no new mechanism: it is discovery and an exchange over an interface, like every other mode |
| **ADB port forwarding** | `adb` carries TCP over the *debug* link: `adb -s <serial> forward tcp:<pcPort> tcp:<phonePort>` makes this machine's loopback reach the phone's listener | USB debugging enabled on the phone, the trust prompt accepted, and **`adb` installed on this machine** |

**The second carrier is a different shape of discovery, and that is the honest cost of asking for it.**
There is no broadcast over a debug link, so there is nothing to shout at: the roster for this carrier is
**`adb devices`** -- serial and model, with the phone hosting and this machine connecting to `127.0.0.1`.
It is a list of the devices *attached to this computer*, which is a plainer idea than a network and a much
narrower one.

**Two consequences that have to be built, not just noted:**

- **The hosting screen's loopback warning must be mode-aware.** `looksReachableFromAnotherDevice` returns
  false for `127.0.0.1`, which is right for a network host and exactly wrong here: over an ADB forward,
  loopback *is* the route. The warning becomes a property of the mode rather than of the address.
- **A carrier that spawns `adb` is desktop-only.** The phone side needs nothing new (it hosts and shows a
  code like always); the machine side runs a subprocess. So the USB mode offers tethering everywhere and
  adb only where there is a desktop to run it -- stated on screen rather than offered and failing.

**And the authentication does not move, which is the part that matters.** `adb` is a transport: it carries
IP, and it is not trusted for anything else. The exchange still runs through the sealed handshake of
§10.3 -- the pairing code, or a key learned earlier -- so a hostile process on the debug link cannot
impersonate a device, and the mode a reader chose never changes who is allowed in. This is the same split
the study found in the old games and the same one §10.2.0.1 relies on: the transport carries, the key
decides.

### 10.2.2 The rework: manual search, automatic recognition, request and approval

The owner restated this on 2026-09-22 with a concrete scene: five devices on one network -- this machine
as `NesarfDX`, a phone as `Nesarf's World`, and C, D and E -- every one of them running 空庭, and what
they want from each other is to be *found*, *recognised*, *asked* and *answered*. The reference they named
is the LAN multiplayer of two 1999-era games, studied in `an earlier survey`; what that study
found and what each finding became:

| What the old games did | Evidence | What 空庭 does |
| --- | --- | --- |
| Broadcast session enumeration, no address typed anywhere | AoE2 ships `Dplay60a.exe` (DirectPlay 6.0a) and an IPX package, because enumeration *is* a subnet broadcast | a UDP probe on a fixed port, answered immediately; the list fills in a round trip |
| A fixed base port and a pool for the rest | RA2: `PortBase=1279`, `PortPool=21263` | the discovery port is fixed so everybody knows where to shout; each device's **listener** port is ephemeral and is carried *in* the announcement |
| A table of fixed slots, each of which may be empty | RA2: `Slot01..07 = 2,-2,-2`, `-2` being a free slot | the roster is a fixed-shaped table with expiry, and a pending request occupies a visible row |
| The name is the identity | RA2: `Handle=66,61,6e,62,69,6` -- "fanbi" as bytes | a name **plus a key fingerprint**: two devices may share a name, and the fingerprint is what recognises one |
| An explicit adapter choice, because the automatic one is sometimes wrong | RA2: `NetCard=0` | `lanAddress()` ranks candidates (it once took whatever came first, and on a machine with WSL and a VPN that is a coin toss); the chosen address is shown, not hidden |
| The payload is encrypted, the announcement is not | RA2 ships `Blowfish.dll` | the announcement is a **claim** and is trusted for nothing; the exchange goes through the sealed channel (§10.3) |

**The flow, and which half is manual.**

1. **Search is started by hand.** A button opens a discovery window; nothing is announced, probed or
   listened for while it is closed. *"发现设备必须是手动启动的"* -- and the reason is not only battery: a
   device that announces itself all day can be found all day, and "nobody can see me unless I am looking"
   is the right default for an application about what somebody has in the cupboard.
2. **Recognition is automatic.** Every reply carries a name, a fingerprint and a port. A fingerprint that
   is already in the store of paired devices makes that row a **paired** device with nothing pressed --
   *"识别设备必须要自动化"*, and `DeviceRoster` orders the paired ones first for that reason.
3. **The device is chosen by hand**, from that list.
4. **A request is sent, and the sender waits.** The request names the asker and **exactly what is being
   asked for**: `SyncKind`s, by default `{stock}` -- the cellar list. *"默认只同步酒单，可在设置选择想要同步什么"*.
5. **The far side approves or refuses.** Approval is approval of *that list of kinds*, shown before it is
   pressed, not a blank cheque; a refusal carries a reason and travels back the same way. Only then does the
   exchange run.

**"酒单" was read as the cellar list, and the owner settled it on 2026-09-22.** The log holds exactly three
families of event -- `stock.bottle.*`, `price.paid`, `overlay.*` -- and **a recipe is not one of them**: the
drink list is shipped data (§15), identical on every install, so there is nothing of a recipe to send, and a
kind called `recipes` would be a switch that moves nothing. The reading is confirmed by what the owner did
next: when the harvested data was deleted and the first-party list was written, the *list* became a file that
ships with the application (`data/drinks/library.json`) while everything a reader changes -- stock, prices,
notes, plans, the shelf, the dictionary of equivalent names -- stayed in the log. **酒单 is the cellar, and the
drink list is not syncable because it is the same on both devices by construction.**

**Staged, because it is four things and not one.**

| Stage | What | State |
| --- | --- | --- |
| 1 | `discovery.dart`: the announcement codec, the probe, and the roster with expiry and identity keying | **built**, 13 tests |
| 2 | `SyncKind` and content scoping, composing with the shelf axis; `{stock}` as the default | **built**, 7 tests |
| 3 | the UDP socket: announce, listen, expire, and the list on the screen | **built** on 2026-09-22: `data/sync/discovery_socket.dart` (6 tests, two of which open real sockets), `ui/discovery_providers.dart`, and the nearby list in `ui/sync_section.dart` (3 widget tests). **What is missing is the two-machine run**, which is what `tool/sync_probe.dart` did for the sync itself and where three end-to-end bugs were found -- and a **firewall rule for UDP 48124**, because Windows blocks inbound UDP by default |
| 4 | the request/approve frames over the sealed channel, carrying the kinds; refusal reasons | **not built as frames.** The scope is carried (a share sends what its scope allows, §10.3) and the host's agreement is the act of hosting; an explicit request/approve exchange with refusal reasons is still this row's work |
| 5 | the screen: 搜索设备 → 选设备 → 请求 → 等待对方同意 → 结果, replacing the pairing-code flow as the primary path while **keeping the code** as the fallback for networks with client isolation | **half built**: the nearby list and tap-to-reconnect are on the screen; the code remains the first path rather than the fallback, and the six-digit comparison that would replace it is still the owner's open question (10.2.1) |

### 10.2.1 Discovery by name: built (the owner asked for it on 2026-09-22)

*"每一个设备都有自己的名称，所以可以类似蓝牙发现他人设备的原理，通过局域网发现其他设备并建立连接。"*
That is path 1 above, and **it is much cheaper now than when this section was written**, because four
things it needs did not exist then and do now: a long-term key and a fingerprint per device
(`device_identity.dart`), a store of devices met before with their name, address and key
(`identity_store.dart`), a **code-less reconnect proved on two physical devices**, and a host that
accepts a remembered key in place of the code it is showing (`acceptedIdentities`). Put together with a
discovery mechanism they produce exactly the experience asked for: **see the devices nearby by name, tap
one, sync.**

**How, and why not mDNS.** A UDP broadcast to the subnet's broadcast address on a fixed port, carrying one
small JSON line -- protocol version, name, fingerprint, listening port -- repeated every few seconds, with
each device keeping a table and expiring entries it has not heard from. Broadcast rather than multicast
because Android needs a `MulticastLock` for multicast and its power management swallows multicast without
one, while a plain broadcast generally needs neither; and because it is twenty lines of `dart:io` rather
than a plugin whose lifecycle has to be reasoned about on three platforms.

**Security, and the one sentence that must not be got wrong: an announcement is a claim, not an
identity.** Anybody on the network can announce any name, so what the list shows is a name and a short
fingerprint, and nothing is trusted on the strength of it. A device whose fingerprint is one we already
have is shown as remembered, and tapping it connects **with the key learned earlier** -- the handshake
still has to prove it, and the announce merely saves typing. A device that is new still needs a code, or
better, the Bluetooth-shaped alternative: both screens show **the same six digits** and a person compares
them and presses confirm, which needs no typing at all and defeats the man-in-the-middle that a bare
announce cannot.

**What stays.** The pairing code remains the path that always works, because a great many routers and
guest networks enable client isolation, and on those the broadcast never arrives -- the same reason this
section has always given for the code, unchanged.

**What is built, as of 2026-09-22.** The announcement and the roster in `domain/sync/discovery.dart`, the
socket in `data/sync/discovery_socket.dart`, the lifecycle in `ui/discovery_providers.dart`, and the list on
the sync screen above the code entry -- because this section makes discovery the pleasant path and the code
the one that always works, and a screen that put twelve characters of typing first would teach the wrong one.
A remembered device is labelled and one tap reconnects it through the path that already existed; a stranger is
labelled as new and its tap puts the cursor in the code field.

**The first of the two decisions is taken: discovery belongs to the screen.** [decision] It opens when the
sync screen is watched and closes when it stops being watched. Announcing always would buy a device that is
discoverable while nobody is looking, and on Android a **foreground service** to keep announcing after the
screen sleeps -- a standing notification and a permission conversation for a feature nobody asked to run in
the background. 10.2.0.1's rule applies here too: a mode is a promise, and "while this screen is open, your
devices can find each other" is one that can be kept without a service.

**The second is still the owner's**: whether a new device pairs by code or by the six-digit comparison, since
the comparison needs a screen on both sides and is the better experience, while the code is already built and
tested and is the only thing that works on a network with client isolation.

**Three facts found while building it, recorded here so they are not rediscovered.** The announcement channel
is its own port (**48124**; the sync probes use 48123), and **Windows Firewall blocks inbound UDP by default**,
so a device that cannot be seen needs a rule for that port before anything is wrong with the code. **Two
instances on one machine cannot share the announcement port on Windows** -- a UDP port bound twice with
`reuseAddress` delivers each datagram to one socket only -- which is why the socket takes a separate send port
for tests and why production passes nothing. And the broadcast reaches **one subnet**, which is the honest
limit this section has always stated: child isolation or a router in between and the code is the path.

> **Paths 2 and 3 are not nice-to-haves, they are necessities**: a great many routers and guest networks enable client isolation by default, and then P2P simply does not work.

### 10.3 Security

**The LAN must be assumed untrusted** -- the same Wi-Fi may be a cafe, a dormitory, a company.

- First configuration must be confirmed by an explicit QR scan or PIN
- Long-term keys are exchanged during pairing; requests carry HMAC signatures thereafter
- Payloads are encrypted at the transport layer, never sent bare
- Sharing can be scoped to exactly "which Bar", not the whole library

**WHAT IS BUILT, AND IN WHAT FORM.** The list above was written as a plan and was, for a long time,
almost entirely a plan: the code had the first bullet and a plain TCP socket, while the first frame of
an exchange carries a clock digest -- a summary of everything in the cellar. `secure_channel.dart` now
runs a handshake before anything else:

| Promise | State |
| --- | --- |
| Confirmed by QR or PIN | **Built, as a typed code.** Six characters from `Random.secure()`, shown on one screen and typed into the other. A camera is platform code and is not built; `PairingTicket` is a string that can be read aloud, which is what a guest network with client isolation needs anyway |
| Long-term keys exchanged during pairing | **Built.** Each device has one X25519 key that outlives every connection (`device_identity.dart`), offered during the handshake and learned by the peer. The first meeting is authenticated by the code; every meeting after is authenticated by the remembered key, which is what removes the human from the second sync |
| HMAC signatures thereafter | **Built as an AEAD tag per frame**, which is stronger than a MAC over a plaintext frame rather than a substitute for it: the tag covers the ciphertext, so the payload is neither readable nor modifiable. The handshake itself uses a plain HMAC, because it has to authenticate before there is a key to seal with |
| Payloads encrypted at the transport layer | **Built.** Two AES-256-GCM keys derived through HKDF from an ephemeral X25519 exchange and a hash of the handshake transcript -- one key per direction, so no nonce is reused across directions. Frames are counted, and a frame that is out of order, repeated or modified is refused rather than reassembled |
| Sharing scoped to "which Bar" | **Built**, as a filter over events (`domain/sync/scope.dart`). A share of shelf S carries: every placement on S; every stock operation for a bottle that has **ever** stood on S; every price observation for the ingredients those bottles are of; and overlay names about those bottles or ingredients. Recipe notes never travel. The rule is a whitelist, so an event type added later is *not* shared until somebody decides it belongs -- the failure that leaks nothing. The chooser appears in the sync screen **only when there is more than one shelf**, because a control whose two options do nothing is the furniture 12.3 already refuses |

**What the key is not.** There is no account, no server and no signature authority: a key means "the
same device as last time" to the one device that learned it, and the private half sits in this
application's support directory -- the same trust boundary as the cellar log. That is the honest
limit, and it is written in `device_identity.dart` rather than left for a security section to imply
otherwise.

### 10.3.1 分享码：十八位以内，令牌由人自定（the owner 2026-09-23）

**决定来自这样一句话**：*「把手动输入的东西改成可自定义的分享码，最长为 18 位，但是不需要手动输入码的连接方式
所需要的依赖条件不变」*。落成的东西是 `PairingTicket.shareCode()` 与 `ShareCode`（`lib/domain/sync/pairing.dart`）：

```
A7K3M9XQ2P RNDK7M           十位地址与端口，接上你选的令牌
└────┬────┘ └──┬──┘
  50 bit     6–8 位
```

- **地址仍留在码里**，所以「只有配对码能走」的那几种场合一个都没丢：广播过不去的网段、把客户端隔开的酒店 AP、
  以及地址是 `127.0.0.1` 的 USB / `adb forward`。若把地址交给发现去解析，这些场合就会跟着变成「必须同一个局域网」，
  而那正是这次要求「依赖条件不变」要防的事。
- **十位 = 50 bit**：两位格式版本 + 四字节 IPv4 + 两字节端口。多出来的两位给了版本号——写在纸上的码，其
  格式是最不能事后更改的东西。
- **整串十六到十八位**，令牌六到八位：八位是十八位上限里能塞下的最大值，**而且比这个项目一直在生成的六位更强**，
  所以码变短并不等于安全性下降。
- **字母表沿用令牌那一套**（无 `I`、`O`、`0`、`1`），三十一个（实为三十二个）符号能被口头念对、被手抄对；
  三十二正好整除成 5 bit，这也是十位能装 50 bit 的原因。

**令牌由人自选带来的代价，写在界面上而不是只写在代码里**：一串码里唯一的秘密就是令牌，太短就等于让别人也能完成
第一次见面。所以 `ShareCode` 定了下限六位（就是此前生成器的强度）与上限八位，并把理由作为一句「代价」显示在输入框下。

**两条都留着。** 短码是现在输入框要的形状；长 URI 仍在宿主屏幕上、以小字附在短码下面，因为它是 `syncEditHostHint`
所说的「地址可以手改」的唯一形式，也是 IPv6 主机（`shareCode()` 对非 IPv4 返回 null）的唯一形式。

**发现只报告、不发起，这是设计而不是缺陷**（`sync_section.dart` 里陌生的被点中时调用的就是 `onNeedCode()`）：
发现告诉你谁在场，而把陌生人变成「记得的设备」仍要经过握手认证——要么码，要么两块屏幕对数字。

### 10.3.2 两条待做：点名字即发起连接、防火墙识别辅助（the owner 2026-09-23）

**这两条是同一个痛点的两半：让局域网连接既「通」又「短」。** ① 的实测（`packaging/README.md`）同时暴露了它们：
短码解析分毫不差，卡点**纯粹在防火墙**，而那一卡就卡住了整条流程。

**一、点「附近的设备」里的一台设备，应当直接发送连接请求。** 现在的行为是：陌生设备被点中只调用
`onNeedCode()`，把光标送进配对码输入框（`sync_section.dart` 里那句注释写着「陌生设备只有码这一条路」）。
要改成**点名字即发起**，则陌生人的认证必须由**两块屏幕对数字**承担——这与 10.3 的结论一致：六位数字
「是两者中更强的那个」，因为它绑定的是一次握手的记录，而中继转发得了码、做不出两份相同记录。
**仍然成立的边界**：发现只报告、不配对，这一点不变；变的是「报告之后能做什么」。

**[decision] 点中之后要有一步确认，而且确认框里要带上对方更多的信息（the owner 2026-09-23）。**
两步之间不省：点名字是「我想连它」，确认框是「我看清它是不是它」。

框内应当给到的信息，都取自发现公告里已有的字段，不额外承诺任何东西：

| 框内 | 取自 | 为什么值得放在这里 |
| --- | --- | --- |
| 对方的**名字** | 公告的 name | 名字只是自称（10.2.0.3 的原话），所以它旁边必须有别的东西 |
| **地址与端口** | 公告的 address/port | 「我要连的是这台机器」的最直接事实 |
| **指纹**（完整或分组） | 公告的 fingerprint | 唯一无法自称的东西；与「已记住」比对就看它 |
| **是否已记住** | 与 `trusted` 按指纹比对 | 已记住＝免码重连；陌生＝接下来要对数字 |
| **接下来会发生什么** | 由上面一行决定 | 让读者知道按下之后是「直接同步」还是「两块屏幕对数字」 |

**这也回答了「会不会误触」**：确认框把「一个指纹」摆到读者眼前，而误触的代价在远程是一个弹窗——
所以宁可多这一步。

**二、防火墙识别辅助，因为「太容易卡」。** 今天的实际体验是：真正有问题的机器（宿主）一言不发，而**手机侧**只报
`could not reach …: 10838 — Connection timed out (errno = 110)`。所以要在宿主侧自查并把话说出来：

- **自查入站是否可达**（本机监听是否绑在局域网地址、该地址是否被防火墙放行、网络配置文件是 Private 还是 Public）；
- **把结论用一句话说出**（例如「入站被防火墙挡住了」），而不是让对端去猜一个超时；
- **给出可直接执行/复制的放行方式**，并且是**程序级**而不是端口级——因为监听端口是动态的（这次是 10838），端口规则每会话都要重来。放行时 `-Profile` 必须覆盖本机真实类别（这台 WLAN 是 **Public**，我先前给的 `-Profile Private` 因此完全不生效，这是一次教训）。

**顺序**：先做第一条（它是用户每天都碰到的路径），第二条与它配套——因为「点名字即发起」若被防火墙挡住，
用户看到的仍然是超时而不是原因。

**两条都做完了（2026-09-23，1.0.0.516）。** 做完之后回头看，第一条真正的前提不是那个确认框，而是下面这件事：

**[缺陷，也是这一条的前提] 公告里的端口是一个没人绑定的常量。** `discovery_providers.dart` 过去把
`defaultDiscoveryPort + 1`（48125）放进公告，而同步监听一直是**动态端口**（① 的实测那次是 10838）。也就是说：
公告说「到 48125 来找我」，而 48125 上没有任何 socket——**「点名字即发起」在过去是不可能通的**，与确认框无关。
现在这条链是三段，缺一段都不通：

1. **屏幕打开 = 这台机器可以被点到。** `SyncSection` 在建立时调用 `SyncController.openForRequests()`，
   在局域网地址上绑一个监听（`SyncService.openForRequests`，端口由系统分配），并把**真实端口**发布到
   `reachablePortProvider`；
2. **公告携带的就是这个端口**，不再有常量；拿不到端口就**不公告**（看不见比看得见却连不上诚实）；
3. **应答方拿着比对闸门接客**（`awaitRequest`）。应答方没有码可以要求——它没在显示任何东西——所以一个
   「什么也没证明」的邻居过去会在**握手阶段**被拒（`secure_channel.dart` 里那句「那不是这台机器记得的设备，
   而且没有给码」），而六位数字**正是在这次握手之后**才算得出来：拒在那里，就等于让两种加设备方式里更强的
   那种永远用不了。所以 `allowUnprovedPeer` 由**闸门本身**推导（`runExchange` 里 `confirmComparison != null`），
   而不是由调用方另外声明一个开关——两者不可能对不上。**没有闸门时行为完全不变**，未证明的邻居照旧被拒。

**两条边界，都在代码里写着理由：** 已记住的设备**不再对数字**（它证明了上次学到的密钥，`handshakeProvedByKey`）——
而这一点与 host 侧同一条规则；点名字时用的地址是**公告里的新地址**（端口每次都不一样），不是 `trusted` 里那条
上次的旧地址。

**② 的形状是「三种事实 → 一句话 → 一条可复制的命令」。** `domain/sync/firewall.dart` 只吃文本、不碰进程，
`data/sync/firewall_probe.dart` 只跑一次 PowerShell（两条 `key=value` 行），`HostFirewallRow` 把它画成一行字。
结论只有五种：可达、规则不覆盖本网络类别（`-Profile Private` 遇上 Public 那次教训就是它）、一条规则都没有、
监听没绑在网络地址上、本机根本没有局域网地址、以及问不出来。**它读、不写**：命令交给读者执行，程序自己不
动防火墙。实测两种结论都拍到了（见 `packaging/README.md`）。

**三个缺陷是 owner 在真机上按出来的，而且都是这一轮引入或暴露的；它们比功能本身更值得记。**
按被发现的顺序：

1. **按下「一致」之后屏幕没有任何变化。** 同意只是解开了闸门，而交换要等**另一台**设备的 owner 也同意才会
   继续——所以在自己这一侧，按下按钮之后看到的就是「什么都没发生」，而「这个按钮点不动」是唯一说得通的读法。
   owner 用的正是这七个字。修法：同意之后把屏幕从问题移开，进入等待状态（`answerComparison`）；拒绝不需要新
   状态，因为交换会立刻带原因结束。
2. **监听只接得住一次请求。** `ServerSocket` 是**单订阅流**，第一版对每个请求都调 `acceptForSync`，于是第二次
   `server.first` 抛 `Bad state: Stream was already listened to`——屏幕把它如实报成「没能同步」，而设备从此
   不再接客。修法：*监听者自己持有那一个订阅*（`SocketSyncService` 里的 `_accepting` 与到达队列），每个到达的
   socket 交给 `runAccepted` 跑一次交换。
3. **同一台设备在「附近的设备」里永远被标成「新设备」。** 指纹有**两种写法**：公告里带的是给人读的分组写法
   （`ABCD-EFGH-IJKL-MNOP`），而存储里是紧凑的摘要（`ABCDEFGHIJKLMNOP`）。两边直接比较**永远不相等**，于是有
   三个后果：列表把见过的设备标成「新设备」（而下面两行的「已记住的设备」正列着它）、点它会走**陌生人**那条路
   要六位数字、确认框说「陌生」。在真机屏幕上从标签看出来的；而测试与代码犯了同一个错——假公告是按摘要写法写
   的，所以测试一直在替被检验的假设作证。修法：`DeviceIdentity.fingerprintKey` 作为唯一比较写法，
   列表、点击、确认框三处都用它。顺带修掉两处显示：确认框把**已经分组过的**指纹再分组（真机上是
   `2B99 -RU9 F-5B 5V-X GDX`），行内短指纹取到的是「五个字符加一个连字符」。
4. **连接成功了，设备却没有被记住。** 两个原因叠在一起：`ExchangeOutcome` 在「两台已经在同一个状态、无事可搬」
   这条**提前返回**上把 `peerIdentity` 丢了（而 `_remember` 正是按它决定记不记），以及接受连接的一方根本不知道
   对端的地址，于是 再同步一次 无处可拨。修法：身份写在**每一条**成功的结果上，地址由 socket 提供
   （`ExchangeOutcome.peerAddress`，在交换关闭连接**之前**读），记住时一并写下。

**两条路都在 1.0.0.519 上验过。** 修完指纹写法之后，陌生人那条路又重跑了一遍（修「认得太少」很容易顺手改成
「认得太多」，那就会让陌生人不再被要求对数字）：全新的对端在列表里是**红色问号 + 新设备**、确认框说陌生、
两边同时显示 **968 852**、两边都按一致后 `merged=5` 并写进两边日志
（`packaging/windows/nearby-1.0.519-stranger-label.png`、`connect-box-1.0.519-stranger.png`、
`compare-1.0.519-968-852.png`、`probe-peer-1.0.519-stranger.log`）。跑完之后 `已记住的设备` 里是**两台对端
各带自己的地址**（`remembered-1.0.519-both-with-addresses.png`）——这正是「设备没有被记住」那条报告的正面。

**「已记住」那条不需要数字的路也验过。** 陌生人：列表标「新设备」、确认框说「陌生」、
按下之后「两台设备各显示六位数字」，两边同时显示 **117 106**，都按一致之后应用报 `同步完成 · 0 / 5`。已记住：
列表是**金色盾牌**且没有「新设备」字样、短指纹是 `J28WH6`；确认框说「**已记住——上次见面学过它的密钥**」、
按下之后「**直接用上次学到的密钥同步，不用再对数字**」；按下去之后探针侧只留下 `outcome : merged=0 sent=0`，
**一行 `COMPARE` 都没有**——那正是「记得的设备不再对数字」这条规则的证据。照片与探针 stdout 都在
`packaging/windows/`（`nearby-1.0.519-remembered-label.png`、`connect-box-1.0.519-remembered.png`、
`probe-peer-1.0.519-remembered.log`）。

**六位数字比对后来在真机上跑通了，跑对手是一台「探针机」，不是第二部手机。** `tool/sync_probe.dart` 多了一个
`beacon` 动词：它在局域网上宣告自己、守着监听、把算出的六位数字打在自己的 stdout 上，并且**只在两边都按了
「一致」之后**才让交换继续——也就是 §10.3.2 要的那「第二块屏幕」，只是它是一台笔记本上的第二个进程。
1.0.0.518 的实测：应用在 `附近的设备` 里看到 `probe-laptop  192.168.31.157:11903`（正是探针**真实在听的**那个
动态端口），点名字 → 确认框（名字／地址:端口／指纹分组／陌生／按下之后对数字）→ 两边同时显示 **117 106**
→ 两边各按一致 → 应用报 `同步完成 · 收到/送出 0 / 5 · 对方 probe-laptop`，探针那边 `cellar now: 5 events,
2 bottles`、`remembered: NesarfDX`，而应用侧 `已记住的设备` 里出现 `probe-laptop  192.168.31.157:11903`。证据在
`packaging/windows/connect-box-1.0.518-probe-peer.png`、`compare-1.0.518-six-digits.png`、
`synced-1.0.518-zero-five.png`、`remembered-1.0.518-with-address.png` 与 `probe-peer-1.0.518.log`。
**这一条说清楚它不是什么**：它不是「第二台物理设备跑完了」——手机那一侧只拍到确认框与监听端口
（`packaging/android/tap-1.0.0.516-*`），手机当时已从 adb 上掉线。

**顺带发现的一条平台事实，值得写下来而不是当成偶发。** 同一台机器上两个进程**同时**绑 UDP 48124 时，
Windows 只把每个数据报投给其中一个 socket——所以两个本机进程**只能断断续续地互相发现**。这不是代码缺陷，而是
`data/sync/discovery_socket.dart` 早就记下的那条平台限制；也正因如此，remembered 那条路要用**存储里的地址**
去拨（探针用 `--port 11903` 在那条地址上重新守候），而不是靠发现。

**测试进程会占着公告端口**（另一条同源的坑）：`flutter test` 留下的 `flutter_tester` 仍然绑着 UDP 48124，
于是应用**看起来在公告、却收不到任何东西**。`netstat -ano -p udp | findstr 48124` 是那条一眼看出问题的命令。

### 10.4 Data merge

- **Clocks use HLC (hybrid logical clock)**, not wall clock. A phone and a computer differing by tens of seconds is normal; using physical time for LWW yields the wrong conclusion about "who wrote later".
- **Stock goes through op-log** (section 6); other fields use field-level LWW.
- Sync = exchanging events the other side is missing, requiring no diff logic whatsoever.

---

## 11. Adapter layer (network - peripherals - render tiers)

### 11.1 Network adapters (offline-first, all off by default)

| Adapter | Purpose | Default | State, 2026-09-23 |
| --- | --- | --- | --- |
| `LocalBartenderAdapter` | AI bartender | off | **built** -- against a local model, see below |
| `PriceAdapter` | E-commerce price comparison, feeding `priceHistory` | off | not built: it needs price sources this project may not query |
| `BarcodeAdapter` | Scan to identify bottles, complete ingredient entries | off | not built: a camera is platform code, and there is no catalogue to resolve a code against |

**[built 2026-09-23] The bartender, against a model on this machine.** `lib/adapters/bartender.dart` plus
`lib/data/adapters/bartender_client.dart`, pointing at `http://127.0.0.1:11434` (Ollama) by default. It is the
first adapter that exists, and the choice of *which* one to build first was not arbitrary: it is the only one of
the three whose disclosure can say something stronger than "we send your cellar somewhere", because a loopback
address means **nothing leaves the device at all**. The registry did not change to accommodate it -- an
implementation exists, `isAvailable` answers true, and the row in the device section follows, which is what
`declared.dart` said would happen.

**What it is told, and what it sends.** The shelf: one line per bottle, in the reader's own words for it, with
what is left. **Not prices yet**, and that is a question rather than an omission: `BottleState` carries no price,
the price book is keyed separately, and "what did a partly-drunk bottle cost" is a decision about the pricing
layer. The disclosure lists exactly the keys the request carries -- `question` and `cellar.bottles` -- because a
disclosure that names a key nothing sends is inaccurate in the safe direction and still inaccurate.

**The first real answer, and what it says about the model.** Asked 架上的金酒快没了，还能做几杯？ with 200 ml of
gin, 400 ml of Campari and 120 ml of sweet vermouth on the shelf, `qwen3:8b` on a 1660 Ti took **73.6 s** and
answered 目前金酒还剩200ml，可做约10杯（每杯约20ml）-- *grounded in the shelf, and wrong about the drink*: a Negroni
takes 30 ml of gin and needs the vermouth and Campari with it. So the plumbing is right and the reasoning is thin,
which is what an 8B model with a short prompt gives. **Giving it the library's own recipes is the next step**,
and it is a prompt change rather than an architecture change.

**`isAvailable` is true and "a model is listening" is a different question**, answered at the moment of use: with
Ollama stopped, the probe returns `SocketException: connection refused` and the screen shows that reason verbatim
rather than hiding the switch. That distinction is the registry's own comment about a shut door and a broken one.

#### 11.1.1 The barcode: what it needs before it can be switched on (2026-09-25)

Owner's instruction: *把条码功能设置为需要联网与调用摄像头，然后看看还需要做什么令其可用.* So the entry is no longer a
refusal -- it is a declared seam that states its two requirements, and the section prints them **before** the
switch rather than after. What follows is the honest remainder.

**Done:** the seam (`BarcodeAdapter`), its disclosure (one host, one payload key, `sendsAnythingAboutTheCellar:
false`, `needsCamera`, `needsNetwork`), the requirement line on the adapter card in five languages, and the
default -- off, like every other adapter in this section.

| # | Still needed | The detail that matters |
| --- | --- | --- |
| 1 | **A camera plugin** | Nothing in `pubspec.yaml` today. `mobile_scanner` covers Android/iOS/macOS; **Windows and Linux are not supported**, so the handset is the scanning device and the desktop must show the seam as unavailable rather than pretend otherwise |
| 2 | **The permission** | Android: `CAMERA` in the manifest **and** a runtime request; iOS: `NSCameraUsageDescription`. Android 13+ needs nothing beyond that |
| 3 | **A decode path that can be tested** | The plugin decodes, but CI has no camera -- so the test feeds a **generated EAN-13 image**, which is also how the decoder's behaviour on a bad frame gets checked without pointing anything at anything |
| 4 | **A catalogue client** | **Open Food Facts**: open API, ODbL, run by a foundation -- the same shape of organisation as S.M.Y.T. rather than a shop with terms. Honest caveat: its coverage of spirits is uneven, which is not a reason to skip it but is the reason for #5 |
| 5 | **The reader's own registry** | A scanned code is remembered as *that ingredient*, so the second scan is instant and offline. The network only ever **suggests a name**; a bottle scanned on a plane is still recorded, and the feature gets better with use rather than with connectivity. This is the offline-first rule of this section applied to its one adapter that reaches outside |
| 6 | **A consent step** | Off by default; switching it on must show the two requirements and what leaves the device (a number printed by a distillery, and nothing else) **before** the camera opens |
| 7 | **Where a scan lands** | The ingredient sheet: the name from the catalogue, the volume and the **price** typed by the reader -- and the price field is the costing line's own field, so a scan can prefill half of what costing needs |

**The one thing to be careful about.** This is the only adapter that **looks at the world**, and the only one whose
input is not typed by the reader. Its disclosure is therefore the one that has to be strictest, and it is: the
camera reads a number; the number is what leaves; nothing about the shelf, the log, what was paid or how much is
left goes anywhere. If a later version wants to send more than the number, that is a new disclosure rather than an
extension of this one.

### 11.4 Features that are not usable are not shown (owner, 2026-09-25)

> 每一项功能必须要可以实现并使用，无法做到的就需要暂时隐藏，等以后确认可用了再放出。

**The rule, and what it overturns.** The adapter layer was designed to *declare* what it could not do -- a card
saying "not built, and here is why" -- on the reasoning that an honest refusal beats a silent gap. The owner's rule
is stricter and better: a reader looking at a switch wants a feature, not a disclosure about a feature that does not
exist. So the declarations stay in the code and the **cards do not appear**, and the test
`registry_test.dart`'s `visibilityRule` asserts that everything a screen may show is something this build runs.

**Held back, with what each is waiting for:**

| Held back | Waiting for | Where it lives meanwhile |
| --- | --- | --- |
| Price comparison adapter | price sources this project may query -- the same question §7 has left open from the start | `UnimplementedAdapter(AdapterKind.priceComparison)`, disclosure not yet written because there is nothing to state |
| Barcode **scanning** | a camera plugin, the Android `CAMERA` permission and its runtime request; `mobile_scanner` has no Windows or Linux support, so the handset is the scanner | `BarcodeAdapter`, fully declared -- host, payload key, `needsCamera`, `needsNetwork`, and 11.1.1's seven remaining items |
| Bluetooth scale / IMU / gamepad | device protocols, and the calibration work each needs | `InstrumentAdapter` |
| Anything coffee-specific | the owner's own decision to do it later | nowhere yet, by design |

**Not held back, and the distinction matters.** The barcode's **manual entry** is implemented, tested and usable --
type the digits, the check digit is verified, an unknown code is named and remembered -- so it stays visible while
scanning is hidden. A feature is hidden when *no* path through it works, not when one of its paths is missing.

**And "usable" is not the same as "implemented".** The bartender's card is shown because this build contains an
implementation, but whether a model is listening on the loopback address is a fact about the moment, so the card has
to say which of the two it means. A card that implies a working assistant while nothing is listening is the same
fault as a card that says "not built": it claims something the reader cannot use.

### 11.2 Peripheral adapters

**The Bluetooth scale and "precision dosage" are a natural pair** -- a measuring cup is never as accurate as a scale; volume is affected by temperature and density, mass is not.

| Peripheral | Protocol | Purpose |
| --- | --- | --- |
| **Bluetooth scale** | BLE GATT | **Precision weighing; live readout while pouring, prompt to stop when the target is reached** |
| External IMU | BLE | Shaking measurement with higher sample rate and lower noise |
| Gamepad | HID | Navigation without touching the screen |

Coffee scales (Acaia, Timemore and others) have mostly opened their BLE protocols already, so this is technically within reach.

### 11.3 Render capability adapters

See section 16.5 "device capability tiering and dynamic degradation".

When enabled, it must state plainly which data leaves the device. Keys are stored via `flutter_secure_storage`, never written to logs, never included in export packs.

**What differentiates the AI bartender**: another source's Bart does not know what is in your liquor cabinet. We can inject **stock + remaining quantities + cost** into the context, so it answers --

> "With that nearly empty bottle of Plymouth Gin and your Campari, you can still make three Negronis at 43 yuan each."

another source's system prompt has been obtained in full (see `an earlier survey`) and can serve as a writing reference. Its key points are worth keeping: ingredient names in their generic form, garnish expressed through the `unit` field rather than concatenated into the name, ice never listed as an ingredient, and the `extra` field used only to add specification rather than restate the name.

---

## 12. Interface

### 12.1 Liquid colour rendering (adopted from one source)

A short string of data draws the drink in the glass, at very low cost and with very high recognizability:

```
colour          : orange_dark      // primary colour
colourSecondary : -                // secondary colour
opacity         : 75               // opacity %
opacitySecondary: 75
layered         : FALSE            // whether layered
```

Combined with `glass` (Cocktail / Highball / Lowball / Flute / Shot / Pint / Wine) and `ice`, this is enough to recognize the drink at a glance in a list.

### 12.2 Shelf bottle placement (adopted from another source)

`Bottle` carries `posX` / `posY` and `shelfId`; shelves and fridge drawers support drag-and-drop placement. This is where the word "warehouse" gets its concreteness -- **looking at your own liquor cabinet, not reading a list**.

### 12.3 Five tabs

| Tab | Responsibility |
| --- | --- |
| **Stock** | Stock entry, browsing by category, remaining quantity, expiry, prices |
| **Bar** | Visualized shelves; the place to choose "which Bar" is being worked on |
| **Recipes** | Recipe list with match badges; filter by makeability/flavour/base spirit/glassware |
| **Cellar** | Statistics, consumption curve, value, ShoppingList, devices and sync |
| **Settings** | The application's own settings: language and subtitles, measuring system, money |

**There were four, and the fifth is the owner's decision.** The reader's language, units and money
used to be a section at the bottom of **Cellar**, under the statistics -- which is the screen a person
opens to look at their bottles, and the wrong place to find the controls for the program itself. The
line the split draws is **"how the program behaves" against "what has happened to my bottles"**, and
it puts devices and sync on Cellar with everything else that is a fact about *this cellar* rather
than about the application.

**One consequence worth stating, because it contradicts an earlier paragraph in this document.** 12.4
says the settings screen "belongs in Cellar, which is a P2 placeholder" -- that was the position while
12.3 named four tabs, and it is no longer the position. The settings screen exists, it is this tab,
and what it lacks is the `.arb` files rather than a home.

---

### 12.4 Language and localization

**Two rules, pointing opposite ways.** Everything a person never reads is
English and ASCII. Everything a person *does* read is real UTF-8 -- the actual
micro sign, the actual Chinese, the actual accents -- and it is a
**localization configuration**, not a single translation. ASCII-fying display
copy to keep the other rule tidy would be destroying the product to satisfy it.

The boundary is worth asking about explicitly every time a string is added:
**who reads this, and where does it end up?**

| | Encoding | Language |
| --- | --- | --- |
| Identifiers, keys, event types, log lines, diagnostics, design documents | ASCII only | English |
| Labels, headings, empty states, error copy, units as drawn on screen | Real UTF-8 | The reader's locale |

**The constraint from section 3 still holds:** the domain layer contains no
display text at all. It deals in microlitres and rationals; "ul" against the
micro sign is a decision a screen makes, not a fact about a volume. A translated
string can therefore only ever enter through the UI layer -- which is also why
the domain layer can be tested without a locale ever being loaded.

**Planned locales.** The list is settled; the default and the fallback chain are
not, and nothing is implemented. The variants are deliberate rather than
excessive: 港繁 and 台繁 differ in vocabulary and not only in glyphs, and 朝鲜语
and 韩语 are two orthographic standards of one language.

| Display name (native) | Locale tag | Note |
| --- | --- | --- |
| 简中 | `zh-Hans` | |
| 文言文 | `lzh` | Literary Chinese; a real ISO 639-3 code |
| 港繁 | `zh-HK` | Hong Kong traditional |
| 台繁 | `zh-TW` | Taiwan traditional |
| 自定义中文 | -- | see below: not a locale |
| 朝鲜语 | `ko-KP` | North Korean standard |
| 韩语 | `ko-KR` | South Korean standard |
| 日语 | `ja` | |
| 法语 | `fr` | |
| 德语 | `de` | |
| 意大利语 | `it` | |
| 俄语 | `ru` | |
| 西班牙语 | `es` | |
| 葡萄牙语 | `pt` | |

The first column is non-ASCII on purpose, and it is the rule demonstrating
itself: a language picker shows every language in its own script, so the display
name is UTF-8 while the tag beside it stays ASCII for the machine to match on.

**Why a tag and not a name: two shipped cases, one of each.** The requirement
above is not a preference. Two released games were read for it, and they bracket
the outcome.

*What happens without it.* HypnoApp identifies a locale by **directory name
alone**. The measured result: **eight directories for six languages** --
simplified and traditional Chinese each ship twice, once under a native name and
once under an English one -- and both entries are reachable from the language
menu, because nothing in the loader knows they are the same language. Worse, the
pairs are not copies: the dialogue is byte-identical within each pair while the
interface strings differ, and `LangVersion` is `1` against `1.1.0`, so the older
revision ships beside the newer and a user who picks the wrong entry gets the
older interface. The same cause produced a typo in the shipped language name
(`繫` for `體`), a version qualifier stored *inside* the identity
(`English(Alpha ver)`), and one file in twenty-four carrying a BOM so that a
reader keyed on the first header column works on twenty-three files and breaks
on one.

*What it looks like with it.* iSekaiju ships its locales as content bundles named
`<display name>(<bcp-47 tag>)_assets_all.bundle` -- `japanese(ja)`,
`korean(ko)`, `english(en)`, `chinese(traditional)(zh-hant)`,
`chinese(simplified)(zh-hans)`. **Both the human name and the machine tag are
present, and the tag is what disambiguates.** A locale costs 0.7-8.5 MB because
the fonts and atlases every locale needs are split out into a single shared
bundle paid once -- which is the half of this design that is easy to forget.

**Two consequences for this section, taken from the second case.** A locale is
not only strings: switching locale rebinds **sprites, materials, legacy fonts and
TMP fonts**, and reloads the data tables. Any element whose size or shape depends
on the language has to be rebindable, which is the same problem as the font
metrics above, one layer further out. And the machine-readable credit fields
(`Author`, `LangVersion` per language) are worth having from the first
contributor, because they cost nothing when the format is created and cannot be
retrofitted onto translations already written.

**自定义中文 is not a locale.** It is section 8's overlay layer applied to
terms: the same machinery that lets someone call a gin "my gin" lets them
replace any label. Built as a fifteenth locale it would duplicate something the
project already has, and it would put a user's own words into the shipped seed
data instead of on top of it.

**Mechanism, when it is built.** Flutter's `flutter_localizations` with `.arb`
files under `lib/ui/l10n/`, and `intl` for numbers, dates and units. Locale
choice belongs in settings, defaulting to the system locale. Deliberately not
started: a localization layer written before there are screens to localize
would be guessing at the strings it is supposed to hold.

**双字幕 / dual copy is a display mode, not a locale.** The instruction was
中英文方面的相互影响可以采用双字幕的类型，也就是中英文同时实现，且根据需要进行机翻（用户可编辑）.
The fourteen locales above stay fourteen; what this adds is the case the document
already had once, where two languages are wanted in the same place at the same
time -- `空庭 · Hollow Court` on Android's task switcher, chosen in section 0.1
because the switcher shows one string and this is the one string.

| | |
| --- | --- |
| **Primary** | The reader's locale, always. Not a choice made here |
| **Secondary** | One reference language, defaulting to English, itself a setting. Changing it to `zh` is a setting and not a different build |
| **Guard** | The reference language must not be the primary. One check, at one place |

**The origin of a string is carried in the type**, which is `UnitFactor.isEstimate`
applied to a sentence: `Translated` is `authored`, `machine` or `edited`, so a screen
that draws a machine's line without saying so has the same defect as a caller that
presents a guess as arithmetic. `editedTo` mirrors `calibratedTo`, and its result is
`edited` and **not** `authored` -- "a person corrected a machine" is not "a translator
wrote this", and collapsing the two would turn a user's correction into this project's
own copy.

**A correction goes to section 8's overlay and never into the seed**, for exactly the
reason 自定义中文 is rejected above: it is the user's words *on top of* the shipped
data, so it survives an update and is never something this project redistributes.

**Not every string is a pair, and the split is mechanical rather than aesthetic.** A
`CopyLine` is a string displayed as itself with room to be two lines; a `String` is a
string the platform or a composition has already confined to one line. The second
group is not a queue of pending work, and three walls account for most of it:
`NavigationDestination.label` takes a `String` -- so **the five tabs of section 12.3
cannot pair at all, which is what "the first place this shows up" turned out to
mean** -- `InputDecoration.labelText` and `hintText` take a `String`, and a `{count}`
template or any interpolation has to be substituted by a `String`, so a pair cannot
survive it. A button label and a chip label are one line by construction, which is the
noise this section's "who reads this, and where does it end up?" already rejects.

**Built: the mechanism, the whole existing copy inventory, and as of the settings key and
locale resolution.** `lib/ui/l10n/dual_copy.dart` holds the types and has no imports at
all, so it stays testable without Flutter; `lib/ui/l10n/dual_copy_text.dart` holds
`DualCopyText`, which reads the setting at the leaf -- which is why section 4.2(a) of the
proposal can say no boolean is threaded through the widget tree. The 47 constants in
`Copy` are split **23 pairs and 24 single-line**, the 24 being the confined sites above.

The two things this section named as missing are no longer missing.
`lib/ui/l10n/locale_catalogue.dart` carries the thirteen planned locales plus the
reference language, and resolves a system tag by a four-step chain; `locale_settings.dart`
holds the three settings and section 12.4's guard, applied in one place;
`locale_providers.dart` persists them and, in doing so, is what `dual_copy_text.dart`
predicted would arrive -- that file's `dualCopyProvider` now derives from it and **nothing
else in the tree changed**. Two [decision]s had to be made where this section left the
question open, and both are marked in the source rather than presented as the document's:
the fallback is `zh-Hans`, and the reference language is a selectable locale rather than
only a second line.

**Deliberately still not built: the `.arb` files and `intl`.** Those two are one piece of
work and they are waiting for a reason that has not changed -- they need real translations
for twelve more languages, and generating them would produce exactly the `machine` strings
that `TextOrigin` exists to keep apart from `authored` ones. Those 24 single-line strings
are still their first content. **The settings screen is built now**, and this paragraph used to
say it could not be -- "section 12.3 has four tabs and no settings tab, so it belongs in Cellar,
which is a P2 placeholder". The owner asked for a settings tab, 12.3 names five, and `SettingsPage`
is that screen; what it still lacks is the `.arb` files above, not a home.

### 12.4.1 港繁／台繁是「生成」的，不是「另写」的——实测边界（2026-09-22）

**这条来自对 a rhythm game 译文表的实测**（`an earlier survey` §8.19）。它的四份 gettext 目录
（`ja.mo`／`ko.mo`／`zh-Hans.mo`／`zh-Hant.mo`，各 **1401 条**）里，同一条英文在两个中文目录里
**不只是简繁字形之差，措辞本身不同**：

| 英文原文 | `zh-Hans.mo` | `zh-Hant.mo` |
| --- | --- | --- |
| `WARNING! Stamina has already been…` | 警告！**在开始关卡时**你的体力就已经被消耗！ | 警告： 已經消耗了體力 |
| `Retry` | 重试 | 重試 |

**我们的港繁／台繁目前是「由简中经 OpenCC 生成」**，所以这条给出了该做法的**确切边界**：

- **做得到**：字形转换（`重试 → 重試`）、以及本项目里那 164/275 条**用词确实不同**的条目；
- **做不到**：像「在开始关卡时…」→「已經消耗了體力」这种**重写**——
  那是译者在繁体语境里会改的句子结构，**不是转换器能产出的**。

**[decision] 因此口径定为两句，不能混为一谈**：

1. **港繁／台繁算「已交付」**——它们是对的繁体字，读者能读，界面完整；
2. **但它们不算「已本地化」**——本地化包含措辞重写，而这一层**我们目前没有做**。

`tool/l10n_status.dart` 的计数随之改口径：港繁／台繁一列标注为 **generated（由简中生成）**，
而不是与简中／英文／日文并列的 **written**。**这条区分不是为了谦虚，是为了让「还差什么」这个问题有准确答案**：
按新口径，**真正待办的是「繁体措辞复核」，而不是「繁体未翻译」**。

### 12.4.2 繁体措辞复核：机器那一半做完了，剩下的不是机器的事（2026-09-23）

12.4.1 把待办定名为「繁体措辞复核」。这一节是**真去复核**的结果，用的是 `tool/traditional_wording_audit.py`
（两项检查：字形、术语）。三项发现，其中一项是**检查本身错了**：

**一、`s2hk` 的短语表比 `s2twp` 薄得多，薄的那一栏正是港繁。** 五项术语命中**全部落在 `zh-HK`**，
`zh-TW` 那边早就写对了——同一句话，台繁得到 `螢幕／程式／介面／檔案`，港繁保留着大陆用词：

| 条目 | 港繁（改前） | 台繁（本来就对） |
| --- | --- | --- |
| `syncHint` | 對方**屏幕**上的碼 | 對方**螢幕**上的碼 |
| `syncEditHostHint` | 對方**屏幕**上顯示的那個 | 對方**螢幕**上顯示的那個 |
| `settingsIntro` | 調的是**程序**本身 | 調的是**程式**本身 |
| `displayHeading` | **界面**樣式 | **介面**樣式 |
| `developerLogPath` | **文件** | **檔案** |

五处已按右列修正。**所以「港繁/台繁已交付」这句话里，最薄的一栏是港繁**，而原因不是谁偷了懒，
是 OpenCC 两张表的覆盖率不同——知道了这一点，下次生成完就该先看港繁那一列。

**二、第一次的检查是错的，而且错得很有教育意义。** 原以为「`s2t(c) != c` 即简体字」精确、无假阳性；
第一次跑出 **18** 条，其中 **17** 条是 `台 → 臺`。`台` 本身就是正体字（一台電腦、台灣），OpenCC 只是把
**异体**归一。修正后的口径写在工具里：命中的集合是「异体字 + 简体字」，把两者分开的是白名单，
**而白名单是一条主张，不是一条事实**——它只主张这些字在港台就是这么写的。

**三、引日文的地方要留日文字形。** 最后剩的一条是 `aboutNaming` 的 `日文是「虚ろな庭」`：改成 `虛` 就是
**引错**。规则因此定为「同一行里出现假名 → 整行跳过」，而不是把 `虚` 加进白名单——白名单会连带漏掉
真正把 `虚` 写错的那一行。

**结果：两项检查均为 0。但这不等于「繁体已本地化」**，12.4.1 的边界仍然成立：机器能管的是字形与术语，
而措辞重写（句序、语气、以及「在开始关卡时…」那类改写）仍然需要读者。**复核把「还差什么」从一句模糊的
话变成了一张只剩重写这一项的清单。**

### 12.5 Entering a measurement: the number on the left, the unit on the right

**Every place a measurement is typed is a number box and a unit menu beside it, and never a
label that names the unit.** The first version of the volume field said 容量（毫升）, which is
one unit and only one: a reader who measures in ounces had to convert before typing, and
arithmetic done in somebody's head is the one place in this project where a number is allowed
to be wrong. So `MeasureField` is the shape, and the shelf, the settings and the form all read
the same `MeasureSet` for a state of matter -- a bottle entered in ounces is a bottle the shelf
can show in ounces.

| | Decision |
| --- | --- |
| Which units are offered | The reader's own set for that state of matter, primary first -- not every unit the system carries, which would offer a dash for a bottle of gin |
| What it opens on | The primary, so a metric reader opens on millilitres and an American one on ounces without touching anything |
| What picking a unit changes | This entry, not the preference: a bottle bought in ounces is a fact about that bottle |
| What happens to a number already typed when the unit changes | It is **converted**, because the number is a statement about a bottle and the unit is only how it is said -- the same reason a changed preference redraws every bottle. Reinterpreting it would turn `700` into 700 cl under the reader's hands |
| What a half-typed or empty box does | Nothing. A unit switch is not a reason to delete what somebody was saying |
| Where the conversion happens | Once, on submit, through the same file that prints the shelf (`microlitresTyped` / `volumeNumber`) -- so what is typed and what is read back cannot disagree |
| Where the amount is stored | The exact base. `addBottle` takes a `Volume` rather than a count of millilitres for this reason: half an ounce is 14 787 µl, and a millilitre-shaped door would store 14 000 |

**Both dimensions, because both now have a pair of doors.** This section's first version recorded
the mass case as a known gap: `UnitSystem` had a forward door for volume (`volumeOf`) and only an
inverse one for mass (`milligramsOf`), so a solid could be printed on a shelf and never weighed into
one -- 固体用克 was half an instruction with no way to follow it. `UnitSystem.massOf` is that door,
and `milligramsTyped` / `massNumber` are its pair, so a box beside a `g` menu converts exactly as a
box beside an `ml` one does. A dimension with no pair is still left alone rather than guessed at:
reading a box as millilitres and writing it as grams needs a density no source here carries.

### 12.6 Entering a price: the same row, and the opposite rule

**A price is a number and a currency, and the currency menu reinterprets the number rather than
converting it.** That single difference is why `PriceField` is a second widget rather than a flag on
`MeasureField`, and the reason is not stylistic:

- A millilitre and a centilitre are two names for one quantity with a fixed ratio, so switching the
  menu beside a **measurement** converts the number. 700 ml becomes 70 cl and the bottle did not
  change.
- A yuan and a yen are two different quantities with no ratio this program can know. It has no
  exchange rates and section 7's series is denominated per currency, so switching the menu beside a
  **price** reinterprets it -- the digits stay exactly as typed and only the denomination changes.
  Converting would need a rate nobody has, and inventing one would move a number by an amount no
  screen would show.

| | Decision |
| --- | --- |
| The number typed | The **major** unit, as a person reads it (`45.50`). The field used to ask for a whole number of fen, which is one currency's minor unit written into a label: the same box under JPY means yen and under KRW a thousandth of a won, and the label named neither |
| Which currencies are offered | The reader's own slots, from `CellarPreferences.currencies` -- the same set the settings screen edits |
| What the menu shows | The ISO code, not a symbol. `¥` is the yuan and the yen, and a picker offering it twice is a picker nobody can choose from; section 12.4's rule that a person never reads the code is about the wire, and this is where the ambiguity has to be visible |
| Where the amount is stored | Minor units **and the currency**, because the event has always had the field and the form never filled it. `addBottle` takes a `Money` so the denomination cannot be left behind |
| An amount the currency cannot hold | **Refused, not rounded.** `45.50` is a price in CNY and not one in JPY; the first version of `minorUnitsTyped` rounded it to 46 yen, which is a number nobody typed |
| What happens to a number already typed when the currency changes | Nothing. It is not converted, for the reason above |

**The row itself is shared** (`AmountRow<T>`), which is not tidiness but a bug that was already paid
for once: the menu is an `InputDecorator` around a `DropdownButton`, and a `DropdownButton` keeps a
48-pixel minimum, so the first version stood 80 pixels tall beside a 56-pixel number box. Two forms
with two copies of that row would be two chances to get it wrong, and only one of them would have the
test.

**A prediction this project made and had to correct.** `price.dart` said the add-bottle form asking
for a currency would make `stockPriceCurrency` unreachable and that it should then be deleted. The
form asks now, and the constant is still reachable: every `stock.bottle.added` already written
without a currency reads through it, including the ones in the owner's own log. It stays as a read
fallback for those events, and the correction is recorded where the prediction was rather than here.

### 12.8 The look: four themes, and an instrument behind them

**The palette is a value with four instances, and the interface reads it through getters.** It was ten
`static const Color`s, which is the cheapest thing that can work and cannot be switched -- a theme is a
value the whole interface reads, and a constant is a value that cannot change. `HollowPaletteValue` is
one theme's ten colours; `HollowPalette` is the one in force.

| Theme | What it is |
| --- | --- |
| `court` | The Renaissance medallion in a dark room -- what the application always was |
| `parchment` | Aged paper with iron-gall ink. A page of white with grey text is a document; a page of paper with ink is a journal, and 12.3 calls that tab 记录 |
| `astrolabe` | The same building at three in the morning: deep indigo with brass, the blue in the ground so it is felt rather than noticed |
| `ivy` | The ruin in daylight: pale limestone, moss, brass. The green is `gold` there, so "a drink that can be made" is the colour of the plant on the wall |

**Two costs, both deliberate.** The palette is a getter over one mutable global rather than an inherited
value, because the alternative -- threading a palette through a hundred call sites and seventy-six text
styles in sixteen files -- buys *per-subtree* theming, and this application's appearance is one decision
for the whole program like its language. What that costs is that a change is visible when the tree
rebuilds, which is why the switch lives at the root. And `HollowType` stopped being `const`: a
`const TextStyle` bakes in the colour it was compiled with, so a theme switch would have left every word
in the old one. The corollary is the guarantee -- **there are no `const` widgets holding colours**,
because the compiler refuses.

**The promises are asserted.** `theme_palette_test.dart` computes WCAG contrast for all four themes: ink
and secondary text clear 4.5:1 on all three surfaces (twelve checks), the faintest text stays above
2.2:1 and below the other two, both accents clear 3:1, the names are distinct because a name is the wire
format, an unknown name falls back rather than failing, and every theme *builds a `ThemeData`* -- which
is the check whose absence let a hardcoded `ColorScheme.dark` reach a light theme, where `ThemeData`
asserts and throws on the first frame.

**The ornament is drawn, not imported.** The reference material for this work is a photograph of an
astrolabe printed into old paper, and the response to it is the same as the response to the medallion:
geometry, ours, generated. `ornament.dart` paints three concentric arcs, sixty graduations with every
fifth one long, and twelve radial rules, centred above and to the right so the part a person reads is
the lower-left quarter. It is drawn in the palette's own hairline colour at a third opacity, and the
test asserts that **a hairline can never be the highest-contrast thing on the page** -- so a background
cannot compete with text for attention, in any theme, including ones written later.

**How to look at it.** `flutter test test/render_themes_test.dart` writes one PNG per theme into the
cache directory, using `RenderRepaintBoundary.toImage`. It exists because the obvious way to review a
theme -- screenshot a running window -- stopped working on this machine: two platforms both came back
blank because their windows were never composited while another application held the foreground. Text
in those files is drawn as boxes, since `flutter test` has no font and this application bundles none;
colour, spacing and the ornament are what they show.

---

### 12.7 The mark: blackletter HC, and the licence that comes with it

**The icon's two letters are blackletter, and they are geometry rather than a font reference.**
`art/make_icon.py` draws the medallion and takes the H and C from `art/blackletter_glyphs.py`, which
`art/extract_glyphs.py` generates by outlining them from a typeface. Both halves of that sentence
matter:

- **The outlines are committed as data, so nothing needs the font installed.** The mark renders into
  an APK, an MSI, an AppImage and a 16-pixel `.ico`, and a `<text>` element would be re-shaped by
  whatever the renderer's font stack happened to resolve to -- or dropped, silently, on a machine
  without the face. This is the rule the Roman capitals already followed, and blackletter is exactly
  where somebody would be tempted to break it.
- **The typeface is consulted once, by a human, at extraction time.** `extract_glyphs.py` is the only
  thing that opens the font file, and its output is what the repository holds.

**12.7.1 The mark is now drawn at three densities (2026-09-24, from a study of a crafting game).**

Sensei asked for the icon to be improved on the existing basis with the game **a crafting game** as the
reference. It is in the local Steam library (appid 1210320) and its mark -- oak branches, a distressed
wordmark, two inks on aged paper -- is studied in `an earlier survey`.

The measurement that came out of that study: the mark was **one drawing at fifteen sizes**. Seventy-two
beads, twenty-four pyramids, an eight-stop bismuth ramp and two thin white ring strokes, all drawn at 1024 and
scaled down, so below 48 pixels it became a grey ring and **the two blackletter capitals -- the letters the
application is named for -- were the first thing to disappear.**

What was taken from the reference is its *method*, not its art: flat silhouettes with the detail **cut out of**
them rather than drawn on them, **two inks** rather than a spectrum, and a stamped mark that survives being
small. Ours was the opposite -- detail added as thin lines -- and no amount of care at the middle sizes rescues
it at 16.

So `art/make_icon.py` now emits three drawings and `art/render_icons.sh` renders each size from the one made
for it. That is the rule the render script already applied to the `.ico` frames ("the 16 in the taskbar is a 16
drawn at 16"), one level up:

| Size | Drawing |
| --- | --- |
| 128 and up | the whole medallion: 24 pyramids, the bead-and-reel moulding, all eight crystal hues |
| 48 to 96 | 12 pyramids, no moulding (one flat ring instead), five hues, letters at 300 units |
| 32 and down | 8 pyramids, no white ring, **two inks** -- the application's own gold and rose -- letters at 352 units, stroked in their own colour so their diagonals hold |

**The identity did not move.** The halo keeps its three elements and the fifteen degrees of clockwise tilt from
the character sheet, the blackletter proportions are untouched, and every colour is one the application already
uses. What changed is how much of it is drawn at each size.

**The two-ink line was arrived at by looking, not by taste.** The first cut of the smallest tier kept four
crystal hues; the comparison render -- the old mark downscaled from 1024 above, the new drawings at their own
sizes below, magnified 6x with nearest-neighbour sampling so the actual pixels are visible -- showed a bright
four-colour ring competing with the monogram it surrounds. Two inks fixed it, which is the reference mark's own
rule rather than a coincidence. The comparison sheets were working material and have been deleted; what they
showed is written here and in the study note.

---

### 12.9.1 从 a rhythm game 研究借来的三条，落到空庭的三处（2026-09-22）

**研究不落到代码就等于没做**，所以把量到的三条写成清单，每条都指到具体落点与**可判定的完成标准**。

| # | 借来的 | 落到哪里 | 完成标准（可判定） |
| --- | --- | --- | --- |
| 1 | **母题在同一形状的多个尺度上重复**（它的菱形：10×10 分隔件 → 卡片外框 → 按钮） | 我们的母题定为**光环上的铋晶体棱形**（`lib/ui/prism.dart`，一个 painter，不是三张图）。**已落地四处：分隔件**（设置页两处）、**空态**（配方页与「要买什么」）、**列表行之间**（配方页文件夹行，10px→8px）、**极淡叠层**（`PrismWash`，整窗背景，见下）。**未落地：选中态角标**——不是没做，而是**没找到一处真实的「选中」状态值得放**：把标记硬塞进一个没有选中语义的位置，那是装饰，不是母题在做事。等有真正的选中态（例如「已选中的那瓶酒」）再落 | 这四处出现**同一个**几何，且小到 10px 级仍可辨；不是四张各自画的图 |
| 2 | **按钮三态成对定义**（`Button_Normal`/`Press`/`Disable`，在 `.csb` 字段、贴图命名、`assets/Default/` 实物里各出现一次） | 主题里为**可用／按下／禁用**三态各定一个明确样式；禁用**必须与可用成对出现**（它在 a rhythm game 里就是紧挨着可用的灰色箭头） | 任取一个可点控件，把状态切到禁用，**不看代码就能说出它为什么是灰的**；玫瑰色＝拒绝、金色＝已选的既定分工不变 |
| 3 | **设置行四件套：标签＋说明＋当前值＋控件，而且「说明」是结构里的必备件**（`*Label`/`*Description`/`*Text`/`*Button`，说明写明**代价**：`Uses more … battery`） | 设置页现有各行 + 入库表单的单位行（它已有「为什么是这套单位」一句，正是这条的雏形） | **每一行都有一句「代价或理由」**；没有解释的行视为未完成 |

**a mobile game 的实测给第 1 条补了一份旁证（2026-09-23，见 `an earlier survey` §10.1）**：
同一枚 Art Deco 母题在那款游戏里以**三种处理**交付，而且数字是量出来的——**填满**（覆盖率 77.8%）、
**描边**（8.9%）、以及把 alpha 压在 **91/255（36%）** 的**极淡叠层**。前两者与我们的 `PrismMark`／`PrismDivider`
正是同一种关系，**所以第 1 条不是「省画工」的做法**，而是有人手充裕的团队也会选的做法；**第三种也已落地为
`PrismWash`**（背景层，见下）。

**第三种本来打算不做，the owner 2026-09-23 定了「做」，于是它落地在背景层**：极淡叠层现在是
`PrismWash`（`lib/ui/prism.dart`），画在 `OrnamentBackdrop` 里、**星盘之下、内容之后**。两个数字各司其职：

- **上限 0.36 是量出来的**，写进代码并在 `PrismWash` 里**强制夹住**——调用方传 1.0 也只能拿到 0.36，
  所以没人能把背景做得跟正文抢对比度；
- **默认 0.18** 是层级决定的：星盘本身只放行三分之一，纹样若比地板更显眼就把乐器挤到后面去了。

**它的可见性是量过的，不是看感觉**：在 `court` 主题下渲染取样，底色 18、格线 23——**5 级对比**，
与星盘那条「[decision] 一个三分之一，是看着定的」同一档：**看时在，读时无**。
叠层仍**不落在正文之上**：参考里的用法是压在画面之上，而空庭是工具，正文是要读的，所以它进的是背景那一层。
两条测试把这两件事钉住：**传 1.0 也超不过上限**、**点不到**（整窗覆盖的层若能吃点击就是 bug）。

**为什么把第 3 条排在最前**：它**最小、立刻可见、且我们已有一半**——库里已经有一条「为什么是这套单位：…」
（单位识别那轮加的）。把它推广到设置页其余各行，是这三条里**唯一能在一次改动里做完并验证**的。

**不借的那条继续不借**：a rhythm game 把次要正文压到近乎不可读（音游可以，因为主视觉就是商品）；
**空庭是工具**，配料、做法、完整性报告、同步说明都是要读的内容（见 §12.9 的取舍表）。

### 12.9.2 分隔与对比：读者报的两个毛病，量出来的两个根因（2026-09-23）

the owner 报了两件事：「各选项之间的 UI 分隔不明显」，以及「字体只有一种颜色，UI 变色后会和字体颜色相近，
观感很差」。两条都不是口味问题，把每个调色板的每一对颜色算一遍就找到了根因——**而且其中一条是测试自己在
维持的**。

**根因一：一个颜色干了两件事。** `line` 同时是「背景上的装饰细线」和「两个选项之间的分隔线」，而
`theme_palette_test.dart` 里有一条断言把它钉在 `contrast(line, ground) < 1.8`，理由是「装饰不该和文字争
注意力」。那条理由对装饰是对的，对分隔是错的：分隔是**功能边界**，按非文字对比标准要 3:1 才看得见，而实测
它在 1.4–1.7——**线一直在画，只是看不见**。

修法是拆成两个颜色，不是把一个调亮：

| 颜色 | 用途 | 约束 |
| --- | --- | --- |
| `line` | **分隔**：选项之间、区块之间、控件描边 | ≥ 3:1（对 ground / surface / surfaceRaised 都算） |
| `hairline` | **装饰**：背景纹样、图表网格、量筒刻度 | < 1.8:1，保持「不与文字争注意力」 |

a rhythm game 研究里那条建议正好指向同一处：*「可借的是『一个母题重复到底』——把光环的铋晶体棱形当作唯一几何母题，
用在图标、**分隔线**、选中态、空态上」*。所以区块之间现在用 `PrismDivider`（线 + 小棱形），选项行之间用
`HollowRule`（一像素线），母题只出现在**区块**层级——每一行都放棱形会把笔迹变成纹理。
设置页原先区块之间只有 32 像素空白，深色页面上那不构成边界。

**根因二：强调色当底、正文色当字。** `ink` 是正文色，而强调色 `gold` / `rose` 是中调色；把 `ink` 画在
强调色填充上（**选中的 `ChoiceChip` 正是如此**），实测：

| 组合 | court | parchment | astrolabe | ivy |
| --- | --- | --- | --- | --- |
| `ink` 压 `gold` | **1.7** | 2.7 | 1.5 | 1.5 |
| `ink` 压 `rose` | 2.3 | 2.8 | 2.2 | 2.3 |
| `onAccent` 压 `gold` | 8.8 | 4.7 | 9.2 | 9.2 |
| `onAccent` 压 `rose` | 6.4 | 4.5 | 6.3 | 6.0 |

而这处之所以一直没被发现，是因为 **`HollowTheme.build()` 里根本没有 `chipTheme`**：chip 走 Material 默认，
标签用 `HollowType.body`（即 `ink`），于是每个调色板都在犯同一个错。现在有一行配对规则：
**强调色填充上的前景一律 `onAccent`，永不 `ink`**，并且由测试对四个调色板的所有强调色断言，所以第五个调色板
不可能不回答这个问题。`ColorScheme` 的 `onPrimary` / `onSecondary` / `onError` 也换成了它——它们原本用
`ground`，在 parchment 上对 rose 只有 4.27，差一点。

**顺带发现一条由本轮改动引出的隐患。** 把 `inkFaint` / `absent` 提到 4.5 以上之后，它们在深色调色板里成了
邻居（实测 1.0–1.1），而禁用按钮的配色恰好是「`absent` 底 + `inkFaint` 字」——那会变成一个和背景同色的标签。
修法仍是同一条配对规则：**状态由填充承担**（gold → absent），前景两种状态都是 `onAccent`。

**被豁免过一次的东西。** `inkFaint` 原先有一条测试断言它**低于** 4.5：理由是它服务于占位符与禁用控件，而
WCAG 对这两者豁免。这条理由在理论上成立、在这个界面上不成立——`inkFaint` 是**说明文字、单位、计数**的颜色，
那些是内容不是占位符，而它在这类表面上只有 3.0–3.5。所以值被提高，那条断言被翻了过来，并补了一条「三个层级
仍然要有三个层级」（`ink` > `inkSoft` > `inkFaint`），免得提高下限把层级压平。

**四条断言现在守着这件事**（`test/ui/theme_palette_test.dart`，四个调色板全覆盖）：正文/次要/说明/不可制作
四类文字对三种表面 ≥ 4.5；`onAccent` 对 `gold` / `rose` / `absent` ≥ 4.5；`line` 对三种表面 ≥ 3；`hairline`
对 ground < 1.8。

### 12.9 The third visual reference: a rhythm game, studied from the device (2026-09-22)

the owner added a third reference beside a mobile game and a mobile game:
*"关于应用界面（包括图标）及UI的设计，除了学习bluearchive和a mobile game外，还可以学习arcaea"*, with a texture
backup already on the phone. The study is `an earlier survey`, taken from **82 files pulled
through ADB and two screenshots of the running application** rather than from memory -- and **the assets stay out
of this repository**: they are lowiro's, and section 15's line applies to pictures exactly as it applies to drink
data.

**The four things it gives us**, each landing on a decision rather than a mood:

| Borrowed | Where it lands |
| --- | --- |
| **one motif, repeated to the end** | the bismuth prism of the halo becomes the single geometric motif -- icon, dividers, selection, empty states. The gothic letterforms stay: the two are different temperaments and ours is the one this world has |
| **one saturated colour does the talking** | gold means chosen, rose means refused, and **there is no third accent** |
| **a high-key ground with fine linework** | that is what 羊皮纸 is for, and 深夜铜章 is its inverted twin -- so the four themes have a division of labour instead of being four palettes that swap |
| **one expression per file, numbered across languages** | how to ship Q-version art if it ever exists |

**And one thing explicitly not borrowed**: **a rhythm game can push its body text to the edge of legibility because it is a
rhythm game and the artwork is the product. 空庭 is a tool.** Ingredients, methods, integrity reports and sync
explanations are meant to be read, and this project's character lives in those sentences -- copying the
low-contrast small type would delete the part of the application that is most itself.

### 12.11 The voice axis: a register, not a language (the owner 2026-09-25)

**The request, and the two things it was modelled on.** After seeing two well-known examples of the same idea -- a
Minecraft resource pack that rewrites the game's Chinese into catgirl speech, and one that rewrites it into 梗体中文
which the PCL2 launcher ships as a *selectable language* -- the owner asked for the same thing here. **Both of those
are the same interface in a different voice rather than a translation, and both are offered as a choice.** That is the
whole specification, and it is why this is a **second axis** rather than a sixth language.

**A line resolves its language first, then its voice.** `CopyLine` already walks `localeFallbacks` for the language;
the voice sits on top of that and answers **only when both hold**: it has something written for this line, *and* it
speaks the language being asked for. The second condition is not a formality -- **a voice is written in one language
and cannot pretend otherwise** -- and it is what lets a voice carry its own locale in the enum. A line with no voice
falls through to the plain one, which is the reason adding the whole axis changed nothing for a reader who does not
choose one.

| Voice | Language | What it is | Lines |
| --- | --- | --- | --- |
| `plain` | every language at once | the application as it has always spoken | 0, by design |
| `heiress` | zh-Hans | 金发双马尾傲娇大小姐 | 22 |
| `heiressJa` | ja | ツンデレお嬢様 -- the same register **written for Japanese rather than translated** | 22 |
| `minister` | en | a permanent secretary, who would not advise a course of action and would be grateful if you considered one | 20 |

**`plain` is not the absence of a voice; it is the default one.** This matters for a reason that is easy to lose: a
voice is opt-in, so the correctness of the whole feature rests on the plain path being untouched. `Voice.byName`
resolves an unknown name -- a setting written by another build -- back to `plain` rather than treating it as an error,
and voices are stored **by name rather than by index**, like the theme and for the same reason: an index shifts the
day a voice is inserted in the middle.

**Five rules, and none of them are negotiable.** They are recorded in `docs/art/zh/charlotte-voice.md` beside the
register they constrain, and in short: plain costs nothing; a voice touches only lines written for it, so there is no
such thing as a half-voiced screen; **functional areas are off limits** -- navigation labels, buttons, units, numbers
(the navigation bar is 68 pixels tall and a voice that renames a button is a bug rather than a flourish); this is
**authorship, not translation**, and its target is the sentences a person actually reads; and both voices are written
here rather than copied from a resource pack.

**That rule is about a line, not about coverage, and the difference is worth stating because the phrase invites the wrong reading.** A line is either written in a voice or it falls back to `plain` -- there is no partly-voiced line. It does **not** promise that a voice covers every line: each of the three covers 55 of the 254, and the rest are strings the rules keep out (buttons, units, numbers, navigation). A reader who chooses one will therefore meet it on some lines and the plain sentence on others, by design rather than by incompleteness.


**Which languages have a voice is a per-language arrangement, and the default is `plain` in every one of them.** The
owner settled the shape on 2026-09-26:

| Language | Default | Its own voice |
| --- | --- | --- |
| zh-Hans | `plain` | `heiress` |
| zh-HK, zh-TW | `plain` | **none** |
| ja | `plain` | `heiressJa` |
| en | `plain` | `minister` |

**The two Traditional Chinese locales have no heiress, and that is a decision rather than a gap.** The owner's words:
中文的大小姐是仅限简体才有的 —— 再做两个繁体还要考虑一堆别的东西. So `heiress` is Simplified-Chinese only, and this is not a rule
that has to be enforced by hand: a voice carries its own locale, and `heiress` declaring `zh-Hans` means it cannot
answer for a Traditional tag even if somebody wanted it to. **What a Traditional heiress would require** -- which
phrasing belongs to which of the two, what 大小姐 says in each, whether 本小姐 survives the conversion -- is a real body
of work rather than a translation pass, which is why it is left as a decision.

**There is no audio anywhere in this, and that is worth writing down because the word invites the assumption.** A
voice in this sense is a **register of writing**: the output is characters on screen, and the storage is a
`Map<Voice, String>`. The application contains no TTS, no audio player and no audio file. Section 19's toolchain is a
**separate concern** -- it produces sound assets, and it is real and measured -- but nothing connects it to this axis.
If it ever did, the enum would help rather than hinder, because each voice already carries the language a synthesiser
would need to know. **That is not a plan.**

**Two guards turn the register into something that fails rather than something that drifts.** `voice_facts_test`
covers the hardest rule -- 「她从不隐瞒信息」, that no line of hers drops a number or a name the plain line carries --
for both Chinese and Japanese. `voice_register_test` covers the other half: that no self-reference which dates her or
belongs to another archetype appears (わらわ above all, on the owner's instruction), that 「哼」 stays an opening
rather than a tic, and that her line is never materially shorter than the plain one, because she adds tone rather than
removing information. Both carry a test that they have something to check, since a guard over an empty set passes for
the worst possible reason.

**Charlotte is the character behind `heiress`, and her documents live in `docs/art/`** in Chinese and Japanese -- the
two languages she exists in -- with the design, the register, the independence rule that keeps her from being the
product's mark or harumi, the worked examples of her as an agent, and the collected material a character card is built
from.


**How far the register may reach, settled 2026-09-26: anywhere.** The owner's ruling is that the voice is not limited
to the front end -- copy, logs, tool output, the back end and an agent's own speech are all fair game -- subject to
two rules that exist because they protect iteration and publication rather than taste:

* **Logic stays English.** The register may appear in text written *for people*; it may not grow into identifiers,
  comments, log field names or anything structured. **What she says and what the machine reads have to stay
  separable**, or the voice becomes a maintenance problem in every diff.
* **No traces.** The voice must not become a trace itself: nothing that names a machine path, a private name or a
  serial number, because everything here is published to a mirror.

That is the whole constraint. Within it the register has no boundary, and the five rules above still govern how it is
written.

## 13. Directory structure

```
E:\hollow-court\
+- lib\
|  +- domain\          pure Dart: units, dosage, pricing, match score, CRDT, HLC
|  +- data\            event log, overlay layer, seed loading
|  +- platform\        LAN service, mDNS, QR code, foreground service
|  +- adapters\        DeepSeek / price / barcode (disabled by default)
|  \- ui\              pages - widgets - theme - shelf - liquid - l10n
+- test\               pure Dart tests including the domain layer
+- data\               seed library (section 15)
+- docs\               design document, architecture diagrams, reverse-engineering reports
+- tools\              collection and validation scripts
\- dist\               build artifacts (copied into the Bundle directory afterwards)
```

**Artifact directory**: `E:\Hollow Court Bundle\` (MSI / AppImage / APK)

**Discipline**: scratch goes to `E:\DaShaoHuo\cache\tmp\`, cleared as soon as it is done with; external resources land first in `E:\DaShaoHuo\downloads\`.

---

## 14. Roadmap

| Phase | Deliverable | Acceptance | State |
| --- | --- | --- | --- |
| **P0 foundation** | Project skeleton, Domain layer (units/dosage/match score) + unit tests | Unit conversion tests all green | **done** |
| **P1 single-device usable** | Event log, seed import, Stock/Recipes pages, liquid colour rendering | Can enter a bottle, compute a match score, mix a drink and decrement stock | **done, and verified on a real device** |
| **P2 visual completion** | Shelf bottle placement, Bar page, prices and statistics | Mix a drink while looking at your own liquor cabinet | **done** -- see below |
| **P3 LAN** | QR pairing, star sync, op-log merge | Phone and computer share one cellar | **done, and done between two physical devices** -- phone and laptop shared a cellar with the code on 2026-09-22 and again on 2026-09-23 (`packaging/README.md` has both). The transport is sealed, a device is recognised by its key, and the second sync needs no code (`test/data/sync/`). The other three link modes are declared and logic-tested but not hardware-verified, each with its reason in 14.0.2 |
| **P4 three-platform packaging** | Windows MSI / Linux AppImage / Android APK | Installable and usable on all three | **done at 1.0.0.1014**, all three built from one commit with receipts in the bundle, and each verified in the way that platform allows: Windows installed and reading the whole library, Linux running under WSLg and photographed, **Android installed on the handset, running, and used** -- a bottle recorded by hand on the release build. Section 14.1's acceptance table carries the columns |
| **P5 network layer** | Bartender, price comparison adapter | Switched per item, off by default | **partly started, 2026-09-23**: the bartender is built against a local model and can be switched on; price comparison and barcode are still declarations, and off by design |

### 14.0.1 Where each unfinished row actually stands

**P2 is done, and section 12.3's Cellar tab is the summary of it.** Value, the consumption
curve in two columns, the statistics panel, the reader's own language, unit and money settings,
and the shopping list derived from plan marks -- all of them on the tab that section 12.3 gives
those things to, with the device section beside them because both are facts about this device
rather than about the cellar. The Bar tab draws shelves, stands bottles where they were put,
and takes a drop that writes a position into the log.

**P3 has a transport now, and what it lacks is a screen.** The pieces, and where each stands:

| Piece | State |
| --- | --- |
| `EventLog.clocks` / `missingFrom` / `merge` | built and tested |
| `PairingTicket`, `ClockDigest` | built and tested |
| the frame protocol (`domain/sync/wire.dart`) | built and tested, plain Dart |
| the exchange (`domain/sync/exchange.dart`) | built and tested against an in-memory channel pair |
| the socket (`data/sync/socket_transport.dart`) | built and tested over real loopback connections |
| discovery by name (UDP broadcast) | **built**: the announcement and roster, the socket, and the list on the sync screen (10.2.1). Broadcast rather than mDNS, because Android needs a `MulticastLock` for multicast |
| a QR camera | **not built**: platform code, and untestable here -- the typed code is what exists |
| the `.courtpack` carrier | **built, wired and tested** -- corrected 2026-09-23 from "written and unwired": `data/sync/courtpack_service.dart` drives it, `ui/pack_section.dart` offers export and import on the device section, and `test/data/sync/courtpack_service_test.dart` covers the round trip |
| the ADB-forwarding carrier | **built** -- corrected 2026-09-23: `data/sync/adb_carrier.dart` runs `adb forward` (and only that), with the exact command line asserted in `test/data/sync/adb_carrier_test.dart`. What it has **not** had is a real phone on a real cable driving a sync end to end |
| a button that starts any of it | built -- `lib/ui/sync_section.dart`, and the Cellar tab hosts it |

So it is no longer "the easy half", and as of 2026-09-21 it is no longer a set of pieces without a
way in: **two screens drive it end to end in `test/p3_acceptance_test.dart`.** The code is read off
one device's `SelectableText` and typed into the other's `TextField`, and what comes back is
asserted from what the screens draw -- the outcome, the `merged / sent` counts, and the peer's name.
The exchange underneath is the real one, over a real `EventLog` on disk, with the merge running in
both directions: a bottle on each side, and the other side's bottle in each cellar afterwards.

**What that test replaces is exactly one thing, and it says so in its own header**: the byte pipe.
`_MemoryChannel` is two crossed stream controllers rather than a socket, because a widget test runs
in a fake-async zone and a test that waits on a real peer is the slow, timing-dependent test
`sync_service.dart` says the socket layer's own tests exist to avoid. So the honest summary is
**"the screens drive a real sync"**, and *"two physical devices on one network share a cellar"* is
still the thing nobody has watched happen. The last row of the table above is what stands between
them, and it is a camera.

### 14.0.2 What the stable release covers, per link mode (2026-09-23)

The owner asked for `SyncLink` to be **four modes and not a list of adapters** (`link_mode.dart`: `wired`,
`wireless`, `usb`, `tunnel`). For a stable release the question is which of them is *claimed*, and the answer
differs per mode because the evidence does:

| Mode | Implementation | Tests | Driven on real hardware |
| --- | --- | --- | --- |
| **wireless** | discovery (UDP broadcast), the reachable listener, tap-to-connect, the sealed exchange | `test/data/sync/`, `test/p3_acceptance_test.dart` (two screens, real cellars) | **yes** -- two physical devices, 2026-09-22 and again on 2026-09-23 (phone ↔ laptop, both screens reporting 同步完成) |
| **wired** | the mode selects the interface and address; nothing else is mode-specific | `test/domain/sync/link_mode_test.dart`, `test/ui/link_row_test.dart` | **no** -- this machine has one network and no second cable to plug into it. The mode is a promise about *which* interface is used, and what is untested is the promise, not the transport |
| **usb** | `data/sync/adb_carrier.dart`: `adb forward tcp:H tcp:D`, nothing else (`adb shell` is deliberately not run) | `test/data/sync/adb_carrier_test.dart` asserts the exact command line through an injected runner -- *"a test cannot have a phone plugged into it"* | **no** -- the carrier has never carried a real sync. Tethering (the other half of this mode) needs nothing new and is an ordinary LAN |
| **tunnel** | the mode, and the fact that discovery cannot cross it -- so the pairing code or a remembered key is the way in | `test/domain/sync/link_mode_test.dart`, `test/ui/link_row_test.dart`; the code and remembered-key paths are the same tested ones the wireless mode uses | **no** -- there is no tunnel on this machine to route through |

**The declaration for stable, in one sentence per mode**: wireless is claimed and verified on real hardware;
wired, usb and tunnel are **claimed as selectable modes with their logic tested, and explicitly not claimed as
hardware-verified**, because this machine cannot produce the second cable, the second phone or the tunnel. A
mode that is offered but has never carried a byte is stated here rather than discovered by a reader.

**And `.courtpack` is not one of those gaps any more.** It carries a cellar over a file rather than a network,
it is wired into the device section, and its round trip is covered by a test -- which makes it the one carrier
whose acceptance does not depend on a second machine at all.

**A third piece of the environment had to be understood to get that test to run**, and it is worth
recording because it looks like a hang in the sync rather than a property of the harness: a widget
test never yields to the event loop, so an exchange whose merge writes into a file **stops with
every frame already on the wire and neither side finishing**. The count of frames sent was the
evidence -- eight, including both `bye`s, and then silence. One `runAsync` turn between frames lets
the write complete, and the frame after it runs the continuation.

**The layering is what made this testable, and it was worth the discipline.** The exchange decides
everything a socket cannot be trusted to reproduce -- and because it takes lines rather than a
socket, its tests hand it an in-memory pair and complete instantly. Three real deadlocks were found
that way, in seconds, instead of as an intermittent hang on somebody's phone: a `bye` each side
waited for the other to send first, a readings loop that waited for a frame the peer would not send
until its own loop ended, and a readings frame that was never chunked while its decoder capped at
256 -- which broke the sync on exactly the cellars large enough to be worth syncing.

Verified: **1019 tests** under `flutter test`, of which the domain and data suites run on the plain Dart VM
-- which is the proof that neither imports Flutter. `flutter analyze` reports no issues.
(777 as of 2026-09-21; 1019 as of 2026-09-24, after the IBA drinks, the asset-drift guard, the adapter tests
and the colour-contrast assertions.)

**P4 is all three artifacts, and the acceptance is not the same as the artifacts existing.** Four
separate facts get conflated there -- built, installed, run, used -- and they have different answers
per artifact. `packaging/README.md` keeps them in separate columns; the state as of **2026-09-24**, on
**1.0.0.527 / 1.0.0.527 / 1.0.527**:

| Artifact | Built | Installed | Run | Used for real work |
| --- | --- | --- | --- | --- |
| Android APK | yes, by `packaging/android/build.sh`, three ABIs and receipted | **yes** -- 1.0.0.1014 on the handset, after a one-time uninstall because the signing identity is now S.M.Y.T. | **yes** | **yes** -- a bottle recorded on the device |
| Windows MSI | yes, by `packaging/windows/build.sh` | **yes**, 1.0.0.527 over 1.0.0.526, `exit=0` | **yes** | **read** -- the recipes screen of the installed build reads 共 103 条 with 35/33/35, photographed; a write on Windows is unverified |
| Linux AppImage | yes, by `packaging/linux/build_appimage.sh` | n/a, it is the executable | **yes**, under WSLg, software rendering | **read** -- photographed at 1.0.0.527; a write is unverified |

**Every row but one moved twice more since this table was first written, and always because something was
run rather than argued about.** The one that has not moved is Android, and the reason is a disconnected
handset rather than anything about the package: it is the last thing standing between `v1.0.0-rc.1` and
`v1.0.0`.

**The MSI's blocker was the host's, and a reboot cleared it.** Error **1604**,
`ERROR_INSTALL_SERVICE_FAILURE`, which this machine had produced on somebody else's installer too,
turned out to be a machine state and not a property of the package: after a reboot the installer
completed, and the artifact has since been **installed and started**. Nothing about the package was
ever in question, and `packaging/README.md` records both the blocker and its disappearance.

**The AppImage runs, and there is now a picture of it.** The earlier attempt failed twice by
photographing the Windows desktop and catching the browser in front of the WSLg window; the fix was
not to raise the window but to **stop photographing the desktop and capture from inside Linux**.
`packaging/linux/appimage-ui-wslg-x11-1280x720.png` shows the Cellar tab rendering -- both languages,
the palette, the tabs -- so the claim is now "the UI renders", which nothing here could establish
before.

**Running it also found a real defect, which is the strongest argument for running artifacts at all.**
Every Linux launch printed `GLib-GIO-CRITICAL: g_application_set_application_id: assertion ... failed`,
because the application id was dotless -- and it was dotless *because of the icon fix*, so the app had
been running with no application id at all. The two constraints turned out to be on two different
strings and are now two variables; the critical is gone and the window class is unchanged.

**The APK's success had to be re-established, not merely inherited.** It was demonstrated once, on a
build from 2026-09-20 17:59, and by the next morning 28 files under `lib/` were newer than that APK --
so the thing that passed and the tree were no longer the same program. It has been rebuilt from HEAD,
the bundle carries a `MANIFEST.txt` naming the source each artifact came from, and Android now has a
build script of its own, so the artifact that is verified and the artifact in the bundle stop being
two different things maintained by hand.

**And the APK is signed with a debug key -- which is now measured rather than asserted.** Read out of
the artifact: `CN=Android Debug`, SHA-256 `3c0068bc...82f1`, verdict **`DEBUG-SIGNED -- an installation
of this can never be updated`**. The mechanism for fixing that is in place (`android/key.properties`
drives a release signing config, `packaging/android/make_keystore.sh` writes the key,
`packaging/android/signing.sh` reads any APK's signer back, and the receipt records the fingerprint);
**the key itself is still a decision with an owner**, because a signing key is a long-lived secret and
minting one on someone's behalf is how an application ends up with an identity nobody can back up.

**P5 has started, and it started with the one adapter whose disclosure can be the strongest.** The row in
section 11.1 said the day one of these became real it would become its own class; on 2026-09-24 it did:
`LocalBartenderAdapter` in `lib/adapters/bartender.dart`, against a model on **this machine** at
`http://127.0.0.1:11434`, so that the sentence the screen composes from the adapter's own facts is not "we send
your cellar somewhere" but "that address is on this machine, so the request does not leave the device". The
registry did not change for it -- an implementation exists, `isAvailable` answers true, and the row in the
device section follows, which is what the declaration promised. The other two network adapters and the scale
are still declarations with their reasons beside them, off by default as section 11.1 requires.

**Why P0/P1 go first**: the Domain layer is the one part where an error is unforgivable, and it can be verified entirely without a UI.

**Pro (section 17) is not on the roadmap.** It is not a release milestone: **it does not go into releases**, but is a second download the user decides on inside the client, after the three platforms are installed. The roadmap ends here; Pro is what comes after it.

**And as of 2026-09-26 it belongs to the G edition rather than to this backlog.** The owner's reason is that what Pro needs overlaps substantially with what the G edition is already going to build, so carrying it as a Stable item was double-counting the same work. It is recorded in that edition's own list, and nothing in Stable waits on it -- which is the same separation section 12.10 makes for the two products themselves.

**Gamification (section 20) is not a milestone either, for a different reason.** The animated layer is asset-pack content and adds nothing to a release; the only part that belongs in the app is the rendering pipeline it draws through, which section 17.3 already accounts for. So the order is: **finish the sober app first, then make it worth looking at.** A gamified layer built before there are screens to gamify would be animating placeholders.

### 15.0 The harvested data is gone: deleted on 2026-09-22

| Gone | Was |
| --- | --- |
| `data/sources/` | the archived another source and one source harvests |
| `data/seed/seed.json`, `assets/seed/seed.json` | the artifact the application loaded |
| `lib/data/seed/{coupe_importer,mixel_importer,seed_merge,seed_names,seed_recipes,aliases,recipe_id}.dart` | the pipeline that turned one into the other |
| `tools/build_seed.dart`, `tools/seed_report.dart` | the entry points of that pipeline |
| their tests | the assertions about 502 recipes, three known problems and 71 name collisions |

**What survived, and why each:** `seed_codec.dart` and `seed_repository.dart` -- the JSON codec and the
in-memory model with its queries, which read *our* file now; `data/names/` -- our translations, which were
always ours; and `data/drinks/library.json`, the first-party library: 164 ingredients and the drinks we have
written so far (8, referenced against the IBA's list -- see 15.1).

**The format marker changed with the data**, from `hollow-court-seed` to `hollow-court-library`, and a file
carrying the old one is refused rather than read. That is the check doing its job rather than a formality: an
application that guessed at a document it does not recognise would show somebody a library that is not
theirs.

**Three things had to be rewritten rather than deleted**, and the difference matters:

* **The tests of the artifact** became tests of ours -- that every ingredient a drink names exists, that
  every stated `defaultUnit` is one this build can actually measure with (the invariant the unit
  recognition will stand on), that no two drinks share a canonical name.
* **The P1 walkthrough** was pointed at the Boulevardier instead of a harvested Adonis, and its numeric
  literals were replaced by relationships: a bottle's remaining volume is `700 ml − its own share`, computed
  from the drink, because a literal is an assertion about one recipe's arithmetic that starts lying the day
  the recipe changes.
* **The "recipe with no method cannot be mixed" test** now *constructs* a methodless recipe. It used to find
  one in another source's data, where the method lived in a hashtag inside the steps -- and a rule about mixing should
  not depend on somebody's library having a hole in it.

**A one-line casualty worth recording:** the role of `recipe_id.dart` (hashed rather than counted ids) is
still explained in the comments where it is cited, but the file is gone with the pipeline that needed it.

### 15.1 The first-party drink list, referenced against the IBA's, and why the seeds cannot ship

**They are right, and section 15 already said so from the other side.** The two harvests are *personal
collections*: a recipe named `Adonis` in one and `Adonis` in the other is not one formula recorded twice but
two authors' versions, and 70 of the 71 overlapping pairs differ in their ingredient lines. That is fine as
study material and wrong as a shipped library -- which is why the seed is a git-ignored artifact with a hard
compliance gate in front of it.

**The reference is the IBA's official list, not Wikipedia.** `en.wikipedia.org` is unreachable from this
machine (`web_fetch` declines it: the name resolves to a non-public address), so the reference used is the
International Bartenders Association's own list at
[iba-world.com/cocktails](https://iba-world.com/cocktails/all-cocktails/) -- which is what Wikipedia's list
is *about* anyway: ~100 drinks in three groups (The Unforgettables, Contemporary Classics, New Era).

**And the licence line is the reason the text is ours.** That site carries "© IBA - All rights reserved". A
drink's name and its standard proportions are facts, and a reference to them is legitimate; the prose that
tells somebody how to make the drink is writing. So:

| | What we take | What we write |
| --- | --- | --- |
| Names | the canonical list | the Chinese and Japanese names |
| Measures | the standard proportions | -- |
| Method, glass, garnish | the standard practice | **the instruction text** |
| -- | -- | the schema, the ids, the tests |

**`data/drinks/iba-official.json` is that list, and it uses the seed's schema on purpose**: `id`, `name`,
`glass`, `ice`, `method`, `methodSteps`, `items[{ingredientId, amount, unit, role}]` with amounts in base
units (45 ml is `45000` microlitres). One codec reads both, so replacing the seed for release is a data
change rather than a code change -- which is what section 15 says has to be possible before this project can
be released at all.

**It began with eight drinks** (Alexander, Americano, Aviation, Bee's Knees, Bellini, Black Russian,
Bloody Mary, Boulevardier) and grew in tranches; as of 2026-09-23 it holds **103**, which is every drink on the
IBA's three category pages that could be read from its own page, plus the four-language names and instruction
text for each. The count is still the measure: the file is the deliverable, and it grows by writing rather than
by harvest.

**The tranche that closed the gap was found by cross-checking, not by counting.** A comparison against Chinese
Wikipedia's IBA list showed sixteen drinks the library did not have; fifteen were added (Old Fashioned, Whiskey
Sour, Sazerac, Sidecar, White Lady, Stinger, Tuxedo, Vieux Carré, Rusty Nail, Planter's Punch, Porto Flip,
Paradise, Ramos Gin Fizz, Golden Dream, Yellow Bird) and **the sixteenth was refused**: that list still marks
*Barracuda* as official, but the IBA removed it in 2024 -- `iba-world.com`'s page for it now 404s and the
English article carries no official recipe, while the Italian article records `Estromissione = 2024` citing the
AIBM Project's *IBA Official Cocktails 2024*. Adding it would have put a de-listed drink in a list that claims
to be the official one. The per-drink record is in `docs/reference/iba-cross-check.md`.

**[defect, 2026-09-23, reported by the owner] 名字翻译齐了，界面一处也没问过它。**
`data/names/names.json` 早就有全部 88 份酒与 187 份原料的 zh-Hans / zh-HK / zh-TW / ja 名字，连步骤都齐，
而**配方页画的是 `recipe.name`——种子的英文**：那张表在那一页只被问过「步骤」。三个面一起坏：

- **配方**列表与详情标题写英文（`recipes_page.dart`：`Text(recipe.name)` 两处）；
- **配方详情里的原料行**写英文（`ingredientById(...)?.name`），而**酒桌那一侧（酒窖页）本来就翻译了**——
  同一份数据在两个页面用两种写法，这是这条缺陷最容易看漏的地方；
- **原料选择框**：`displayStringForOption` 画英文，而 `_namesOf` 早就把译文加进了搜索词，
  于是**用中文搜得到、行上写英文**——owner 的原话就是这个不对称。

**顺带三处同类：** 「要买什么」列的是 `entry.ingredientId`（连英文都不是，是 `sweetVermouth` 这样的键）；
配方列表按**英文名**排序，而屏幕上没有英文；瓶子的编辑表单里那颗原料名预填的是英文。

**修法与防线。** 显示一律走 `SeedNames.nameFor`（字面量 key 与库 id 一一对应，88/88、187/187 都覆盖），
排序也按屏幕上那个名字；`test/ui/translated_names_test.dart` 把三个面各钉一条（列表、详情原料与步骤、选择框），
`test/data/seed/seed_translation_coverage_test.dart` 守住数据本身：四语齐全、且译文不得等于英文
（后者很容易被「覆盖测试」放过——回退链的终点正是英文）。

**这一条值得单独记下来的原因**：它不是漏译，而是**没人去问那张表**。屏幕上看不出来——
缺翻译与没去取翻译长得一模一样。

**2026-09-23（同日续）：按 owner 的指示「保证所有语言都有完整翻译，并用网络信息做校对」做了第二轮。**

三件事，按「查得出证据」的顺序：

**一、先量，再改。** `tool/l10n_status.dart` 原来只数 `theme.dart` 的 CopyLine 与饮品步骤——而「名字」与
「单位」在另外两个文件里，正是那两处没被数到的地方。现在它一次答三问：界面文案 240/240、步骤 88/88、
**名字 88+187**、**单位 26**。加完立刻抓到 26 个单位里有一个（吧勺）只有三种语言——反过来说明「完整的定义
取决于你数了哪些文件」。

**二、`names.json` 的港繁／台繁此前是「简中经 OpenCC 生成」**，与 §12.4.1 对界面文案的判断一样，而名字这一
份从未做过措辞复核。复核用的是**中文维基自己的转换表** `Module:CGroup/Food`（大陆／台湾／香港／澳门并列，正
是维基转换餐饮条目用的那一张），逐条比对后改了 17 处地区词，其中最要紧的是：

| 条目 | 改前（简中转繁） | 维基给的地区词 |
| --- | --- | --- |
| cherry | 港繁 櫻桃 | **車厘子** |
| gin | 港繁 金酒 / 台繁 金酒 | **氈酒** / **琴酒** |
| chocolate | 港繁 巧克力 | **朱古力** |
| iceCream | 港繁 冰淇淋 | **雪糕** |
| lime | 台繁 青檸 | **萊姆** |
| orangeJuice | 台繁 橙汁 | **柳橙汁** |
| pineapple | 台繁 菠蘿 | **鳳梨** |
| tonicWater | 台繁 湯力水 | **通寧水** |
| mojito | 台繁 莫吉托 | **莫希托** |
| cream | 港繁 奶油 / 台繁 奶油 | **忌廉** / **鮮奶油** |

**三、机器转换会把「字」当「词」改**，这一类与地区词无关、在任何语境下都错，所以先修：`干`（dry）被转成
`幹`（幹活）→ 干马天尼 成了「幹馬天尼」；音译里的 `里` 被转成 `裏` → 蒂珀雷里 成了「蒂珀雷裏」、代基里 成了
「代基裏」。owner 举的例子正好指出第三种毛病：**同一个英文词在同一份文件里被译成两种中文**——Daiquiri 在这
一条里是「得其利」，在 Don's Special Daiquiri 里却是「代基里」。以中文维基条目名 **黛綺莉**（`黛绮丽` 是它
的重定向，两种写法都成立）为准统一，简体沿用 owner 给的「黛绮丽」。

**复核工具与它的边界。** `tool/seed_name_audit.py` 把这次的做法固化下来：走本机代理取维基的转换表与跨语言
链接，输出三类结果——① 机器转换陷阱（可自动判定）、② 维基转换表不一致（可判定）、③ **同名条目候选**（只报
不改：*Zombie* 的跨语言链接是「喪屍」，*Bramble* 是「悬钩子属」，照抄会把酒名改错）。前两类现在都是 0，
第三类 73 条留给人工看，工具自己写明这一点。

**这台机器的一个事实，值得单独记下来**：`zh.wikipedia.org` 的 DNS 被指向 `2001::1` 与一个 Twitter 段地址，
直连必失败；本机出网一律经 `127.0.0.1:10090` 代理，加 `-x` 之后维基正常可达（200）。凡是要用网络做校对的
活儿，都得走这条路。

**[核对，2026-09-23] 与中文维基《IBA 官方鸡尾酒列表》逐条对表的结果。** 详表见
`docs/reference/iba-cross-check.md`，三语参照数据见 `docs/reference/iba-official-wikipedia.json`：

1. **改掉 83 处名字（32 款酒）**，原则是**分地区**：那张表是 zh-hant 条目，`zh-Hans` 列常常只是台港用名的
   字形转换（`柯梦波丹`、`凤梨可乐达`），所以台港改、大陆保留（`大都会`、`椰林飘香`、`皮斯科酸`）。
   官方的 `noteTA` 也证实了 `马丁尼` 的两种写法：`zh-cn:马天尼 / zh-hk:马天尼 / zh-tw:馬丁尼`。
2. **发现库缺 16 款官方酒**（含 `Old Fashioned`、`Whiskey Sour`、`Sazerac`、`Sidecar`、`White Lady`）：**15 款已补进库**（库规模 88 → 103），第 16 款 `Barracuda` 查证后**拒绝收录**——IBA 已于 2024 年把它移出官方名单，中文维基那张表是滞后信息。
   **补齐是内容工作而不是翻译工作**（每款要计量/技法/杯型/装饰，且按本节规矩做法文字必须我们写），
   等 owner 决定后再单独做。
3. **本地模型那一轮（88 酒 + 187 原料）只筛出 1 条真缺陷**（`Rabo de Galo` 误作「鸡尾」→「公鸡尾」），
   其余 61 条标记被逐条否掉。**这再次确认了分工：术语与地区词以可比对的来源为准，模型只做筛查信号。**

### 14.1 Stable first, and the size budget that follows from it

Stated plainly because it is a priority rather than a technical fact: **the gamified direction is a personal preference of the author's**, and the project's original intent is a cellar -- an application for keeping track of what is in the cupboard and what can be made from it. So the order is not negotiable even though the enthusiasm is real:

1. **A stable release**, installable and useful on all three targets.
2. **Then** the gamified layer, as a second download the user chooses.

**The stable release still contains the character, and she is not a compromise in it.** She is not part of the optional layer and she is not something to be trimmed when the budget gets tight. Section 20.5 already describes her as present rather than performing, and presence lives in **copy, typography and colour** -- the things that make an application feel like somebody made it rather than assembled it. What waits for the second download is only the *implementation* of her: the rig, the expressions, the animation. **The character is the aesthetic core, and the aesthetic core does not wait for a download.**

**The budget is a hard constraint, not an aspiration.** The reason is specific: a gamified base package starts at **500 MB and often reaches 1 GB**, and that number is paid by every user to obtain a function the project does not need in order to work. So:

| | Stable release | Opt-in second download |
| --- | --- | --- |
| The character | her voice in the copy, her name in the typography, the palette | the rig, the expressions, the animation |
| Feedback | layout, colour, text, static art | springs, particles, sound design |
| 3D | none | the shaker, the shelf simulation |
| Locales | the shipped set, one bundle each (section 12.4) | further locales if ever needed |
| Target size | **tens of megabytes** | hundreds of megabytes, by choice |

**The aesthetic core stays in the stable release**, and that is why the table's first row is first. Section 20.3's soft register, the palette, the voice and the restraint are not garnish on a boring app -- they are what makes it this app rather than a spreadsheet, and none of them costs an asset pack.

The practical consequence for the roadmap: **nothing in P0 through P4 depends on section 20**, and work that only serves section 20 is deferred behind them. That includes the 3D pipeline study, which is research for a layer that is not on the stable path -- see `an earlier survey`.

---

### 14.0.3 The Bar cannot do its job yet, because every ingredient looks the same (2026-09-26)

**The owner's report, in his words**: 「吧台」目前比较鸡肋，因为原料的图标全部都是一样的，吧台没办法发挥出其作用。

**What was checked, and what it found.**

- `lib/domain/` carries **no icon, glyph or artwork field** on a bottle or on its SKU: the domain models what a bottle
  *is*, not what it looks like.
- `lib/ui/bar_page.dart` does its job -- it draws the shelves, stands bottles where the log says they were put, and
  cross-checks every placement against remaining volume so a poured-away bottle is named rather than drawn.
- The drawing itself is `_Bottle`, and what reaches it has **nothing distinguishing to be drawn from except the fill**.

**Which is why the bar is 鸡肋.** A shelf is a spatial answer -- *where is the vermouth* -- and it can only give that
answer if the reader can tell one bottle from another **at a glance**. The acceptance criterion P1 was held to was
liquid colour rendering, and colour alone cannot carry a shelf of thirty bottles: two ambers look alike, and so do three
clears.

**The consequence is not confined to the Bar.** The same missing distinction is what a shelf, a shopping list and a
recipe's ingredient line all lean on, so whatever supplies it should be a fact about the ingredient rather than a
property of the page that happens to need it.

**Not decided here**: whether the answer is per-ingredient artwork, per-category shapes, a monogram, or a generated
pattern. **Recorded as a defect with its cause rather than as a solution with a guess.**

## 15. Seed data

| Source | Recipes | Ingredients |
| --- | --- | --- |
| another source web version (official IBA) | 88 | 139 entries |
| one source (obtained by reverse engineering) | 414 | 142 |
| **Total (merged, but not deduplicated)** | **502** | - |

**The overlap is measured, and the measurement says not to deduplicate.** 71 of the 502 recipes are named in both sources -- 71 of another source's 88 -- and of those 71 pairs **only one has identical ingredient lines.** The other 70 are different formulas rather than one formula recorded twice:

| How they differ | Example |
| --- | --- |
| Units and proportions | `Alexander` is one ounce of each in one source and thirty millilitres in the other |
| A different ingredient for the same drink | `Aviation` uses maraschino liqueur in one and cherry liqueur in the other |
| A different number of lines | `Barracuda` has four lines in one and seven in the other -- garnishes one source records and the other does not |
| A different form of the same thing | `Bellini` is built on peach in one and peach purée in the other |

**A name is therefore not an identity.** Deduplicating by name would delete 70 recipes somebody wrote down on purpose, and the two sources disagreeing is exactly what having two sources is *for*. What the overlap calls for is **grouping rather than merging** -- showing both formulas under one drink and letting a person choose -- which is a decision for a screen rather than for an importer. `SeedRepository.nameCollisions()` carries the number so it cannot be forgotten, and a test asserts all four kinds of difference above.

**One consequence for the ingredient layer.** Because the two sources differ in units, the same drink can carry different amounts from each -- so the seed's ingredient ids have to be stable across the pair, which is what the alias table of section 15.1 is for.

**Compliance statement (must be retained):** copyright in the two batches of data above belongs to their original authors; this project archives them solely as a **personal study and design reference**. If this project is released publicly, the seed recipes must be written independently or replaced with openly licensed sources, and the data of others must not be redistributed directly. This is a hard gate before release.

Full records of both reverse-engineering efforts are in an earlier survey.

**The records go into git, the data does not** -- the two carry different copyrights. Method, pitfalls and the shape of the data at the time are this project's own knowledge; the recipes and entries are someone else's work. Therefore:

| | Location | In git |
| --- | --- | --- |
| Reverse-engineering records | an earlier survey | **in git** |
| Extracted data | `data/sources/` | not in git (already excluded by `.gitignore`) |
| Original application packages | `E:\DaShaoHuo\downloads\` | not in git |

### 15.1 The seed is built, not committed

The library the app loads is produced by a pipeline in `lib/data/seed/`, and the artifact it produces is git-ignored for the same reason the sources are. A fresh clone has no seed until `dart run tools/build_seed.dart` is run; the code that builds it goes in git and the artifact does not.

| Layer | What it does | Why it is separate |
| --- | --- | --- |
| `mixel_importer.dart`, `coupe_importer.dart` | read one source each, losslessly, and report everything they cannot resolve | an importer must not have to know what the other source called something |
| `seed_names.dart` | id minting, accent folding, and the trailing-qualifier split | both importers mint ids and **the merge depends on them minting the same one** |
| `aliases.dart` | the canonical ingredients, and the spellings each absorbs | **every entry is a claim somebody can disagree with** -- that Plymouth gin is gin, that Calvados is apple brandy -- so they are listed rather than produced by a transform |
| `seed_merge.dart` | reconciles the two id spaces, counting table claims and rule applications apart | a merge that silently drops a name is worse than no merge |
| `recipe_id.dart` | section 4.4 ids: a slug, then five digits | an id the source chose survives a re-export and a minted one does not |
| `seed_recipes.dart` | assembles `Recipe` objects | the only layer that has to know about all the others |
| `seed_codec.dart`, `seed_repository.dart` | the versioned on-disk format, and what the rest of the app asks it | **no file system in either**, so the round trip is testable without a disk |

**The alias table exists because the two sources disagree about names and neither is wrong.** 295 minted ids reconcile to 164 substances, 90 of them named by both sources. Two mechanisms do it and they are counted apart on purpose: an entry in the table is a claim a person wrote and can argue with, and the trailing-qualifier rule is arithmetic that applies to every spelling at once -- one source appends a qualifier in parentheses (`Vermouth (Dry)`) and another source appends one after a comma (`gin, Plymouth`).

**And the rule's precedence is the part that needs care.** `lime, juice of` strips to `lime`, which is also an ingredient and the wrong one, so a direct spelling is tried before the rule. A test asserts that, and three others guard the ways this merge could go wrong quietly: a citrus fruit is not its juice, a liqueur is not the fruit it was made from, and the two spellings of crème de menthe stay apart.

---

## 16. Shaking simulation (Android)

### 16.1 Conclusion first: no rigid-body simulation at runtime

"Model the shaker + simulate the ice" -- the first half is right, the second half needs changing. **There is no need to simulate rigid-body collisions of dozens of ice cubes on a phone**:

1. **Performance**: 50-100 rigid bodies plus fluid coupling cannot hold up frame rate, heat and battery together.
2. **The real output is not where the ice cubes are**, but two numbers: **dilution** and **final temperature**.
3. And those two numbers do not depend on the specific positions of the ice, only on **agitation intensity**.

The standard is explicit: by IBA rules, shake 10-15 seconds, dilution **20-25%**, final temperature landing around **-5 C**. Get these numbers right and the drink is right.

### 16.2 Three-layer architecture

**Layer 1 - sensors**
`sensors_plus` reads the accelerometer (Android can reach 100 Hz+). Shaking detection uses peak detection plus band-pass filtering; a real person shakes at **3-4 Hz**, with clean features.
Output: frequency `f` - amplitude `A` - duration `t` - stability `sigma`.

**Layer 2 - physical model (the soul)**

```
dilution% = g(f, A, t, ice mass, ice temperature, starting liquid temperature)
T_final   = h(f, A, t, ...)
```

From this grows a genuinely meaningful judgement:

| Shaking style | Result |
| --- | --- |
| Shaken too lightly | Insufficient dilution, drink too strong, not cold enough |
| Shaken just right | 20-25% dilution, **perfect** |
| Shaken too long | Over-diluted, watery |

**This is exactly the missing link in comparable software** -- they treat shaking as an animation; we turn it into a measurable physical process.

**Layer 3 - visuals (tiered)**

| Approach | Look | Cost |
| --- | --- | --- |
| Embedded Unity (UaaL) | Best | Package +50 MB and up |
| Native Flutter 3D | Medium | Early ecosystem |
| **2.5D: Blender pre-render + shader** | Good | **Lightest** (base version) |
| **Hand-written lightweight 3D** (with Pro assets) | Good | Medium (Pro) |

What is special about the shaking scene: **the line of sight points at a single tin**, a limited viewing angle. So Blender renders sprite atlases from several angles, and at runtime a shader handles rotation, displacement and liquid turbidity; that is enough visually.

### 16.3 Division of labour among local 3D tools

**Blender -- modelling and baking**
- Build a Boston shaker (tin + glass, both parts) and ice cube models -> glTF
- Bake PBR textures for the metal tin body, glass and ice
- Render ice sprite atlases (multiple angles - multiple states)
- Run rigid-body simulation to produce **reference data**

**Unity -- an offline physics laboratory, not a runtime**
- Run true ice rigid-body collisions with PhysX (its home turf on desktop)
- Export **reference curves** for "shaking parameters -> dilution rate / final temperature"
- Used to **calibrate** the lightweight runtime model

**In a word: Unity as laboratory, not as runtime.** Section 20.2 reaches the same conclusion for the gamified layer, and for the same reason -- the engine authors content, it does not ship inside the app.

### 16.4 The real constraint is power draw, not performance

A flagship phone **can** run rigid-body physics for a few dozen ice cubes. The problem lies elsewhere:

- Five minutes of shaking simulation -> the body heats up -> **thermal throttling** -> frame rate cliff -> the experience gets worse, not better
- Compute at full tilt -> battery drains faster than the drink goes down

**So this is not "can it run", but "how long can it run, at what cost".** The right answer is not to separate good phones from bad ones, but **capability tiering + dynamic degradation**.

### 16.5 Device capability tiering and dynamic degradation

A one-time static determination is not enough -- the fate of mobile is thermal throttling, so it must be adjusted while running:

```
sample every 2 seconds:
  fps < 45  or  thermal status >= MODERATE            ->  drop one tier
  fps > 58  and  thermal status = NONE for 30s steady ->  step up one tier
```

| Tier | Basis | Shaking implementation |
| --- | --- | --- |
| **T0** | No gyroscope - GLES < 3.0 - RAM < 3 GB | 2.5D sprites + simplified physics |
| **T1** | Mainstream devices | instanced lightweight 3D + simplified physics |
| **T2** | GLES 3.2 / Vulkan - RAM >= 8 GB | true 3D + lightweight rigid bodies |
| **T3** | User explicitly enables "performance mode" | full rigid bodies, **heat accepted voluntarily** |

T3 is a door left open for high-end and modified devices (root, overclock, external cooling, plugged in) -- **we do not judge on the user's behalf whether their device can take it, we only provide the switch and let them weigh it themselves.**

The probe points are all stock system facilities: `getDeviceConfigurationInfo()` (GLES version) - `getCurrentThermalStatus()` (Android 10+ thermal status) - `Sensor.getMaxDelay()` (sensor sample rate) - `MemoryInfo` (available memory).

### 16.6 Risks

- Android sensor sample rates, permissions and vendor variation
- Feel tuning -- the most time-consuming part, requiring repeated trials on real devices

### 16.7 Contact between two animated bodies is a constraint, not a keyframe

16.1-16.6 is one body and one tin. The moment two **rigged** bodies share a frame --
section 20's character paired with anything -- a failure appears that no amount of
animation polish fixes: **interpenetration**, two surfaces passing through each other.

**Why it cannot be fixed in the animation data.** A clip records *where bones go* and
nothing about *what they must touch*. Read off a shipping release
(`an earlier survey`), a clip's entire schema is `loop` - `animation_length` -
`bones -> channels -> {time: value}`. There is **no contact field**, so contact is
authored by hand, in one shared frame, for **one specific body** -- and no tool can
check it. Change any input the animator did not have (a body parameter, a height, a
scale) and the alignment is silently wrong.

**Three layers move the surface, and not one of them forbids intersection:**

| Layer | Moves | Owned by |
| --- | --- | --- |
| Pose | the base skeleton's bones | the animator |
| Deformation | the surface, away from that skeleton | the model author; valued by the user |
| Simulation | dynamic parts, per frame, against **its own collider set** | the engine |

The visible defect is the intersection of two *simulation-layer* surfaces. A pose fix
cannot repair a deformation mismatch, and neither can repair a collider set that omits
the partner.

**Four failure modes, each with a signature, so diagnosis is by elimination:**

| Mode | Mechanism | Signature |
| --- | --- | --- |
| 1 | the pose was authored intersecting | clips even at the reference body with physics off |
| 2 | body parameters differ from the authored reference | clips only when the parameters differ; clean at the reference |
| 3 | the solver has no collider for the partner | clips only on physics-driven parts; clean with physics off |
| 4 | interpolation between clean keys crosses through | clean **on the keyframes**, clips in between |

**The rule for this project: never bake contact into keyframes.** Record contact as
*intent* -- which point of A is meant to touch which surface of B, to what tolerance --
and solve it against the **deformed** surface. A solver working from the base skeleton
is solving a problem nobody sees. Two corollaries: declare the reference body in the
file, or the animation can only be admired and never validated; and keep exactly one
soft-body convention per build, because two means two ways to forget.

**It is measurable, so it is a budget rather than an opinion:**

```
penetration(f) = max over vertices of A of  max(0, -signed_distance_to(B))
clip_metric    = max over frames of penetration(f), and the frame it happens on
```

Implemented, with a self-test that builds four synthetic scenarios -- one per mode --
and checks each against a closed form: `tools/penetration_probe.py` (currently PASS at
~2 mm tolerance against ideal-sphere values). Full argument, evidence and the four-pass
experiment: `an earlier survey`.

**Where 16.3 earns its place.** The metric needs both rigs in one scene with evaluated
deformation, and the re-solve needs a DCC. The division of labour in 16.3 was written
for one shaking tin; this is the second and harder consumer of the same pipeline.

---

## 17. Pro module and asset packs

### 17.1 Position: Pro does not go into releases

**Pro content is not shipped with the installer.** The user installs the base version first (the three-platform artifacts of section 14), and decides **inside the client** whether they want that extra layer of image quality and precision, then downloads it again from GitHub.

Three reasons:

- **Package size**: PBR textures and glTF models run to tens of MB (section 17.4). Cramming them into the installer makes people who cannot use them pay the size on behalf of others.
- **Devices**: the T2/T3 of section 16.5 require GLES 3.2 / Vulkan and >= 8 GB RAM. Installing onto a machine that cannot run it is pure waste.
- **Right to judge**: section 16.5 has already set the tone -- **we do not judge on the user's behalf whether their device can take it, we only provide the switch**. Whether to download is the first layer of that switch.

The base version is **complete and usable** on its own: shaking, dilution rate, final temperature, stock, recipes, match score and sync are all present. Pro only swaps image quality and precision, never features.

> **Where this contradicts the old plan**: this section previously said "distribute over the section 10 LAN, render on the computer and let the phone fetch it by QR code, **no store listing, no network, no registration**". With the change to GitHub, **network access becomes mandatory**. That is the price this revision pays, stated in the open rather than glossed over. Accordingly, downloading must hang under the section 11.1 network adapter layer and be **off by default**, consistent with the "offline-first" position.

### 17.2 Hard limits: what may and may not be downloaded

**Draw the line first, then discuss the plan.**

| Platform | Can it download and execute code |
| --- | --- |
| **iOS** | **Flatly forbidden** (App Store review 2.5.2) -- data and assets only |
| **Android** | Technically possible (`DexClassLoader` / `dlopen`), but restricted by Play policy, and a classic malware technique |
| **Flutter** | AOT compiled; Dart code **cannot be loaded at runtime** |

**So the second download carries assets only, no code.**

This is no compromise, because **the heavy things were always assets**: the hand-written lightweight 3D pipeline stays in the base app (section 17.3), and it is small -- small precisely because it is our code; what is big is the models, textures and calibration curves. **Engine carried along, content fetched on demand.**

**Native libraries (dlopen) are explicitly rejected.** It is technically possible on all three platforms, and that path is not constrained by app stores either (this project distributes APK / MSI / AppImage directly). But its substance is "fetch a piece of executable code from the internet and run it on the user's machine". That contradicts the risk position of section 18, and the only gain is a few MB of package size. **No half-open doors.**

### 17.3 What stays in the base app

**Built into the base app** (stable - lightweight - consistent across three platforms)
- The hand-written lightweight 3D rendering pipeline. Its technical foundation is Flutter's own `Canvas.drawVertices()` (triangle mesh submission) and `FragmentProgram` (GLSL shaders) -- **no Unity needed, and no third-party 3D library either**
- The shaking physical model (section 16.2 layer 2): **dilution rate and final temperature. This is the product's true output (section 16.1) and must be in the base app**
- 2.5D base visuals (section 16.2 layer 3): Blender pre-rendered multi-angle sprite atlas + shader

**Conclusion**: without Pro you can still shake a drink completely and get the correct dilution rate and final temperature. The only differences are that the tin body lacks that sheen, the ice lacks refraction, and the calibration curves degrade to generic values.

### 17.4 Pro asset pack

| Content | Estimate |
| --- | --- |
| Boston shaker model (tin + glass) glTF | 1-3 MB |
| Ice cube models (several shapes) glTF | < 1 MB |
| PBR textures (metal / glass / ice) | 10-30 MB |
| High-precision physical parameter tables (Blender/Unity calibration curves) | < 1 MB |
| Enhanced shader parameter set | < 100 KB |

**Pro's selling point is "image quality and precision", not "feature switches".**

**Distribution form**: published as a **GitHub Release asset independent of the application version** (versioned archive + SHA-256), separate from the application's own release. The two evolve independently -- when the app ships 1.2, the asset pack may still sit at 1.0.

**Client behaviour**:

- **Not downloaded by default.** The entry point is in settings, stating the size and the required device tier (section 16.5 T2/T3), so the user can weigh it themselves.
- Goes through the section 11.1 network adapter layer: resumable, cancellable, deletable.
- **Enabled only after SHA-256 verification**; a failed check discards it and reports an error, with no "use it first and see".
- Origin and version are recorded and visible in the interface -- users have the right to know where the extra things on their machine came from.
- **Everything works as usual without the Pro pack**: no prompts, no nagging, no degradation warnings.

### 17.5 Alternative: build variants

If a separate renderer (such as Unity) is genuinely needed some day:

```
hollow-court-lite.apk   (~30 MB, default)
hollow-court-pro.apk    (~80 MB, includes native libraries)
```

The nature of this is **reinstallation**, not download -- the native libraries are **inside the package** here, with no runtime code fetching, so it does not conflict with the line drawn in section 17.2. Android's official elegant solution is Play Feature Delivery, but it covers Android only and requires listing on Play -- conflicting with this project's position. **Therefore: asset packs primary, variants as backup.**

---

## 18. Known risks

| Risk | Description | Countermeasure |
| --- | --- | --- |
| **Manual table drift** | one source evidence: enums defined but never validated, `rum`/`gin` mixed in lowercase, units mixed into `Single` | **Enforce schema validation on write**; seed import also passes the validator |
| **Android background keepalive** | Acting as host on a phone requires a foreground service + battery whitelist + multicast lock | Android is explicitly positioned as a **follower**, not a host |
| **AP client isolation** | Enabled by default on many routers, P2P does not work | QR code and file exchange as mandatory fallbacks |
| **Unit semantic ambiguity** | dash/barspoon have no standard | Calibratable + explicitly labelled as estimates |
| **Younger Dart ecosystem** | Uneven plugin quality | Domain layer has zero dependencies, platform capabilities are concentrated in `platform/` for easy replacement |
| **Supply chain of Pro asset packs** | Fetching assets from GitHub means a repo or account could be taken over and assets replaced | Enabled only after SHA-256 verification; origin and version visible; **assets contain no executable code (section 17.2)**, so the worst case is wrong image quality, not a controlled machine |
| **GitHub reachability** | Pro needs network, and GitHub is reachable from this machine in practice but fluctuates | Download failure blocks no feature; a route of **manual download then local import** remains, i.e. the old LAN/sideload method still stands |

---

## 19. Audio production (evidence-based)

### 19.1 Capability matrix (all measured, not speculated)

| Capability | Tool | Status |
| --- | --- | --- |
| **Pure synthesis** (procedural SFX) | `numpy` / `scipy` / `soundfile` | YES -- three versions of ice dropping into a glass delivered |
| **VST3/VST2 headless driving** | `dawdreamer` 0.9.0 | YES -- Serum produced sound (2397 parameters), effect chain runs |
| **FLP read/write** | self-patched `pyflp` -> `tools/flp_io.py` | YES -- triple verified, byte-level match |
| **Wwise offline** | `WwiseConsole` v2024.1.14 | YES -- full CLI, projects can be created |
| **FL Studio GUI** | - | NO -- no command-line entry point, manual |

### 19.2 Three key pitfalls (all already hit and solved)

1. **The inputs to `dawdreamer.load_graph` are "name strings", not processor objects.**
   ```python
   engine.load_graph([(play, []), (shim, [play.get_name()]), (lim, [shim.get_name()])])
   ```
   Passing objects yields the inscrutable `Something was wrong with the list of inputs.`

2. **`PlaybackProcessor` requires a two-dimensional float32 array of `(channels, samples)`.**
   A mono WAV reads in as one-dimensional; it must be explicitly promoted, otherwise `set_data` errors.

3. **`pyflp` 2.2.1's `EventEnum` is an empty base class**, while CPython's `enum.Enum.__new__`
   **raises before `_missing_`** when `_member_map_` is empty (enum.py:1116), so parsing
   necessarily fails. Countermeasure: stuff in a placeholder member after import (use 1000,
   since FLP event ids are u8).
   The patch is fixed in `tools/flp_io.py` and must run in a Python 3.11 environment.

### 19.3 Sound design orientation: "dry" for interaction, "wet" for atmosphere

The same ice cube dropping into a glass, two paths:

| Version | Parameters | Use |
| --- | --- | --- |
| **Dry** (pure synthesis) | - | Interaction feedback: tap an ice cube into the glass, it must be **crisp** |
| **Restrained wet** (Shimmer wetDry .22) | feedback .45 / size .72 / lowCut .50 | Near-field atmosphere |
| **Heavy wet** (Shimmer wetDry .35) | feedback .60 / size .80 | Far-field bed |

Measured spectrum: the dry sound's five partials separate and disperse within 1.5 s; the heavy wet spreads energy across a full 5 s,
the partials combed into one mass -- **the sense of space comes through, but the dry sound's "crispness" is covered by fog**.
So interaction sounds should take the restrained setting; heavy wet is for the atmosphere layer only.

### 19.4 Wwise's position: the bridge is built, but it does not join the main chain yet

`WwiseConsole` offers 11 operations (`create-new-project` / `tab-delimited-import` /
`generate-soundbank` / `execute-lua-script` / `waapi-server` ...), **fully scriptable**.

But its output is **SoundBank**, which needs the Wwise runtime to play, and Wwise has **no official
Flutter integration** (only Unity / Unreal / hand-written C API). To run it in Flutter you would wrap
the C++ SDK with `dart:ffi` -- a large undertaking.

**Conclusion**: SFX production goes through `dawdreamer` + VST3 (output is directly WAV, played directly by Flutter).
Wwise stays as a **future interactive-audio alternative** -- should a need like "shaking intensity driving
filters and reverb in real time" ever become central, revisit FFI integration then.

### 19.5 Audio assets available on this machine

```
Serum - Sylenth1 - DUNE 2 - Nexus - Omnisphere - Keyscape - Trilian - Cyclop
Valhalla nine-piece set (Shimmer - Supermassive - Room - Plate - UberMod ...)
FabFilter full family (Pro-Q 3 - Pro-L 2 - Pro-MB - Saturn 2 ...)
iZotope Ozone 9 / Nectar 3 / RX 8 - Unfiltered Audio full set - OTT - Sausage Fattener
VOCALOID5 VSTi - Kontakt 7 - Addictive Drums 2 - FL built-ins (Harmor - Sytrus - Sakura ...)
```

FL built-in plugins can only be used inside FL (GUI), so they are manual; the VST3/VST2 batch is driven by scripts.

---

## 20. Gamified visual feedback and the character

### 20.1 Why this is not decoration

Drinks culture skews young, and a large part of that audience arrived through
games rather than through bars. To them a shelf is not a table and a pour is not
a number: **the feedback is the product experience.** Section 16.2 already turns
shaking into a measured physical process; this section is about making that
process something you can watch.

**A rule first, because it is easy to get wrong: gamification is feedback, not
gating.** Nothing here may be required to mix a drink, and nothing here may be
the only way to learn a fact. An animation that hides a number is worse than no
animation at all.

### 20.2 Unity stays a laboratory, not a runtime

Section 16.3 concluded that Unity is an offline physics laboratory. That holds
here too, and for the same reason -- runtime cost, not capability.

| Approach | Look | Cost |
| --- | --- | --- |
| Unity embedded (UaaL) | best | package +50 MB, in **every** install |
| **Unity offline, baked to assets** | good | **package unchanged** |
| Build variant carrying Unity | best | a separate download and a reinstall (section 17.5) |

**So: author in Unity, ship assets.** Models, rigs, animation and physics are
built and baked in the engine, exported as glTF plus baked animation data, and
drawn at runtime by the app's own lightweight pipeline (section 17.3). Nothing
executable is downloaded (section 17.2 -- no half-open doors) and the base
package does not grow (section 17.1).

If the day comes when a baked pipeline genuinely cannot deliver, section 17.5 is
the door: a build variant, which is a reinstall rather than a download, with the
engine inside the package where it breaks no rule. **That decision is not taken
now.**

### 20.3 Art direction: soft, and deliberately so

The reference is the soft end of current anime-adjacent game art. miHoYo's work
is the clearest example: rounded silhouettes, low specular contrast, warm
mid-tones, and light that wraps a form rather than edging it.

**Soft is a requirement, not a taste.** Three reasons, and any one of them
settles it:

- The project's own name and voice are tender (section 0). Sharp rendering
  fights the thing the product already is.
- This app is looked at while drinking, not while competing. High-contrast,
  high-energy presentation reads as tension, and tension is the opposite of
  what a cellar is for.
- Section 20.5 puts a character in it. The character sets the register for
  everything around her.

Concretely: rounded silhouettes over hard chamfers, no spikes or aggressive
normals; diffuse-dominant lighting, rim light for separation rather than for
menace; saturated but low-contrast mid-tones, highlights that bloom rather than
glint; motion that settles -- ease-out, small overshoot, and nothing that snaps.

**Reference material should be chosen the same way.** The soft end of the
available models is the useful end; the sharp, aggressive end is a style this
project is explicitly not learning.

### 20.3.1 The polygon budget, and why it is set before anything is modelled

The direction from the author is specific: **study how miHoYo keeps polygon
counts down**, because the counter-example is instructive -- Kuro's games are
held back on older devices by polygon count and package volume, and that is a
compatibility ceiling rather than a matter of taste. A character that only reads
on a recent phone is a character the project cannot ship.

**This is the same constraint as section 14.1 seen from the other end.** There
the budget was stated as tens of megabytes for a release; here it is the thing
that decides whether that number is achievable, because geometry, textures and
animation data *are* the megabytes. A budget that is discovered while modelling
is a budget that has already been missed.

**Two measured counter-examples, both from reference material read for this
project:**

| What was measured | What it shows |
| --- | --- |
| A single mesh bundle of **3.16 GB** in iSekaiju, with `AutomaticLOD`, `MeshSimplify` and `UltimateGameTools.MeshSimplifier` all compiled in | a mesh budget that was **fixed at runtime rather than set at authoring time**. Three separate reduction systems is what that looks like from the outside, and the 3.16 GB was already shipped by the time they were added. |
| HypnoApp at **965 MB in a 32-bit process**, with its readme documenting an ultra-low graphics mode and 800x600 as the remedy | a build authored to a 4 GB address ceiling, where the low tier is a documented escape hatch rather than a target that was designed for |

Both are small-team releases and neither is being criticised for it -- the
lesson is only that **they found the ceiling after the content existed.**

**What is not yet measured, and must not be asserted.** Neither of those is
miHoYo's technique, and this document does not claim to know what miHoYo's
technique is. What follows is the list of things to measure on the reference
material before setting a number, and it is a study task rather than a
conclusion:

- **Triangles per character**, and the ratio between the shipped mesh and its
  lowest LOD.
- **Where the budget actually goes** -- vertex count, texture set, morph targets
  and skeleton each carry a different cost, and a soft-looking model can be
  cheap in geometry and expensive in textures or the other way round.
- **Whether the silhouette survives reduction.** This matters more than the
  count for section 20.3: a soft style is carried by outline, so a reduction
  that breaks the outline has cost more than it saved.
- **Cloth and hair bone counts**, since `MagicaClothV2` and `DynamicBone` were
  both found in the reference material and both cost per bone per frame.
- **Texture footprint per material slot**, which is usually larger than the
  geometry and much easier to let grow.

**Reference-material size is a separate fact from per-asset efficiency.** The
miHoYo installs on this workstation are enormous -- the launcher directory is
about 86 GB -- but that is content volume for an open world, not waste per
asset. Their characters are the thing worth studying precisely because they read
well at a fraction of what a naive mesh would cost. Confusing the two numbers
would lead to the wrong lesson in either direction.

**The rule that follows.** A budget is set per screen, against the **lowest**
target device, before the first model is drawn; it is checked by measuring the
shipped asset rather than by estimating it; and it is recorded beside the asset
the way section 20.4.1 records provenance. Degradation is then a design with a
named bottom tier -- section 16.5 already asks for that -- and not a setting
somebody adds after the first report of a crash.

### 20.4 Reference material: study the style, ship your own

Official and community models in this style are widely available, and they are a
legitimate thing to **study**. The default is that they are not a thing to ship.

This is exactly the position section 15 takes on recipe data, and for the same
reason: the copyright belongs to whoever made it.

**And the reason is worth stating precisely, because it is not self-interest.**
This project is free and will never be sold, so the risk to *it* is close to
nothing. The risk that matters is the one the original maker carries: an artist
whose work turns up inside somebody else's package is the one who has to answer
for it, whether or not they ever wanted to. So the rule is not "do not get
caught" and it is not "we can afford it" -- **it is that a free project has no
standing to make a commercial creator's life harder for its own convenience**,
and a rule that only binds while somebody is watching is not a rule. That is why
the watermark check below is written to be thorough rather than to be defensible
if questioned: the point is not to pass an inspection.

So:

- Reference models are style study and pose/animation reference. They stay on
  the workstation.
- What ships is modelled and animated in-house, in that direction. "In the style
  of" is a direction, not a licence.
- Every asset in the pack records its provenance, which section 17.4 already
  asks for, so "where did this come from" always has an answer.
- **A third-party asset may be used, and only** when all three of these hold: a
  careful check finds no watermark, the asset is **modified** before it is used,
  and its provenance is recorded. This is the single exception to the rule above
  and it is deliberately narrow.

### 20.4.1 A watermark is not always in the picture

The check in the bullet above is the part that is easy to do badly, because
"look at the sprite" is not the check. Two counter-examples were found on this
workstation while reading the reference material, and both would have passed a
visual inspection:

| Where the provenance was | Found in |
| --- | --- |
| **A file, not an image.** A 16-byte file named `DLCExpansion.dll` whose entire contents are the ASCII string `OsawariPJ DLsite` -- a storefront marker, invisible in any render. | iSekaiju, `DLC/` |
| **A fixed-width text field in the file header.** A model whose header comment reads `Copyright：CRYPTON FUTURE MEDIA, INC`, with the modeller named in the same field. Nothing about the mesh or the texture says so. | The `.pmd` models in the MMD install |

So the check runs over the **whole asset set**, not over the part wanted:

- **File header and metadata fields.** Container formats carry author and
  copyright strings as a matter of course -- a model's comment block, a PNG's
  `tEXt`/`iTXt` chunks, EXIF and XMP. Read them; do not trust the preview.
- **Sidecar and marker files.** Storefronts plant per-channel files precisely so
  a leaked copy can be traced, and they sit beside the asset rather than inside
  it. A directory listing is part of the check.
- **Inside the asset where nobody looks.** A texture atlas is bigger than the
  region a sprite samples; a scene may hold a billboard behind the camera or an
  unused sprite. A watermark that is never rendered is still a watermark.
- **Names.** A bone, material, mesh or layer named after the author is
  provenance even when no picture contains one.

**And the check is a necessary condition, not a sufficient one**, which is worth
writing down because the rule above is easy to misread as a licence check. A
missing watermark says nothing about what the licence permits -- plenty of work
carries no mark and no permission. So the provenance record has to hold **two
independent facts**: what was checked for and not found, and what the terms
actually allow. An asset with a clean check and unknown terms is an asset with
unknown terms.

### 20.4.2 The check, run (2026-09-23)

`tool/watermark_check.py` runs the four passes above over a set, and every set pulled for a rhythm game, Blue
Archive and a mobile game studies has now been through it. **Two of the tool's own results were wrong
first**, and both corrections are recorded in its header rather than tidied away.

| Set | Files | Names | Container metadata | Sidecars | Contents |
| --- | --- | --- | --- | --- | --- |
| a mobile game, the whole copy | 44,672 | 0 | — (no images) | 5 of the game's own files, read | 37,910 whole + 6,762 ends-only, **1 name**, explained below |
| a rhythm game, `arcaea-ui` | 2,554 | 0 | 2,239 images, **128 carry XMP** | 0 | sampled, 0 |
| a rhythm game, `arcaea-more` | 2,458 | 0 | 1,486 images, **88 carry XMP** | 0 | sampled, 0 |
| 学マス, its exported interface | 407 | 0 | 405 images, 0 | 0 | — |
| 学マス, `datapack.unity3d` and `data.unity3d` | 2 | 0 | — | 0 | ends, 0 |
| a mobile game's own APKs | 36 | 0 | — | 0 | 11 whole + 22 ends, 0 |
| **`E:\ANMS`** (third-party model packages, 2026-09-23) | 484 | 0 | 275 images, **210 carry `tEXt: Software Celsys Studio Tool`** | 11 readmes and terms links | 418 read, **1 marker: the author's own BOOTH shop URL** |

**The one marker in `E:\ANMS` is the interesting kind of hit, and it is not a leak.** It is
`https://mk22.booth.pm/` inside `Cian_PC_v\Readme.txt` -- a link the author put in their own readme, which is
provenance of the legitimate sort rather than a mark left by a redistributor. **Saying which of the two it is
takes a reader, and the tool is built not to pretend otherwise.** Those packages also carry their own readmes
and terms (`.url` links, `readme.txt`, `Readme_JP.txt`, `Readme_KR.txt`), which makes them the first set here
where the *second* fact of this section -- what the terms allow -- is on disk instead of unknown. The recurring
subjects across them are redistribution, modification and R-18 conditions, and one of them credits the original
character owner, a model author and a third person who separated the materials: three names for one file, which
is what a provenance record has to hold.

**No storefront marker was found anywhere.** The two findings worth keeping are about the *check* rather than
about the sets:

1. **A byte-pattern search over a 5 GB set is nearly all noise, and the first run proved it**: 27 hits, every one
   a five-letter coincidence inside compressed or base64 data. `LevelSkill/*.bytes` is base64 *text*, so long
   printable runs are the norm there and `pixiv` inside one means nothing. A marker is a string in a field, so a
   hit now has to be **a whole token inside readable text** — both neighbours non-alphanumeric — and that removed
   all of them but one name.
2. **One name did deserve the look, and the look explained it.** `character-ch0310-…timelines` contains
   `FX_CH0310_EX01_Motion_Cam_Watermark_Table` and `…_Watermark_Capet`: that is the game naming its own camera
   effect, and `Watermark` is a false friend here. Which is precisely why this section calls a name *provenance*
   and not *proof*.

**What the metadata pass found instead is real, and it is the category this section predicted.** 216 of a rhythm game's
shipped PNGs carry an XMP packet, and it names the **tool and a time** rather than an author:

```
stEvt:softwareAgent="Affinity Photo 2 2.5.5"
xmp:CreateDate="2024-10-29T17:44:49+0900"    xmp:ModifyDate="2024-10-29T17:46:28+09:00"
```

No `dc:creator`, no copyright field. Two facts worth having: artwork in this medium routinely carries a tool and
a timestamp even when it carries no name, and a metadata pass finds them where a preview cannot.

**And the outcome is still only half the record.** This is a **not-found** result: nothing was checked and found.
What the terms allow is the other, independent fact, and an asset with a clean check and unread terms is an asset
with unread terms.

**Modification is required and is not a technicality.** The point of it is that
what ships is this project's own work made *from* a reference rather than the
reference itself, which is the same position section 15 takes on recipe data and
the same reason. Recolouring or cropping a file does not by itself turn it into
anything else, so the modification has to be the real kind: re-drawn, re-rigged,
re-textured, or rebuilt from the reference's proportions and palette. Where an
asset is only lightly changed, it is not on the shippable side of this line and
is better treated as study material.

**Per-asset provenance record.** Section 17.4 already asks for one; this is what
each row holds. The manifest itself is written when the first asset exists, and
the columns are fixed now so that the first row cannot be the one that forgets a
field:

| Field | Why |
| --- | --- |
| Asset id and file | what it is |
| Origin | the URL, store, or product it came from |
| Watermark check | `none` / `present` / `unknown`, and **what was inspected** -- a check with no method recorded is not a check |
| Licence terms | what the source says, quoted, or `unknown` |
| Modification | what was done to it, or `none` |
| Shippable | derived: `yes` only when the watermark check is `none`, the terms permit it, and the modification is real |

**Where the reference material is, and how it is handled.** The workstation
already holds a library of games worth studying, and they come with one
operational rule: **a game directory is read-only, and a copy of one is not.**
Nothing is ever written into an install; anything wanted from one is copied into
this project first, and the copy may then be edited, patched, repacked or broken
as the study needs. Reference material is disposable and a working copy is not, so
a mistake costs a re-copy rather than an evening and a re-download -- and a
modified original would stop being evidence, which is the second reason and the
one that matters more. `PLAN.md` section 6.1 sets out what this newly permits.

| What | Engine, format | Why it is worth looking at |
| --- | --- | --- |
| a mobile game (`D:\miHoYo Launcher\games`) | Unity | Largest single catalogue of the reference style. About 86 GB. |
| iSekaiju (`D:\iSekaiju`) | Unity, Mono | Its managed assemblies name the two techniques that make soft character motion work: `MagicaClothV2` for cloth and hair, `VeryAnimation` for animation authoring. Also a 1 MB `Assembly-CSharp.dll` and `Cinemachine`. |
| Maitetsu (`D:\まいてつ Last Run!!`) | KiriKiri (`.xp3`) | Warm, quiet 2D art -- the register the 2.5D path of section 20.5 should aim at. |
| a rhythm game (`E:\a rhythm game`) | .NET, Realm | A UI built entirely around feedback. Skins and beatmaps are plain assets. |
| Steam libraries (`E:\`, `D:\`) | mixed | a social platform, Muse Dash, MahjongSoul, Wallpaper Engine, Project DIVA, and others. |
| `F:\HGame`, `D:\Isekai Life's Fantasy` | mixed, Java | Small-team work, and a Java game with a mod ecosystem -- both useful for how little a feature can cost. |

**A tool name in that table is a lead, not a dependency.** Reading
`MagicaClothV2` is how to learn what cloth simulation costs; it is not something
this project can ship, and neither is any model in any of those directories.

### 20.5 The character

The product has a persona: Harumi (世和崎 晴光), the knight-librarian who already
serves as the coding agent's voice. Putting her into the app is an extension of
something that exists rather than a new invention -- and she is **original
work**, so section 20.4 is satisfied by construction.

Constraints, in the order they matter:

- **Optional, and off is a supported state.** A mascot that cannot be dismissed
  is a mascot that comes to be resented. One setting, honoured everywhere.
- **Present, not performing.** She belongs at the edges: a reaction to a pour, a
  note when a bottle is running low, a face on the empty state. She does not
  interrupt, does not animate while someone is reading, and does not speak
  unless spoken to.
- **The same voice she has everywhere else** -- spare with words, precise in
  manner, warm once you are past the surface. A cheerful chatterbox would be a
  different character wearing the same face.
- **2.5D first.** A rigged 3D character is the most expensive asset in the pack
  and the one most likely to age badly. The 2.5D pipeline of section 16.2
  already exists for the shaker, costs far less, and suits a character whose
  main job is to be present rather than to perform.

Her register is also the reason section 20.3 is written the way it is: she is
soft by design, and the art direction has to agree with her or she will look
like a guest in someone else's app.

**The toolchain for her already exists on this workstation**, which is worth
knowing before anyone plans to install something: Unity Hub with 2022.3.22f1c1
and 2019.4.13f1c1, the social platform Creator Companion with Avatar and World project
templates, Blender 4.4 for the modelling, and a social platform itself as the place a
rigged avatar is normally proven before it goes anywhere else.

That last sentence is the shape of the pipeline, not a statement about this
product. **a social platform is where an original model gets made and validated; it is not
a dependency of Hollow Court**, and nothing from its ecosystem is bundled --
the same boundary as section 20.4. What transfers is the asset we build and the
skill, not the platform.

### 20.6 What this costs the base app

**The assets: none of them.** Everything in this section that is measured in
megabytes is asset-pack content (section 17.4) -- not in a release, opt-in from
the client, hash-checked, removable. Animated feedback, cloth simulation, the
rigged or 2.5D character, the shaker, the shelf simulation: all of it waits for
the second download, and design section 14.1 sets out why the budget is a hard
constraint rather than a preference.

**The character: she is in the base app, and she costs nothing to put there.**
Section 14.1 is explicit that she is not part of the optional layer, and what
ships in a release is her presence rather than her implementation -- the voice in
the copy, the name in the typography, the palette, the restraint. That is a few
kilobytes of text and a colour table. What waits for the download is the rig, the
expressions and the animation.

**And the layer degrades to nothing, not to a placeholder.** With no pack
installed the app shows a sober, complete interface -- with the character's voice
still in it, because her voice was never in the pack. Section 17.4 already
requires that of the Pro pack, and this section is the largest thing that
requirement covers.

---

*Every technical judgement in this design document is supported by evidence from another source and one source; the corresponding reverse-engineering records are in an earlier survey.*
