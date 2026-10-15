# AddonManager

**Author:** Max and A
**Development version:** 0.4.0-dev.2
**Windower:** FFXI / Windower 4 (Lua 5.1)
**Commands:** //am

Manage **Lua addons** with persistent global and per-character lists. Inspired by Byrth's Windower plugin_manager, but implemented independently; no original Plugin Manager source is copied. **Windower DLL plugins are not managed yet.**

## Installation

1. **Back up** your working Windower/addons/AddonToggle folder, especially `data/profiles/`, `data/options.txt`, and any imported lists.
2. Create Windower/addons/AddonManager/ and place AddonManager.lua and README.md there. Copy the **existing AddonToggle/data/** folder into **AddonManager/data/** to retain every profile and option.
3. Disable the original AddonToggle and Windower plugin_manager in startup configuration; do not run two profile managers simultaneously. Keep the old AddonToggle folder as an offline backup.
4. Load from the console with `lua load AddonManager` or enable the new folder through the Windower launcher. Type `//am help`.
5. Replace references to old `//pm` and `//at` commands in macros and scripts; **neither alias is registered**. The BarFiller/EquipViewer pair-toggle has been retired.
6. **v0.4 is a development build not yet tested live.** The preceding v0.3 live snapshot capture was successfully tested in game on 2026-10-14. Preserve your original init.txt loading until you verify startup behavior on each client.

AddonManager itself should be started through Windower, so that it receives actual character login events. Other addon startup arrangements may remain independent.

## Profile commands

| Command | Action |
| --- | --- |
| //am or //am help | Show commands |
| //am list [global/character] | Show profile (default = current character) |
| //am add [global/character] ADDON | Save addon entry; running state unchanged |
| //am remove [global/character] ADDON | Delete entry; running state unchanged |
| //am load [global/character] | Issue loads from the selected list on this client |
| //am unload [global/character] | Issue unloads from the selected list on this client |
| //am load all | Load the combined global and current-character lists (same as //am apply) |
| //am unload all | Unload the combined global and current-character lists |
| //am apply | Load global + current character (deduplicated) |
| //am scan [all] | List installed Lua addons (not currently running addons) |
| //am import loaded [profile] | Capture this client; for characters, exclude global + already saved entries | 
| //am import init [profile] | Preview import of scripts/init.txt |
| //am import legacy [profile] | Preview original plugin_manager XML profile |
| //am import file [profile] | Preview data/import.txt |
| //am import confirm or cancel | Save preview or discard it |
| //am prune [character] | Preview entries in this character's list already covered by global |
| //am prune confirm or cancel | Save proposed removal or discard it; no runtime unloading |
| //am delay [seconds] | Set spacing between load requests (0–10, default 1) |
| //am startup on/off | Enable or disable auto-loading on character login |
| //am status | Show character, counts, and request totals |
| //am restart | Reload AddonManager itself |
| //am unload manager | Explicitly unload AddonManager itself |

Example: //am add global ConsoleBGPlus and //am add Cioara EnemyBar2. Then //am load Cioara from **Myrr's** client issues load requests for the entries in Cioara's saved list, without changing Myrr's profile or loading Cioara's global additions. //am apply specifically loads global + the current character.

Every add/remove immediately saves a plain text file, e.g. data/profiles/global.txt or data/profiles/cioara.txt. Editing is independent of loading. Duplicate entries are suppressed. Saved startup options are kept in data/options.txt.

## Experimental imports

**Live loaded-addon import (v0.4):** Run `//am import loaded` from a logged-in client. It defaults to that character's profile. The command runs `lua list` and captures current-client output through incoming-text events, then maps display names (e.g. `Battle Stations`) to installed folder names. It excludes AddonManager, historical AddonToggle, and plugin_manager.

For any **character** target, it subtracts both the **saved global profile** and entries already present in the character profile. For **global** itself, it subtracts only entries already saved in global. The preview reports the total observed, global-covered count, already-saved count, protected names, and unmatched names. `//am import confirm` saves just new entries after rechecking global; `//am import cancel` discards them. This never immediately loads or unloads an addon.

The original v0.3 `lua list` capture was confirmed in real FFXI on 2026-10-14; the v0.4 global-aware filtering and rename still need in-game testing. It captures one client at a time, not a persistent registry.

**Prune profile overlaps:** Once you've chosen the intended shared baseline in `global.txt`, run `//am prune Cioara` to review which Cioara entries are already in global. `//am prune confirm` removes only those previewed overlaps that remain in global; `//am prune cancel` keeps everything. The process never modifies global or the runtime. It is intentionally not automatic because global may initially contain an overly broad imported list.

**Important:** If global is a copy of Cioara's full loaded snapshot, other characters' import previews will correctly treat those entries as shared, even if they do **not** belong on all characters. Curate global **before** pruning character profiles.

All imports are **preview-first**. Run //am import init global to inspect recognized Lua load commands from Windower/scripts/init.txt; finish with //am import confirm or //am import cancel.

Run //am import legacy Cioara to copy the original Plugin Manager's **addon** entries for Cioara from addons/plugin_manager/data/settings.xml. The selected name is both source and destination. DLL plugin entries are ignored.

Run //am import file Cioara to read plain addon names (one per line, optional # comments) from AddonManager/data/import.txt. Duplicates are removed, and missing addon names are skipped when directory scanning succeeds.

## Important behavior and limitations

- Automatic profiles apply after **actual character login**, with an initial three-second delay, not at character selection.
- Profiles apply additively: global + character, with duplicate load requests suppressed.
- Individual //am load and //am unload commands act on the named profile **alone**.
- //am unload global can unload an addon also referenced by a character profile; this is a command, not a reference-counted ownership model. Self-unloading of AddonManager and plugin_manager through list operations is blocked.
- Logout cancels queued work; **this version does not automatically unload already running addons when a character logs out**. Be cautious when switching characters in a single client.
- Status tracks **requested** loads and unloads, never claims confirmed runtime state. Use the Windower //lua list command to verify.
- Installed-addon scan checks for a folder containing a same-named Lua entrypoint and does not reveal the runtime list.
- Concurrent writes by multiple clients to the **same profile file** are not transactionally protected yet. Edit from one client at a time.
- No priority cycle or character-specific exclusions yet.

## Changelog

- **Original v1.0:** Max's //at toggle for BarFiller and EquipViewer.
- **2026-10-14 / 0.2.0-dev.1 / Batch 1:** Saved profiles; global and character login loading; stagger interval; list editing; explicit load/unload; preserved //at alias.
- **2026-10-14 / Batch 2 experimental:** Addon directory scan; safe preview/confirmation imports from init.txt, legacy XML, and plain text.
- **2026-10-14 / Batch 3 experimental (v0.3):** Capture Windower's loaded-addon list through incoming-text events; reconcile spaced display names against installed addon folders and preview safe merge-only profile import. **Live capture subsequently confirmed by user.**
- **2026-10-14 / Batch 4 experimental (v0.4):** Rename installable addon to AddonManager with //am only; exclude global entries from character loaded imports; preview-confirm character pruning for existing global duplicates.
- **2026-10-14 / Batch 4 refinement (v0.4.0-dev.2):** Remove the now-unneeded historical BarFiller/EquipViewer toggle and its command entirely.

## Attribution

The design was informed by Byrth's [Windower plugin_manager](https://github.com/Windower/Lua/tree/dev/addons/plugin_manager), but that code is not bundled. For working practices, see WORKFLOW.md. For the first test run, follow TESTING.md.
