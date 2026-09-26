# Art resources and UI classification

Written 2026-09-25, after the owner's note that the three studied subjects -- **a rhythm game**, **a mobile game**
and **a mobile game** -- are worth learning from specifically for *art-resource planning* and *UI classification*.

Those two things are not decoration. A palette is a decision any project can make in an afternoon; how the art is
**organised** is what decides whether a second theme costs a week or a month, and how the interface is
**classified** is what decides whether a new screen is a variation or a fork.

## 1. What the three actually do (measured, not remembered)

Taken from the UI material pulled on 2026-09-22 and still on disk.

| | Structure | Files | The作法 worth stealing |
| --- | --- | --- | --- |
| **a rhythm game** | `assets/{Fonts, layouts, startup}`, `auto/`, `sheets/`, `views/` | 2445 | **One panel, one file** (`MainMenu.csb`, `TopBar.csb`, `CharacterSelect.csb`). **Atoms and composition are separate**: `sheets/` holds packed sprites, `views/` holds what they compose into |
| **a mobile game** | `sheets/` only | 2309 | Everything is packed into sheets. Names are **feature-prefixed and numbered** -- `AcademyScheduleImage_1..4` -- so a file's owner is legible from its name alone |
| **a mobile game** | `sheets/`, `textures/` | 405 | **The name states the role**: `patterns-on-dark` is a *pattern*, `audition_header_frame` is a *component part*, `ActorFootShadowTexture` is *role + type*. `textures/` exists separately from `sheets/` because they are different asset classes |

Three separate projects converged on the same four answers: **separate the atoms from the composition**,
**pack what repeats**, **name the role in the filename**, and **let a screen be one addressable thing**.

## 2. The classification this application adopts

### 2.1 Art resources: theme, then room, then role

The G-edition split note in `DESIGN.md` is irrelevant here; this is about *this* product's own art, and it has two
axes because it has two kinds of variety: three worlds, and five rooms inside each.

```
art/
  themes/
    honeyed/                 # one directory per world, self-contained: deleting it removes the world
      ground.svg             # the world's own ground pattern
      ornament.svg           # the ornament behind a page
      frame.svg              # the panel frame
      <room>.svg             # the five rooms' materials: cellar, bar, recipes, journal, settings
    whiteCourt/ ...
    winter/ ...
  shared/
    prism.svg                # the motif: one file, used by every world (it IS the identity)
    glyph-<name>.svg         # the navigation's five marks
    fleuron.svg
  render/                    # generated output, never edited by hand
```

**Why the filename says the role** (`-ground`, `-pattern`, `-ornament`, `-frame`) -- because that is the one thing
all three references agree on, and because it is exactly what a reader needs when a screen looks wrong: the name
says whether to look at the world, the room, or the atom.

**Why the motif is shared and the rest is not.** A world may change its ground, its ornament and its materials;
it may not change the prism. A theme that redraws the identity is not a theme, it is a second product -- and this
project already has one of those (`DESIGN.md` 12.10).

### 2.2 The interface: rooms, furniture, atoms

```
lib/ui/
  rooms/       one file per screen: cellar, bar, recipes, journal, settings
  furniture/   things a room is made of and that persist across rooms: nav bar, sheets, dialogs, headers
  atoms/       the smallest drawn things: glyphs, prism, rules, materials
  l10n/        the two-register copy system
  theme.dart   the palette and the theme table
```

**A room may use furniture and atoms; furniture may use atoms; atoms use nothing.** That is the whole rule, and it
is checkable: an atom that imports a room's file is a design error, not a style preference. It is the same
separation a rhythm game's `sheets/` against `views/` makes, stated as a dependency direction instead of a directory.

## 3. What this buys, concretely

1. **A fourth world costs one directory.** Everything a world owns is inside `art/themes/<world>/`, so adding one
   is additive -- no existing file is edited, which means no existing theme can break while a new one is drawn.
2. **A new screen costs one file in `rooms/`.** It picks furniture and atoms; it does not invent a button.
3. **Monotony becomes visible rather than argued.** Three worlds times five rooms is fifteen surfaces, and the
   suite already refuses to let any two of the five in a world converge; the same check extends across worlds.
4. **The dependency direction is testable.** A test can walk `lib/ui/` and fail if `atoms/` reaches into `rooms/`.

## 4. Order of work

1. **The three worlds** (`honeyed`, `whiteCourt`, `winter`) -- palette first, then their own ground and ornament.
2. **The five rooms per world** -- materials as values, then each room's surface.
3. **The atoms** -- prism, glyphs, rules: the shared vocabulary, drawn once.
4. **The furniture** -- nav bar (done), sheets, dialogs, headers.
5. **The rooms themselves** -- one at a time, in visibility order: cellar, recipes, bar, journal, settings.
