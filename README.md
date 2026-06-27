# Mimic Repeat Orders

The impossible is possible: use the Mimic behavior for Repeat Orders.

## Features

- Assign any appropriate Player-owned ship to commander with `Repeat Orders` enabled as subordinate with `Mimic` behavior.
- The subordinate ship will copy the `Repeat Orders` of its commander.
- Ships with insufficient AI Pilot skill to use `Repeat Orders` will be not assigned or removed.
- Any changes to the commander's `Repeat Orders` will be automatically reflected on the subordinate ship.
- Works with any vanilla `Repeat Orders` order type automatically — every order parameter (search radius/position, cargo amount, price threshold, wares, etc.) is detected directly from the game engine, so new order types work without needing a mod update.
- Works with non-vanilla orders too, such as `Mining in Sector` from the `Mining in Sector for Mimic Repeat Orders` mod.

## Limitations

- Only one level of `Mimic` behavior is supported. Ships assigned as subordinates to subordinate ships will not be able to mimic their orders.
- Changes to subordinate ship's will be reflected with small delay, up to 30 seconds.

## Specifics

- A single `Repeat Orders` entry is enough to enable mimicking — there is no requirement to combine multiple order types.
  So be careful, is some orders required a "pair" to work properly, like `Buy` and `Sell` orders for trading - there is now **your responsibility** to manage them correctly!
- Cargo-amount parameters (e.g. the minimum/maximum amount on `Buy`/`Sell` orders) are automatically rescaled to match the subordinate ship's own cargo capacity, rather than copied as an absolute number — a larger or smaller subordinate ship will buy/sell proportionally more or less.
- If a subordinate ship cannot carry the ware used by the commander's orders, it is unassigned from the commander automatically.

## Requirements

- `X4: Foundations` 7.60 or newer (tested on 7.60 and 8.00).
- `Mod Support APIs` by [SirNukes](https://next.nexusmods.com/profile/sirnukes?gameId=2659) to be installed and enabled. Version `1.95` and upper is required.
  - It is available via Steam - [SirNukes Mod Support APIs](https://steamcommunity.com/sharedfiles/filedetails/?id=2042901274)
  - Or via the Nexus Mods - [Mod Support APIs](https://www.nexusmods.com/x4foundations/mods/503)
- `Options Helper`, to provide the in-game Debug Level option. Version `1.10` and upper is required.
  - It is available via Steam - [Options Helper](https://steamcommunity.com/sharedfiles/filedetails/?id=3715253556)
  - Or via the Nexus Mods - [Options Helper](https://www.nexusmods.com/x4foundations/mods/2089)

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

### [2.00] - 2026-06-27

- Added
  - In-game `Debug Level` option (`None` / `Debug` / `Trace`) under Extension Options, replacing the previous always-on debug output. Requires the new `Options Helper` dependency.
- Changed
  - Repeat orders are no longer limited to a fixed list of supported order types — any order placed in the `Repeat Orders` loop is now mimicked, including every one of its parameters, detected directly from the game engine instead of a hand-maintained list.
  - A single `Repeat Orders` entry is now enough to enable mimicking; the previous "needs at least two combined orders" rule has been removed.

### [1.14] - 2026-02-11

- Added
  - Support for `Update Trade Offers` order.

### [1.13] - 2025-12-08

- Added
  - Support for `Deposit Inventory` order.

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
