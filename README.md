# Mimic Repeat Orders

The impossible is possible: use the Mimic behavior for Repeat Orders.

## Features

- Assign any appropriate Player-owned ship to commander with `Repeat Orders` enabled as subordinate with `Mimic` behavior.
- The subordinate ship will copy the `Repeat Orders` of its commander.
- Ships with insufficient AI Pilot skill to use `Repeat Orders` will be not assigned or removed.
- Any changes to the commander's `Repeat Orders` will be automatically reflected on the subordinate ship.
- Works with `Sell`, `Buy`, `Mine`, `Collect Drops`, `Salvage at Position` and `Deliver Salvage` vanilla orders.
- Works with `Mining in Sector` order from the `Mining in Sector for Mimic Repeat Orders` mod.

## Limitations

- Only one level of `Mimic` behavior is supported. Ships assigned as subordinates to subordinate ships will not be able to mimic their orders.
- Changes to subordinate ship's will be reflected with small delay, up to 30 seconds.
- Supports only limited amount of orders. Other order types may be supported in future versions.

## Specifics

- Orders `Sell`, `Buy`, `Mine`, `Mining in Sector`, `Salvage at Position` and `Deliver Salvage` will not be processed if they are only one type of orders under control of `Repeat Orders`. I.e. if the commander has only `Sell` orders, the subordinate ship will not mimic them. But if both `Sell` and `Buy` orders are present, both will be mimicked. `Mine` and `Mining in Sector` are best combined with `Sell`. `Salvage at Position` is best combined with `Deliver Salvage`.
- Only `Collect Drops` order is supported alone, as it does not require any other order to be effective.

## Requirements

- `X4: Foundations` 7.60 or newer (tested on 7.60 and 8.00).
- `Mod Support APIs` by [SirNukes](https://next.nexusmods.com/profile/sirnukes?gameId=2659) to be installed and enabled. Version `1.93` and upper is required.
  - It is available via Steam - [SirNukes Mod Support APIs](https://steamcommunity.com/sharedfiles/filedetails/?id=2042901274)
  - Or via the Nexus Mods - [Mod Support APIs](https://www.nexusmods.com/x4foundations/mods/503)

## Installation

You can download the latest version via Steam client - [Mimic Repeat Orders](https://steamcommunity.com/sharedfiles/filedetails/?id=3599279973)
Or you can do it via the Nexus Mods - [Mimic Repeat Orders](https://www.nexusmods.com/x4foundations/mods/1875)

## Usage

Simple use the usual context menu options to assign a ship to commander with Repeat Orders enabled as subordinate using the `Mimic` behavior.

## Video

[Video demonstration of the Mimic Repeat Orders. Version 1.00](https://www.youtube.com/watch?v=6pT75XC8MUs)

## Non-vanilla Orders

### Mining in Sector for Mimic Repeat Orders

Simple mining routine for player owned ships in sector to be managed by Repeat Orders

You can download the latest version via Steam client - [Mining in Sector for Mimic Repeat Orders](https://steamcommunity.com/sharedfiles/filedetails/?id=3602563805).

Or you can do it via the Nexus Mods - [Mining in Sector for Mimic Repeat Orders](https://www.nexusmods.com/x4foundations/mods/1880)

## Credits

- Author: Chem O`Dun, on [Nexus Mods](https://next.nexusmods.com/profile/ChemODun/mods?gameId=2659) and [Steam Workshop](https://steamcommunity.com/id/chemodun/myworkshopfiles/?appid=392160)
- *"X4: Foundations"* is a trademark of [Egosoft](https://www.egosoft.com).

## Acknowledgements

- [EGOSOFT](https://www.egosoft.com) — for the X series.
- [SirNukes](https://next.nexusmods.com/profile/sirnukes?gameId=2659) — for the Mod Support APIs that power the UI hooks.
- [Forleyor](https://next.nexusmods.com/profile/Forleyor?gameId=2659) — for his constant help with understanding the UI modding!

## Changelog

### [1.12] - 2025-11-26

- Added
  - Support for `Salvage at Position` and `Deliver Salvage` orders.

### [1.11] - 2025-11-16

- Added
  - Support for `Collect Drops` order.

### [1.10] - 2025-11-09

- Added
  - Framework to support additional order types.
  - Support of `Mine` and `Mining in Sector`.
  - Cleanup not supported orders.
- Fixed
  - Several small bugs.

### [1.01] - 2025-11-04

- Fixed
  - On multiple events some was skipped due to incorrect queue handling.
  - Incompatibility with 8.00 (up to HF3)

### [1.00] - 2025-11-04

- Added
  - Initial public version
