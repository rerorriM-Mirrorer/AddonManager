# AddonManager

**Author:** Max and A
**Development version:** 0.5.0-dev.3
**Windower:** FFXI / Windower 4 (Lua 5.1)
**Commands:** //am

Manage **Lua addons** with persistent global and per-character lists. Inspired by Byrth's Windower plugin_manager, but implemented independently; no original Plugin Manager source is copied. **Windower DLL plugins are not managed yet.**

## Installation

1. **Back up** your working Windower/addons/AddonToggle folder, especially `data/profiles/`, `data/options.txt`, and any imported lists.
2. Create Windower/addons/AddonManager/ and place **AddonManager.lua, am_cluster.lua, and README.md** there. Copy the **existing AddonToggle/data/** folder into **AddonManager/data/** to retain every profile and option.
3. Disable the original AddonToggle and Windower plugin_manager in startup configuration; do not run two profile managers simultaneously. Keep the old AddonToggle folder as an offline backup.
4. Load from the console with `lua load AddonManager` or enable the new folder through the Windower launcher. Type `//am help`.
5. Replace references to old `//pm` and `//at` commands in macros and scripts; **neither alias is registered**. The BarFiller/EquipViewer pair-toggle has been retired.
6. **v0.5.0-dev.3 is a development build awaiting live FFXI validation.** This build adds audit-before-loading on AddonManager reload and retains the Logger recovery added in dev.2. Back up profiles and options; on a failed snapshot, nothing is loaded automatically.

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
| //am apply | Explicitly load global + current character (unfiltered/forced) |
| //am all load ADDON | Load one named addon, one same-PC client at a time |
| //am all reload ADDON | Reload one named addon, one same-PC client at a time |
| //am all cancel | Cancel the current cross-client batch |
| //am stagger [seconds] | Read or change cross-client gap (default 2s, 0.1–10) |
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
| //am audit | Compare loaded addons with global + this character; read-only |
| //am verify on/off | Enable/disable audit after startup queues (default on) |
| //am status | Show character, counts, and request totals |
| //am restart | Reload AddonManager itself |
| //am unload manager | Explicitly unload AddonManager itself |

Example: //am add global ConsoleBGPlus and //am add Cioara EnemyBar2. Then //am load Cioara from **Myrr's** client issues load requests for the entries in Cioara's saved list, without changing Myrr's profile or loading Cioara's global additions. //am apply specifically loads global + the current character.

Every add/remove immediately saves a plain text file, e.g. data/profiles/global.txt or data/profiles/cioara.txt. Editing is independent of loading. Duplicate entries are suppressed. Saved startup options are kept in data/options.txt.


## Multi-client stagger (v0.5)

Run `//am all load trust` or `//am all reload xivcrossbar` **from one Windower client**. Only other *logged-in* clients on the **same computer** running this AddonManager version can answer its IPC discovery; a separately running laptop is not reached. Participants are sorted alphabetically, with the initiating character last. Commands issue sequentially with a default **two-second gap between acknowledgements**. Change it from the initiating client with `//am stagger 2.5`; this option persists in AddonManager/data/options.txt.

The addon validates actual installed addon folders before dispatch. Only `load` and `reload` of a specific addon are allowed; management addons are protected. `//am all reload` **without an addon** deliberately displays usage rather than reloading 50+ addons at once. `//am all cancel` stops a pending batch. A peer that refuses a request or fails to acknowledge it causes the batch to stop; **there is no automatic retry**. Acknowledgements confirm command dispatch, *not successful addon initialization*. Do not rebroadcast the same command using Send, or each client may try to start a separate batch.

`//am delay` remains the **within-client** profile queue spacing. `//am stagger` controls **between-client** one-addon operations. Neither feature automatically applies a whole profile to other clients.

## Startup verification (v0.5)

On a **fresh character-login event**, AddonManager retains the existing automatic profile queue; after it finishes dispatching commands, the manager leaves a three-second settling interval, then requests `lua list` on **that client**. It compares the observed names against global plus that character's profile, displaying the number matched, missing, unmanaged, and unresolved. Missing configured entries are listed; the report is **read-only** and never retries or unloads anything. Windower-managed native addons appearing as unmanaged are normal.

Use `//am audit` to repeat the same snapshot manually, or `//am verify off` to stop automatic post-login audits. Startup verification is on by default. A failed or empty `lua list` capture is reported as **inconclusive**, not treated as every addon being missing. A capture already in progress isn't overwritten.

**Logger fallback (v0.5.0-dev.2):** If AddonManager's own `incoming text` listener captures no names, it checks `Windower/logs/<Character>_YYYY.MM.DD.log`, written by Windower's official **Logger addon** when Logger is running. It records the file's end position **before** requesting `lua list`, then accepts only a new heading and names appended since that position. Old entries never count as proof. The report announces when a fresh Logger snapshot was used; the fallback is optional and does not start Logger or change any profiles. If neither source works, the new inconclusive message distinguishes the missing incoming-text heading from missing/empty Logger output.

**Visibility:** Windower's documented `lua list` has no supported silent argument. AddonManager avoids an additional verbose chat report on success, but cannot guarantee that Windower's own list output remains invisible. The capture first tries incoming-text events and, only if those yield no names, the fresh Logger append. The new fallback still needs live FFXI confirmation; neither method grants direct access to LuaCore's loaded-addon registry.


## Safe reload reconciliation (v0.5.0-dev.3)

**Reloading or loading AddonManager while already logged into a character** now starts with a read-only **preflight `lua list` audit**. Nothing from the saved global/character profiles is loaded beforehand. AddonManager uses the same live incoming-text capture and optional fresh Logger-file fallback as the manual audit. The new snapshot must include `AddonManager` itself and contain **no unresolved display names** before it can authorize missing-only loads.

If the snapshot is trustworthy, the manager compares it with `global.txt` plus the active character profile, then queues only the missing names, using the existing `//am delay` spacing. If all are loaded, it reports that and sends **no load commands**. If a fresh trustworthy snapshot is unavailable, it reports the reason and **sends zero automatic loads**. There are no speculative loads, retries, automatic unloads, or saved-profile changes. The original **login-event startup behavior is unchanged** in this batch.

`//am verify off` controls the *extra after-startup audit*, **not the safety-critical reload preflight**. `//am startup off` still disables automatic management. If audit fails and you intentionally wish to issue every saved load request anyway, `//am apply` remains the **explicit unfiltered command**.

The preflight's `lua list` output may still appear in the chatlog; Windower does not provide a documented silent variant. Logger is not required, but may help recover the list when AddonManager's own listener fails. This is a conservative first iteration: a valid but nonmatching or incomplete list causes no automatic loads, even if addons genuinely are missing.

## Experimental imports

**Live loaded-addon import (v0.4):** Run `//am import loaded` from a logged-in client. It defaults to that character's profile. The command runs `lua list` and captures current-client output through incoming-text events (or newly appended Logger output if necessary), then maps display names (e.g. `Battle Stations`) to installed folder names. It excludes AddonManager, historical AddonToggle, and plugin_manager.

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
- **2026-10-20 / Batch 5 (v0.5.0-dev.1):** Acknowledged same-computer IPC for one-addon staggered load/reload, adjustable two-second gap, safe cancellation, post-login live-list verification, manual audit, and switchable read-only startup checks.
- **2026-10-21 / Batch 5b (v0.5.0-dev.2):** Optional fresh Logger-file fallback for audits/imports after user-observed live-text capture failure; reject old/empty snapshots, report capture-source reasons, and retain read-only audit behavior.
- **2026-10-21 / Batch 5c (v0.5.0-dev.3):** Mid-session manager reload now audits first and issues load requests only for verified missing profile entries; failed or partial captures stop automatic loading without disturbing existing addons. Fresh character-login startup behavior preserved.

## Attribution

The design was informed by Byrth's [Windower plugin_manager](https://github.com/Windower/Lua/tree/dev/addons/plugin_manager), but that code is not bundled. For working practices, see WORKFLOW.md. For the first test run, follow TESTING.md.
