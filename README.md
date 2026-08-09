# AscensionLoot

AscensionLoot is a World of Warcraft 3.3.5a raid-loot addon for Ascension: Conquest of Azeroth.

It is built for raids that collect loot on one designated holder and distribute it later using BisBeard soft reserves, structured rolls, persistent loot tracking, and assisted trading.

> **Current version:** 0.5.0

## Features

- BisBeard RollFor soft-reserve import
- Persistent loot queue across bosses, reloads, and relogs
- Master Loot and Group Loot workflows
- SR, MS, and OS roll handling
- Multiple-copy and duplicate-SR support
- Synchronized roll window for raid members using AscensionLoot
- Live roll timer and accepted roll results
- Roll, OS, and Pass buttons for participating players
- Roll and OS controls for the loot holder
- Safe raid-roster name matching
- Temporary raid-trade timer validation
- Assisted trade opening and item placement
- Movable minimap button
- Configurable loot, roll, trade, and interface settings
- Loot history with clear-history confirmation
- Built-in UI demo with safe cleanup

## Roll rules

```text
Soft Reserve > Main Spec > Off Spec
```

- `/roll 100` is SR when the player reserved the item
- Otherwise `/roll 100` is MS
- `/roll 99` is OS
- Duplicate reserves may grant extra roll attempts
- One player can win only one copy in the same roll
- Ties are rerolled only between tied players

Roll announcements include the configured duration.

For rolls longer than 10 seconds:

- A halfway warning is announced
- The final 5 seconds are counted down

For rolls of 10 seconds or less:

- No halfway warning
- The final 5 seconds are counted down

## Installation

Download **AscensionLoot.zip** from the GitHub release assets.

Do not download GitHub's automatically generated **Source code** archives.

Extract the ZIP into:

```text
Interface\AddOns\
```

The final path must be:

```text
Interface\AddOns\AscensionLoot\AscensionLoot.toc
```

Enable the addon on the character-selection screen and reload the UI:

```text
/reload
```

For beta testing, enable Lua errors:

```text
/console scriptErrors 1
```

## BisBeard import

1. Open the raid on BisBeard
2. Lock the reserve list
3. Choose **RollFor export**
4. Copy the generated string
5. Right-click the AscensionLoot minimap button or run:

```text
/al import
```

6. Paste the export
7. Press **Import**

## Basic workflow

### Master Loot

1. Set the designated holder as Master Looter
2. Import BisBeard reserves
3. Configure Master Loot automation
4. Loot bosses normally
5. Eligible items are added to the persistent queue
6. Roll and trade the items later

### Group Loot

1. Use Group Loot
2. Let the designated holder receive distributable loot
3. AscensionLoot verifies the temporary trade timer
4. Eligible items are added to the persistent queue
5. Roll and trade the items later

## Bag controls

- **Alt + Left Click:** Start a roll for a tradeable bag item
- **Shift + Alt + Left Click:** Assign a solo-soft-reserved item directly

Only items with an active temporary raid-trade timer are accepted.

## Minimap button

- **Left click:** Toggle the loot window
- **Right click:** Toggle the Import page
- **Drag:** Move the button

The button can be hidden through Settings.

## Commands

```text
/al
/al loot
/al settings
/al reserves
/al import
/al history
/al finish
/al cancel
/al trade
/al clear
/al clearloot
/al clearhistory
/al demo
/al help
```

## Beta feedback

Please include the following when reporting a problem:

- Addon version
- Master Loot or Group Loot
- What you were doing
- Complete Lua error
- Steps to reproduce
- Relevant screenshots
- Other bag, minimap, or interface addons in use

## Known limitations

- Only one roll session can be active at a time
- Final trade acceptance must be completed manually
- Some custom bag addons may require compatibility fixes
- RAID_WARNING requires raid leader or assistant permissions
- Ascension's customised client may require further compatibility fixes

## Licence

MIT
