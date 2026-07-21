# RefinedBlizzPlates by Placid

A nameplate addon for World of Warcraft 3.3.5 (WotLK) that reskins Blizzard's default nameplates in place, adding class-colored health bars, cast bars, level/elite/boss/raid-target icons, totem tracking, and optional overlapping-nameplate stacking. It is a fork of the original `RefinedBlizzPlates` by Khal, adapted and tuned for Project Ascension.

## Install
Folder name must stay `RefinedBlizzPlates by Placid` inside your `Interface\AddOns` directory (this folder already matches, so you can copy it there as-is).

## Slash Commands
None. The addon does not register any `/` chat commands. All configuration is done through the in-game Interface Options panel (`Esc > Interface > AddOns > RefinedBlizzPlates by Placid`), which the addon opens itself via `AceConfigDialog:AddToBlizOptions`.

## Features
- Reskins default nameplates into a "Virtual Plate" overlay (health bar, name text, level text) without replacing Blizzard's plate frames outright.
- Class-colored and reaction-colored health bars, with aggro/threat glow on the health bar border.
- Cast bar with spark, border/glow states (interruptible vs. non-interruptible/shielded), and cast timer text.
- Level text, elite/rare icon, boss icon, and raid-target (skull, star, etc.) icon overlays.
- Class icon overlay option.
- Totem tracking: per-totem icons and description text for the four totem slots (earth/fire/water/air).
- "Barless Plate" mode: a compact, health-bar-less nameplate style for out-of-combat/passive display.
- Blacklist: hide nameplates for specific unit names.
- Whitelist: assign a specific unit name its own custom nameplate icon (icon, size, offset, border), independent of the shared totem icon settings, using a built-in icon-picker popup (`IconPicker.lua`).
- Arena opponent ID text (e.g. "Arena 1") in arena matches.
- Clickbox handling that adjusts nameplate click targets in and out of combat, including friendly-nameplate click-through.
- Optional "Retail-like Stacking": vertically offsets overlapping nameplates so they don't stack directly on top of each other, with tunable presets (Balanced/Chill/Snappy/Custom), spring stiffness, launch damping, collider size, and a "freeze on mouseover" option.
- Zone-specific fixes: Lady Deathwhisper "Dominate Mind" detection/handling and a level-filter/level-text-hide option.
- AceDB-backed profiles (create/copy/reset/delete profiles from the Profiles tab).
- Localized strings for enUS, deDE, esES, esMX, frFR, koKR, ruRU, zhCN, zhTW.

## Bug Fixes vs. the Original
Compared against `!!RefinedBlizzPlates` (Khal's original, v1.9.6, github.com/KhalGH/RefinedBlizzPlates-WotLK) — confirmed to be the direct base by identical file layout (`Core.lua`, `Functions.lua`, `Media.lua`, `Settings.lua`, `Embeds.xml`, matching `Locales`/`Assets` structure). `TurboPlates-1.4.5x`, also present in this folder, is a structurally unrelated addon (different file set entirely — `Auras.lua`, `Castbars.lua`, `HealerDetection.lua`, etc.) and was not used for this comparison beyond confirming it doesn't match.

- Replaced the original's per-frame `OnUpdate` polling engine (a 0.05s-throttled full-plate sort pass plus a 0.2s secondary pass, and a WorldFrame child-count poll to detect new nameplates) with an event-driven engine: nameplates are discovered via `NAME_PLATE_UNIT_ADDED`, reaction/hostility changes via `UNIT_FACTION`, aggro/threat-color changes via `UNIT_THREAT_SITUATION_UPDATE`/`UNIT_THREAT_LIST_UPDATE`, and mouseover highlighting via `UPDATE_MOUSEOVER_UNIT` — each scoped to the specific unit instead of scanning every visible plate on a timer. Frame levels are now set once when a plate is shown instead of being re-sorted every tick.
- Added `RBP.CheckReactionChange` and `RBP.CheckAggroColorChange` (new in `Functions.lua`) to support the above event-driven reaction/aggro updates; these functions do not exist in the original.
- Replaced the original's exponential-relaxation nameplate-stacking algorithm with a spring-physics stacking system (new `Stacking.lua`), split into a throttled/dirty-gated layout pass and a per-frame spring-integrator animation pass. This adds tunable settings not present in the original: Stacking Feel presets (Balanced/Chill/Snappy/Custom), Spring Stiffness (Raise/Lower), and Launch Damping. The original only exposed Enable, Collider Width/Height, Vertical Offset, Freeze Mouseover, and Disable in Open World for stacking.
- Added a Whitelist feature (new UI in `Settings.lua` plus new `IconPicker.lua`) that lets a user assign a specific unit, by exact name, its own custom nameplate icon with independent size/offset/border — the original has no Whitelist tab or icon-picker at all.
- Renamed the SavedVariables (`KhalPlatesDB` -> `RBPPlacidDB`) and the AceConfig options-table keys (`RefinedBlizzPlates` -> `RefinedBlizzPlates_ByPlacid`), so this fork can run alongside the original without clobbering its saved settings.
