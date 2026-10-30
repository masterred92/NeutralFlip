# Changelog

## 0.3.0
- One scan feeds every addon: when PriceLog, MatTooltip or GoldPerSpot is installed, an AH scan is shared, never repeated within 15 minutes.
- Each side's price now shows its own age, and an empty list says when you last scanned.
- A short guide on first login.
- Tooltip: one block shared with MatTooltip, so the AH price is never shown twice.
- Shows as one entry in the shared "Kenny's addons" display-bar menu.
- `/nflip debug` checks your setup: client version, every game API the addon needs, and which of Kenny's other addons it is working with.
- A loud chat warning if this client is missing an API the addon needs, instead of failing silently.
- English text now lives in `Locales/enUS.lua`, ready for translations.
- Shared code (KennyShared) is identical in every addon of the family and checked in CI, along with every Blizzard API call (against the Forever UI source) and every DBM/BigWigs/Questie API call (against their source).

## 0.2.0
- `/nflip way [bootybay|gadgetzan|everlook]`: a TomTom arrow to a neutral AH (needs TomTom). The spots are approximate and get you to the town.
- LibDataBroker display (Titan Panel, ChocolateBar, Bazooka...): flip count, top five in the tooltip, left-click opens the list, right-click sets the TomTom arrow.
- Tests now fail CI on any luacheck warning, and the API check also covers TomTom and LibDataBroker calls.

## 0.1.0 (first public release)
- Added the CurseForge and Wago project IDs to the TOC for automatic packaging, and an icon for the AddOns list (`media/icon.tga`).
- First version. Keeps faction and neutral AH prices apart, detected by zone or map, with a deposit-rate cross-check and a manual override.
- Lists flips in both directions, net of the 5%/15% cut, with deposit at risk, freshness and quantity caps, and a thin-market flag.
- Tooltip shows both prices and the flip. Uses your own searches and full scans, including scans started by PriceLog or MatTooltip.
- Game version: WoW: Forever 1.60.1 (Interface 16001).
