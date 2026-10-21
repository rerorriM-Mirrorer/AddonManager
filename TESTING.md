# TESTING — AddonManager

**Development branch:** `dev/addonmanager-v0.5-logger-audit`
**Version:** 0.5.0-dev.2
**Date:** 2026-10-21
**Status:** **User confirmed v0.5.0-dev.1 audit failure in-game; v0.5.0-dev.2 Logger fallback awaits live testing.** The existing profile loading has not been modified.

## Batch 5b — Recover loaded-addon snapshots from Logger

**Observed evidence from the user (Cioara, October 21, 2026):** Logger's daily file contained two complete `Currently loaded addons:` blocks, each including `AddonManager` and ~60 other addons, followed by `[AM] Audit inconclusive: lua list produced no captured entries (nothing assumed missing).` The user also confirmed the list appeared in the chatlog on both manual and AddonManager-invoked `lua list`. This proves Logger received the text while AddonManager's live capture did not produce entries. It does **not** establish why the two subscribers differed (event delivery, parser or timing).

**Source investigation:** Official Windower Logger `addons/Logger/Logger.lua` uses `incoming text`, strips chat colors and appends output to `Windower/logs/<Character>_YYYY.MM.DD.log`. AddonManager already used the same `incoming text` event. No Windower internal registry or silent-list API is assumed.

**New behavior:** Before each `//am audit` or `//am import loaded`, remember today's character-specific Logger file length. If the event capture has no addon entries after two seconds, inspect **only bytes appended after that watermark** (up to 128 KiB); accept only a fresh loaded-addon heading followed by at least one addon line. Old lists and header-only captures are rejected as inconclusive. The normal event capture remains preferred. All audits stay read-only; imports still require confirmation. The fallback is optional; Logger is not loaded automatically or required for other AddonManager functions.

### Install and first live checks

1. Back up the working `Windower/addons/AddonManager` directory, especially `data/`. Install the new `AddonManager` folder, including `AddonManager.lua`, `am_cluster.lua`, README, WORKFLOW and TESTING. Do not delete or replace existing profile/settings files.
2. Ensure the official Logger addon is already running on Cioara; run `//lua list` and confirm its output appears in the character's Logger log.
3. Run `//am audit` and check for `Recovered N addon names from new Logger text.`, followed by `Audit cioara: ...`. If the normal live event capture starts working, no fallback message is expected; a completed audit is still the success condition.
4. Inspect the missing/unmanaged counts against Cioara's actual saved global/character profiles. Windower-managed native addons may be reported as unmanaged and are not errors.
5. Re-run `//am audit` immediately to ensure the second snapshot is freshly collected; it must not reuse the first. An empty or absent Logger file must still yield an inconclusive report instead of claiming missing addons.
6. Optionally try `//am import loaded Cioara`; it should show a preview from a fresh list and **not save anything** until `//am import confirm`. Use `//am import cancel` after checking the preview.
7. If successful, test `//am verify on` at next login. If the built-in `lua list` chatter is undesirable, `//am verify off` suppresses automatic audits only.
8. Regression check `//am all reload trust` on two same-PC clients and existing saved profile management. No IPC logic was changed in this batch.

### Verification and safeguards

- [ ] Actual in-game Logger fallback and complete Cioara audit verified.
- [ ] No historical Logger snapshot treated as a fresh audit.
- [ ] Live imports retain preview-confirm flow and respect global subtraction.
- [ ] The `incoming text` capture remains available even when Logger isn't running.
- [ ] No addon loads, unloads, or profile saves caused by `//am audit`.
- [ ] Cross-client operations and startup remain unchanged.

**Static/mock tests:** GitHub Actions runs Lua 5.1 syntax checks, existing mock Windower profile management, three-client IPC simulation, and a Logger-only mock where event capture receives nothing. The new mock verifies a fresh Logger audit, safe import preview, stale list rejection, empty-heading rejection and no extra load commands. These tests do **not** substitute for FFXI/Windower behavior.

**Delivery register:** Fix source and test revisions `44feb069`, `11e0af90`, `55ff9238`; full branch history identifies the final package revision. Preserve the previous known-good development branch `dev/addonmanager-v0.5` for rollback.

---

# PREVIOUS TESTING — AddonManager

**Development branch:** `dev/addonmanager-v0.5`
**Version:** 0.5.0-dev.1
**Date:** 2026-10-20
**Status:** New multiclient IPC and startup verification committed for simulated and live testing. No v0.5 in-game verification yet.

## Batch 5 — Staggered load/reload and startup audit

**Install:** Back up your existing `Windower/addons/AddonManager/` folder and its `data/` directory. Extract the entire new `AddonManager/` folder, including **AddonManager.lua, am_cluster.lua, README.md, WORKFLOW.md and TESTING.md**. Leave existing `data/profiles/*.txt` and `data/options.txt` intact. Reload with `//lua reload AddonManager` on each participating client. The IPC protocol requires **the new version in every participating client**. The main/release branch is not touched; development work stays on this branch.

**Startup verification:** This build defaults `//am verify on`. A completed login profile queue waits three more seconds, executes `lua list`, then observes its incoming-text output for two seconds. Because Windower offers no documented silent `lua list`, visible list output may occur. Audit is read-only, never unloads or reloads, and an empty capture is **inconclusive**, not all missing. Use `//am verify off` if the output is distracting, and `//am audit` to test manually.

**Cross-client IPC:** From one logged-in client on the **same computer**, send `//am all load trust` or `//am all reload xivcrossbar`. Participating characters appear in alphabetical order, followed by the initiator. The default two-second stagger begins after each dispatch acknowledgement; an acknowledgement is not addon-readiness confirmation. The IPC does not reach a different PC/laptop, and `//am all reload` without an addon intentionally does nothing. Do not send the same command to all clients via Send.

### Live checklist — please report results

- [ ] On two clients, check `//am help`, `//am status`, `//am stagger` (default 2), and `//am verify`.
- [ ] `//am all load trust`: exactly one load request per participating client; initiator last; print order. Confirm no cross-client duplicate loads or unexpected hard freezes.
- [ ] `//am all reload trust`: same ordering and gap; verify actual in-game Trust UI behavior. Also try `xivcrossbar` and `switch_focus` only if installed on all clients.
- [ ] `//am stagger 2.5` changes the cross-client gap; `//am delay` still controls only within-client startup list spacing. Both save to `data/options.txt`.
- [ ] `//am all cancel` during discovery or between clients cancels remaining dispatches; no retry loops or late reloads.
- [ ] Client missing AddonManager is omitted from the roster; missing addon in a participating client rejects the batch. Ensure each client reports independently.
- [ ] One unresponsive participant stops the remaining queue after timeout; no duplicate send or infinite wait.
- [ ] Test `//am all reload` bare and `//am all reload addonmanager`: show validation errors, no widespread or self reloads.
- [ ] With a normal character login and `verify on`, wait until profile commands have dispatched + settling period. Audit reports counts; identify any expected addons falsely marked missing.
- [ ] Run `//am audit`: compare with manual `//lua list`, report counts of matched/missing/unmanaged/unresolved; do not mark native Windower addons as failures.
- [ ] With `verify off` and after a client reload, automatic audit does not run; manually running `//am audit` still works.
- [ ] If `lua list` capture fails or is empty, audit says **inconclusive** and no changes are performed. Recheck `//am import loaded` still previews and confirms correctly.
- [ ] Logout/character change during a queued load or group operation cancels remaining work.
- [ ] Confirm existing profile files, delay/startup settings, prune and import functionality remain intact.

### Verification evidence and outstanding design questions

- Prior v0.4 loaded-list import has user-confirmed success; v0.5 **not** yet tested in actual FFXI.
- New `am_cluster.lua` uses Windower same-computer IPC. Roster discovery and dispatch acknowledgements are not proof that an addon is fully initialized.
- Current v0.5 verification uses the incoming-text capture method. Verify that background startup `lua list` is observable on each client's Windower build. If not, keep this optional rather than silently claiming success.
- An audit run overlapping a manual import is skipped rather than destroying an import preview. No retries, no automatic unloading, no enforcement of unmanaged addons.
- Historical v0.4 note that the repository was named AddonToggle was accurate at its original writing; the repository was subsequently renamed **AddonManager** by the user.

**Automated result:** PASS on GitHub Actions [Lua 5.1 checks, run 39542894885](https://github.com/rerorriM-Mirrorer/AddonManager/actions/runs/39542894885), commit `fc1e73675c2edc49836c8949b126e4379199be31`: syntax validation of both addon modules and both test programs; existing mocked Windower smoke test; and three-client simulated IPC discovery, two-second dispatch spacing, initiator-last, reload, opt-out, peer refusal, cancellation and duplicate packet handling. These are **static/simulated tests only**, not actual FFXI tests.

**Development register:** Core IPC coordinator commit `e0912775`, main addon/audit integration `d3ef2cc9`, multi-client simulated test `e5992d84`. CI and corrective commits are included in branch history. Build ZIP must correspond to final branch commit and final green GitHub Actions run; use the artifact from that run. No actual FFXI tests have been performed for this version.

---

# PREVIOUS TESTING — AddonManager

**Development branch:** dev/addonmanager-v0.4
**Version:** 0.4.0-dev.2
**Date:** 2026-10-14
**Status:** v0.3 live capture confirmed by user; v0.4 rename, global exclusion and pruning await in-game validation.

## Batch 4 — Rename and global-aware character imports

**Migration precautions:** Save copies of the previous AddonToggle folder and profiles. Install under **Windower/addons/AddonManager/AddonManager.lua**, copy the previous **AddonToggle/data/** directory to **AddonManager/data/**, and disable/unload old AddonToggle before running the new manager. Update startup commands. Old //pm and //at command prefixes intentionally no longer exist. The GitHub repository itself is still named AddonToggle until the owner renames it under Settings (administration action unavailable from the connector).

- [ ] `lua load AddonManager` succeeds. `//am` and `//am help` show formatted commands; invalid `//am` shows help.
- [ ] `//am status` shows current client character, version and counts.
- [ ] The old BarFiller/EquipViewer overlay toggle has been removed; there is no `//am overlays` command.
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

## Agent instructions adoption — 2026-10-16

- Added `AGENTS.md` at this development branch's repository root to direct coding agents to the current workflow and testing records, with a canonical NPCMirror fallback when documents are missing.
- Documentation commit: [`310c3c19`](https://github.com/rerorriM-Mirrorer/AddonManager/commit/310c3c191a59f6591cb147a84936f3ea80d4246c).
- No addon code was changed or game testing performed as part of this documentation update; all previous test instructions and observations remain above.
