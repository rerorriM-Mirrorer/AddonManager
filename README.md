# AddonToggle / Profile Manager

**Author:** Max and A
**Development version:** 0.3.0-dev.1
**Windower:** FFXI / Windower 4 (Lua 5.1)
**Commands:** //pm, //at

Manage **Lua addons** with persistent global and per-character lists. Inspired by Byrth's Windower plugin_manager, but implemented independently; no original Plugin Manager source is copied. **Windower DLL plugins are not managed yet.**

## Installation

1. Back up your existing AddonToggle and Windower startup scripts.
2. Install AddonToggle.lua under Windower/addons/AddonToggle/.
3. Disable the original plugin_manager (it could conflict with this manager).
4. Enable AddonToggle in the Windower launcher or type //lua load AddonToggle.
5. Use //pm help to begin. The addon creates data/profiles/ and saves one text file per profile.
6. **This is a development build, not live-tested in FFXI.** Initially manage nonessential addons only. Do not remove existing init.txt loading until the new profiles have been verified.

AddonToggle itself should be started through Windower, so that it receives actual character login events. Other addon startup arrangements may remain independent.

## Profile commands

| Command | Action |
| --- | --- |
| //pm or //pm help | Show commands |
| //pm list [global/character] | Show profile (default = current character) |
| //pm add [global/character] ADDON | Save addon entry; running state unchanged |
| //pm remove [global/character] ADDON | Delete entry; running state unchanged |
| //pm load [global/character] | Issue loads from the selected list on this client |
| //pm unload [global/character] | Issue unloads from the selected list on this client |
| //pm load all | Load the combined global and current-character lists (same as //pm apply) |
| //pm unload all | Unload the combined global and current-character lists |
| //pm apply | Load global + current character (deduplicated) |
| //pm scan [all] | List installed Lua addons (not currently running addons) |
| //pm import loaded [profile] | Capture this client's //lua list and preview new entries | 
| //pm import init [profile] | Preview import of scripts/init.txt |
| //pm import legacy [profile] | Preview original plugin_manager XML profile |
| //pm import file [profile] | Preview data/import.txt |
| //pm import confirm or cancel | Save preview or discard it |
| //pm delay [seconds] | Set spacing between load requests (0–10, default 1) |
| //pm startup on/off | Enable or disable auto-loading on character login |
| //pm status | Show character, counts, and request totals |
| //pm restart | Reload AddonToggle itself |
| //pm unload manager | Explicitly unload AddonToggle itself |
| //at | Preserve historical BarFiller/EquipViewer toggle |

Example: //pm add global ConsoleBGPlus and //pm add Cioara EnemyBar2. Then //pm load Cioara from **Myrr's** client issues load requests for the entries in Cioara's saved list, without changing Myrr's profile or loading Cioara's global additions. //pm apply specifically loads global + the current character.

Every add/remove immediately saves a plain text file, e.g. data/profiles/global.txt or data/profiles/cioara.txt. Editing is independent of loading. Duplicate entries are suppressed. Saved startup options are kept in data/options.txt.

## Experimental imports

**Live loaded-addon import (v0.3 test):** Run //pm import loaded Cioara (or //pm import loaded global) from the client whose running addons you want to copy. AddonToggle invokes Windower's lua list and attempts to observe its chat output through the incoming-text event that Windower Logger uses. After a short capture window, the manager previews addon names normalized to actual installed folders. It skips plugin_manager and AddonToggle, deduplicates already-listed entries, and flags unmatched display names. Run //pm import confirm to **merge** additions into the saved profile, or //pm import cancel to discard the preview. The command never immediately loads/unloads the captured addons.

The feature is **experimental**: if this Windower installation does not expose the lua list output to incoming-text listeners, no preview will be created. This is a snapshot of one client, not continuous runtime tracking. //pm scan scans installed folders instead; those are *not* evidence of current runtime state.


All imports are **preview-first**. Run //pm import init global to inspect recognized Lua load commands from Windower/scripts/init.txt; finish with //pm import confirm or //pm import cancel.

Run //pm import legacy Cioara to copy the original Plugin Manager's **addon** entries for Cioara from addons/plugin_manager/data/settings.xml. The selected name is both source and destination. DLL plugin entries are ignored.

Run //pm import file Cioara to read plain addon names (one per line, optional # comments) from AddonToggle/data/import.txt. Duplicates are removed, and missing addon names are skipped when directory scanning succeeds.

## Important behavior and limitations

- Automatic profiles apply after **actual character login**, with an initial three-second delay, not at character selection.
- Profiles apply additively: global + character, with duplicate load requests suppressed.
- Individual //pm load and //pm unload commands act on the named profile **alone**.
- //pm unload global can unload an addon also referenced by a character profile; this is a command, not a reference-counted ownership model. Self-unloading of AddonToggle and plugin_manager through list operations is blocked.
- Logout cancels queued work; **this version does not automatically unload already running addons when a character logs out**. Be cautious when switching characters in a single client.
- Status tracks **requested** loads and unloads, never claims confirmed runtime state. Use the Windower //lua list command to verify.
- Installed-addon scan checks for a folder containing a same-named Lua entrypoint and does not reveal the runtime list.
- Concurrent writes by multiple clients to the **same profile file** are not transactionally protected yet. Edit from one client at a time.
- The preserved //at toggle still uses a simple boolean (no runtime verification).
- No priority cycle or character-specific exclusions yet.

## Changelog

- **Original v1.0:** Max's //at toggle for BarFiller and EquipViewer.
- **2026-10-14 / 0.2.0-dev.1 / Batch 1:** Saved profiles; global and character login loading; stagger interval; list editing; explicit load/unload; preserved //at alias.
- **2026-10-14 / Batch 2 experimental:** Addon directory scan; safe preview/confirmation imports from init.txt, legacy XML, and plain text.
- **2026-10-14 / Batch 3 experimental (v0.3):** Capture Windower's loaded-addon list through incoming-text events; reconcile spaced display names against installed addon folders and preview safe merge-only profile import.

## Attribution

The design was informed by Byrth's [Windower plugin_manager](https://github.com/Windower/Lua/tree/dev/addons/plugin_manager), but that code is not bundled. For working practices, see WORKFLOW.md. For the first test run, follow TESTING.md.
