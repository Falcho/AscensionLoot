# Ascension Loot 0.1.0

A clean-room World of Warcraft 3.3.5a addon for:

- BisBeard RollFor soft-reserve imports
- A separate master-loot queue frame
- Alt-click to start the appropriate roll
- Shift+Alt-click to award the active proposed winner
- Reserve-only, main-spec, off-spec and tie rolls
- Duplicate soft reserves as additional allowed rolls
- Safe low-quality autoloot
- Award history

It contains no GDKP, auction, pot, balance or gold-tracking features.

## Installation

Copy the `AscensionLoot` folder into the Ascension 3.3.5a client:

```text
Interface\AddOns\AscensionLoot\AscensionLoot.toc
```

Restart the client, enable the addon on the character screen, and run:

```text
/console scriptErrors 1
/reload
```

## First test

Run:

```text
/al demo
```

This opens the UI with three fake items. Rolling works in demo mode; awarding is deliberately disabled.

## BisBeard import

1. Open the locked raid on BisBeard.
2. Select its **RollFor export**.
3. Copy the Base64 string.
4. In game, run `/al import`.
5. Paste the string and click **Import**.

The initial release supports BisBeard's plain Base64 JSON RollFor export. It deliberately rejects zlib-compressed exports.

## Raid workflow

1. Become master looter.
2. Open a corpse.
3. The Ascension Loot frame opens and lists item loot slots.
4. Alt-click an item row to start its default roll:
   - one soft reserver: proposes that player directly;
   - multiple soft reservers: starts an SR-only `/roll 100`;
   - no soft reservers: starts an open MS `/roll 100`.
5. Click **OS** for `/roll 99`.
6. When the roll finishes, click **Award Winner** or Shift+Alt-click the same item row.
7. Confirm the award.

The addon rechecks the loot slot and candidate list immediately before calling `GiveMasterLoot`.

## Commands

```text
/al
/al loot
/al reserves
/al import
/al history
/al settings
/al finish
/al cancel
/al clear
/al demo
/al help
```

## Current limitations

- Designed against the standard 3.3.5a API. Ascension-specific API differences may require small compatibility fixes after live testing.
- Roll parsing uses the client's `RANDOM_ROLL_RESULT` localization, with an English fallback.
- Only one roll can be active at a time.
- Autoloot defaults to coin, poor and common items and protects all reserved items.
- Item names in the reserve viewer can initially appear as item IDs until the client caches those items.
- Award history is recorded after `LOOT_SLOT_CLEARED`.

## Licence

MIT. See `LICENSE`.
