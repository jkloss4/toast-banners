# Toast Banners

Cinematic on-screen banners, like the game's zone text, for zone and subzone changes, quests, scenarios,
achievements, boss emotes, level ups and rares defeated. Each one replaces Blizzard's own banner or alert for that
event; turning a type off brings Blizzard's back.

Made for WoW: Forever (Interface 16001); also lists retail (Interface 120100).

The banners are the Presence module of [Horizon Suite](https://www.curseforge.com/wow/addons/horizon-suite) (MIT), by
Crystilac, without the rest of the suite. The banner files keep Horizon Suite's names (`Presence*.lua`) and code, so
changes from upstream can be compared and brought over. `Core.lua` and `Helpers.lua` provide the parts of Horizon
Suite's core they use.

## Changes from Horizon Suite

- **Settings page in Blizzard's style:** **Options > AddOns > Toast Banners** (or `/toastbanners`), with General,
  Notifications, Typography and Colors tabs, and a size (Large, Medium or Small) for each notification type.
- **Preview on screen:** **Show Preview** plays the real banner, above the settings window. While it's showing, it
  changes with the settings you change.
- **Colors tab:** every notification type can have its own main title, divider line and subtitle colors (and
  "Discovered" line color, for zone banners).
- **Main title spacing:** under *Typography > Large / Medium / Small Notifications*, the space between the main title
  and the divider line.
- Typography labels say *Main Title* and *Subtitle* (Horizon Suite: *Primary* and *Secondary*), and *colors*.

`/toastbanners demo` plays every banner, one after another.

## Install

Download `ToastBanners-<version>.zip` from the [latest release](../../releases/latest) and extract the `ToastBanners`
folder into `World of Warcraft\_classic_beta_\Interface\AddOns\` (retail: `_retail_`).

An addon manager that installs from GitHub releases (e.g. WowUp: *Install from URL* with this repo's URL) can also
install and update it.

Don't run it alongside Horizon Suite with its Presence module on, or every banner shows twice.

## Developing / releasing

- Test local changes: `.\scripts\install-local.ps1` copies the addon folder into the Forever `AddOns`, then `/reload`.
- After a WoW patch: bump `## Interface:` in `ToastBanners/ToastBanners.toc`.
- Release: `git tag v1.0.1 && git push --tags`. The [Release workflow](.github/workflows/release.yml) stamps the
  version into the TOC, builds the zip (with a `release.json` for addon managers), and publishes the GitHub release.

## License

MIT ([`LICENSE`](LICENSE), also included in the addon folder), covering both this addon and the Horizon Suite code it
is based on.
