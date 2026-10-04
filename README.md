# Pal Deck mod for Palworld

The Palworld half of [Pal Deck](https://teatimeservers.ca/plugins/pal-deck), a Stream Deck plugin, and of Palworld
Dashboard, an iCUE widget for the CORSAIR XENEON EDGE. It is a small client-side UE4SS Lua mod: once a second it
writes what your game shows you about your party, your bases and yourself to a state file, which the plugin and the
widget draw from.

It only reads the game. It never changes a Pal, an item or a save, opens no network connection, does nothing on a
dedicated server and only looks at the local player. This repository is here so you can see exactly what it does: it
is all in one file, [`main.lua`](PalDeck/Scripts/main.lua). The file ships without comments, as it is here.

## What it reads

- Your character: name, level, HP, hunger, EXP, the stat points you have spent on each stat and the points left.
- Your party of five, from the party container on your player controller: each Pal's id, nickname and English name
  (from the game's own `DT_PalNameText`), level, HP, hunger and its maximum, sanity, sickness, rare, gender, talents,
  condenser rank, soul upgrades, trust and passive skills (English names from `DT_SkillNameText`).
- Your bases' workers, from the base containers on the game state: the same for each Pal, and each base's count of
  workers, sick, hungry (under 35%), low on sanity (under 50) and rare.
- The Pal you are looking at: the nearest Pal in the middle of your view, within 80 metres, worked out from the camera
  position and the Pals' positions; its details as above, whether it is wild, and how far away it is. Positions are
  used only to pick that one Pal and are not written.
- The time of day (hour, minute, day count, night) from the game's time manager, when this build of the game offers
  those functions.
- The weapon in your hands: its class, item id, English name (from `DT_ItemNameText`), and the rounds in the magazine
  when the weapon carries them.
- Whether you are in a world or at the title screen.

Every object is checked with `IsValid` before it is touched, and every function is looked up with `StaticFindObject`
before it is called: in UE4SS a bad native access crashes the game, and Palworld then switches its whole mod system
off until you turn it back on.

## The state files

The same JSON, rewritten whole once a second, goes to two places:

- **In the game folder:** `Mods\NativeMods\UE4SS\Mods\PalDeck\state.json` (the Steam Workshop UE4SS layout) or
  `Pal\Binaries\Win64\ue4ss\Mods\PalDeck\state.json` (a hand install), for the Stream Deck plugin.
- **In your user folder:** `%APPDATA%\PalDeck\state.json`, for the iCUE widget, which can only be given permission to
  read under your user folder. The mod makes the `PalDeck` folder at the title screen, by asking the engine to write a
  file there (Lua has no quiet way to make a folder) and deleting that file again; a starter file follows at once, so
  the folder and the file exist before you add the widget.

`protocol` is the file's format version; `inGame` is false at the title screen. Anything that could not be read is
`null`, so a game update that renames one field costs one field, not the file. Each write is a single write that ends
with `"end": true`, and readers ignore a file that does not.

## Key bindings

The mod binds F13 to F24, keys that exist in Windows but on no keyboard, for the Stream Deck. F13 writes the state
file and logs that the mod is alive; F14 to F18 log a party slot and F20 the bases; the others log that they are not
implemented yet. UE4SS reads them only while the game has focus.

## Diagnostics

A file named `dev.txt` placed beside the state file in the game folder turns on the investigation code used to find
the game's objects: dumps of the classes it reads (`dump.txt`), the input bindings (`input.txt`), the name tables
(`names-check.txt`), the look-at search (`target.txt`) and a step-by-step `trace.txt`. Without `dev.txt` none of it
runs. All of it is written inside the mod's own folder.

## Installing

Pal Deck installs it for you: **Install the mod** in any Pal Deck key's settings, with the game closed. By hand:

1. Install UE4SS for Palworld (the Steam Workshop's UE4SS, or a hand install matched to your game version; see
   pwmodding.wiki).
2. Close Palworld.
3. Copy the `PalDeck` folder into UE4SS's `Mods` folder:
   - Workshop layout: `<Palworld>\Mods\NativeMods\UE4SS\Mods\`
   - Hand install: `<Palworld>\Pal\Binaries\Win64\ue4ss\Mods\`
4. Add `PalDeck : 1` to the `mods.txt` in that `Mods` folder, above the `Keybinds` line (the `enabled.txt` in the
   folder does the same on builds that use it).
5. Start the game. The UE4SS log gets a `[PalDeck] loaded` line, then the state file paths it writes to.

Do not give the mod a Palworld ManagedMods entry (`Info.json`, `InstallManifest.json`): the game's mod manager removes
packages it cannot match to a Workshop subscription, and it loads fine from `mods.txt`.

UE4SS is tied to the game's version: after a Palworld update, mods that read the game wait until UE4SS catches up.

## Licence

MIT, see `LICENSE`. Pal Deck is an unofficial fan project, not affiliated with or endorsed by Pocketpair. Palworld is a
trademark of Pocketpair, Inc.
