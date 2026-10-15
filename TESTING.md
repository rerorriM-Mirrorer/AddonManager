# TESTING — AddonManager

**Development branch:** dev/addonmanager-v0.4
**Version:** 0.4.0-dev.1
**Date:** 2026-10-14
**Status:** v0.3 live capture confirmed by user; v0.4 rename, global exclusion and pruning await in-game validation.

## Batch 4 — Rename and global-aware character imports

**Migration precautions:** Save copies of the previous AddonToggle folder and profiles. Install under **Windower/addons/AddonManager/AddonManager.lua**, copy the previous **AddonToggle/data/** directory to **AddonManager/data/**, and disable/unload old AddonToggle before running the new manager. Update startup commands. Old //pm and //at command prefixes intentionally no longer exist. The GitHub repository itself is still named AddonToggle until the owner renames it under Settings (administration action unavailable from the connector).

- [ ] `lua load AddonManager` succeeds. `//am` and `//am help` show formatted commands; invalid `//am` shows help.
- [ ] `//am status` shows current client character, version and counts.
- [ ] `//am overlays` preserves the historical BarFiller/EquipViewer toggle.
- [ ] `//am list global` and `//am list Cioara` preserve copied v0.3 profile files.
- [ ] With global containing an addon, `//am import loaded Cioara` excludes it; preview also excludes entries already in Cioara.
- [ ] `//am import loaded global` captures full loaded snapshot minus global's already saved entries; there is no global subtraction of itself beyond deduplication.
- [ ] `//am import confirm` adds only the previewed character extras; `//am import cancel` leaves profiles untouched.
- [ ] `//am prune Cioara` lists only overlap between global and Cioara, no immediate file modification.
- [ ] `//am prune cancel` preserves file; `//am prune confirm` removes only previewed overlapping entries, does not unload any running addon, and leaves global unchanged.
- [ ] `//am apply` and `//am load all` load global+current with one load request per entry and 1-second default staggering.
- [ ] Restart and change character/client: per-character lists remain separate; no duplicate management from the retired addon.
- [ ] Inspect `console.log` for syntax/runtime errors and `//lua list` for runtime confirmation.

**Design note:** Cioara and global may contain identical broadly imported lists from initial test. Curate global *before* pruning and before concluding other character imports are complete. Prune never guesses which addons should be global.

**Observed from user-provided v0.3 test evidence:** The user confirmed that loaded-list imports functioned and shared saved global/Cioara profile files showing imported entries. This upgrades the previous v0.3 capture uncertainty; it is not evidence v0.4 itself has been run in game.

---

# HISTORICAL TESTING — AddonToggle / Profile Manager

**Development branch:** dev/profile-manager-v0.3
**Version:** 0.3.0-dev.1
**Date:** 2026-10-14
**Status at original delivery:** Live loaded snapshot had not yet been confirmed. **Subsequently confirmed by user** following v0.3 test.

## First install

Back up the existing addon folder and startup scripts. Disable Windower's original plugin_manager. Put AddonToggle.lua in Windower/addons/AddonToggle/. Keep current launcher/init.txt addon load settings during the first isolated tests. Test only with a nonessential addon before migrating any core UI tools.

## Batch 3 — Live loaded-addon capture (experimental)

User feedback: on 2026-10-14 the user reported that profile management was working well and that the //pm scan catalog could help with imports. The uploaded global profile contained equipviewer, while Cioara's profile contained barfiller. The captured Cioara chat log showed one //lua list snapshot with 54 loaded addon display names, and //pm scan all reported 69 installed folder entries. All 54 names in that snapshot matched the installed folder catalog after ignoring capitalization and spaces, including Battle Stations and Job Change. This is not evidence that a live incoming-text capture through the new addon works.

- [ ] Before installing v0.3, back up your existing AddonToggle folder and data/profiles directory.
- [ ] //pm load all requests global + active-character addons (same as //pm apply). Prior Cioara live log revealed "all: no addons to load" on the previous version; this corrects that.
- [ ] //pm import loaded Cioara requests //lua list in **this** Windower client.
- [ ] Loaded output is captured after ~2 seconds; the preview shows an appropriate number of entries and any missing/ambiguous names.
- [ ] The preview correctly resolves display names with spaces (Battle Stations, Job Change) to real folder names.
- [ ] AddonToggle and plugin_manager themselves are never included in a new profile.
- [ ] No profile changes before //pm import confirm.
- [ ] //pm import cancel leaves the saved profile unchanged.
- [ ] //pm import confirm appends previously absent addon names only; file contents survive addon reload.
- [ ] //pm import loaded global explicitly targets global list.
- [ ] If capture fails (no incoming-text event or empty list), manager reports a failure and does not prepare/save an import.
- [ ] //pm scan all remains a separate installed-folder inventory command.
- [ ] Existing //at toggle, persistent profiles, manual load/unload, and auto-login staggering still work.

Note: the uploaded console log contains some duplicate-load errors for EquipViewer and BarFiller, which were already running when further load requests were issued. AddonToggle does not yet know confirmed runtime states; this is a later optimization, not a claimed fix in v0.3.

---

## Batch 1 — Profile and lifecycle checks

- [ ] //lua load AddonToggle: no Lua console errors.
- [ ] //pm, //pm help and an invalid //pm command display formatted help.
- [ ] //at retains the BarFiller/EquipViewer toggle.
- [ ] //pm status reports the present character.
- [ ] //pm add global EquipViewer and //pm list global: entry appears.
- [ ] //pm add Cioara BarFiller and //pm list Cioara: entry appears.
- [ ] Repeated add is idempotent.
- [ ] //pm remove Cioara BarFiller edits saved file without unloading BarFiller.
- [ ] Re-add, //lua reload AddonToggle, then list: entry persists.
- [ ] //pm load Cioara from another character's client loads Cioara's list in that client, without modifying its own saved list.
- [ ] //pm unload Cioara unloads only Cioara's listed addons in current client.
- [ ] //pm unload global and //pm unload all request unloads, without trying to unload the manager itself.
- [ ] //pm apply requests global + current character entries once each.
- [ ] //pm delay 1 saves across reload.
- [ ] //pm startup off prevents automatic load, while manual commands continue to work.
- [ ] Actual character login with startup on loads only after in-world login with ~3-second safety buffer; one-second spacing between requests.
- [ ] Logout interrupts a pending startup queue.
- [ ] With two clients, each selects its own current character profile. (Do not edit the same profile simultaneously.)

## Batch 2 — Discovery and import experiments

- [ ] //pm scan lists installed addon folders and //pm scan all prints the complete catalog.
- [ ] //pm import init global previews recognized lua load commands from Windower/scripts/init.txt without writing them yet.
- [ ] //pm import cancel leaves file unchanged.
- [ ] //pm import legacy Cioara previews original plugin_manager Cioara addon entries (if that XML is present).
- [ ] Create AddonToggle/data/import.txt with valid addon names; //pm import file Cioara previews additions.
- [ ] //pm import confirm saves additions and //pm list Cioara displays them.
- [ ] Duplicate, invalid and missing addon names are skipped.

## Evidence and notes

Record exact commands, character names, addon names, output and console errors. Please share observations from at least one character and two concurrent clients. Windower currently offers //lua list to independently verify runtime state.

### Known limitations under test

There is no automatic unloading of finished addon loads at logout; only queued work is canceled. The program cannot enumerate currently running Lua addons, and completion of issued load/unload commands is not verified. Concurrent writes to one profile are not protected. No DLL plugin management or priority cycling.

## Delivery register and history

- Original v1.0: Single //at toggle. No supplied original live test report.
- 2026-10-14 Batch 1: New profiles/startup/list commands; awaiting live testing.
- 2026-10-14 Batch 2: Installed directory scan and preview/import experiments; user reported profile manager works well; specific test boxes not yet individually verified.
- 2026-10-14 Batch 3: Live-loaded import from //lua list added; initially awaiting live verification. Subsequently confirmed by user to work; the observed imported profile files were supplied.

Historical test records have not been fabricated. Corrections and later test findings should be appended, preserving the history.
