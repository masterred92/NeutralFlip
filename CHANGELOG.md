# Changelog

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
