# TESTING — AddonManager

**Branch:** `fix/addonmanager-console-timestamps-20261022`
**Version:** 0.5.0-dev.6
**Date:** 2026-10-22
**Status:** Killala's new real FFXI Logger capture revealed a native-console timestamp prefix which made quiet audits fail. A minimal parser fix and exact-prefix Lua 5.1 regression have passed CI; **the new patch has not been tested in-game**. Preserve the user-confirmed dev.3 safe-reload baseline.

## Batch 5f — Native console timestamp/prompt prefix

**Uploaded user evidence:** `Killala_2026.10.22(3).log` (Killala, 2,650 decoded lines) reports:
- At log line 2633, `[AM] Safe reload: auditing global + killala before any load requests.`
- Line 2634: `[AM] Audit inconclusive (console.log: unexpected console text: 20:58:48 >   autoex). No changes made.`
- Line 2635: `[AM] Safe reload: no addons loaded because verification was inconclusive.`
- Lines 2638–2640 repeat the sequence, with `20:58:58 >   autoex`.
This establishes the immediate failure as an **unhandled `HH:MM:SS >` prefix**, not a glint runtime-error line. The earlier Cioara glint spam and error-line handling remain separate observations; the full native `console.log` excerpt was not uploaded.

**Fix:** In `am_console.lua`, for each fresh captured log line, remove *only* the optional `HH:MM:SS >` clock/prompt prefix and retain following indentation. Then apply the unchanged begin/end marker, heading, two-space name, interleaving, incomplete-list, error-line and safe-reload checks. Lines without the prefix remain unchanged. This is parsing-only: no changes to addon loading, character profile files, IPC, logging settings, or command behavior.

**Verification:**
- [x] Lua 5.1 syntax and mocked profile, IPC and console-capture tests pass on GitHub Actions.
- [x] Regression test supplies the exact `20:58:48 >   autoex` format with timestamped start/end markers and heading, and checks that `autoex`, `Battle Stations`, and `AddonManager` are extracted.
- [x] Regression confirms a timestamped GilFinder-like Lua error can be ignored without treating it as an addon, while unrelated timestamped chatter still aborts the capture.
- [x] Previously supported unprefixed lists, stale lists, truncated lists, foreign-client markers and incomplete captures retain tests.
- [ ] **Live Killala check:** reload AddonManager or run `//am audit`; it should complete a list-based audit rather than reject `autoex`.
- [ ] **Live Franklet check:** confirm the same quiet-console path works independently on his client.
- [ ] Repeat a missing-only reload using one harmless addon; verify no extra loads.
- [ ] If failure persists, capture the marker-bounded `console.log` excerpt and check another formatting variant before expanding accepted inputs.

**Related but separate observations from these two character Logger logs:** Killala reports frame-rate 30 FPS twice (after a 60 FPS setting); Franklet reports a 60→30 transition twice. These logs alone do not identify the addon that changed the FPS. Franklet also reports five XIVCrossbar messages that `pet` set was absent for his BST/WAR job. Neither issue is changed in this patch.

**Delivery:** Working branch and commit identified at packaging; preserve preceding `dev/addonmanager-v0.5-console-noise` and `dev/addonmanager-v0.5-safe-reload` branches. No `main` changes; no FFXI live test claimed for this fix.

---

# PREVIOUS TESTING — AddonManager

**Branch:** `dev/addonmanager-v0.5-console-noise`
**Version:** 0.5.0-dev.5
**Date:** 2026-10-22
**Status:** Cioara live quiet-console audit produced an **inconclusive result** while GilFinder spammed a glint.lua line-30 nil-index runtime error. Error handling revised and mocked tests passed; no live re-test yet. Previously confirmed safe-reload and missing-only behavior remains preserved on a separate branch.

## Batch 5e — Interleaved Lua errors during console list

**User evidence (2026-10-22):** The user ran `//am audit` using quiet console mode, saw repeated GilFinder `glint.lua:30` “attempt to index field … (nil value)” messages, and received `Audit inconclusive (console.log: unexpected console text inside loaded list)`. This does not by itself prove the GilFinder error was the precise rejected line, but the two symptoms occurred together. Audit was read-only and rejected the untrusted list instead of loading anything. Original `console.log` excerpt has not been supplied.

**Fix:** The marker-bounded parser now ignores only recognizable Lua runtime-error and stack-trace lines (`.lua:<number>`, `stack traceback:`, or `attempt to index`) interspersed with normal indented addon rows. It still requires the same unique begin/end markers, proper heading, nonempty entries, no other-client markers, and strict resolution of captured names before safe-reload can load missing addons. It returns a count of ignored error lines for a concise chat report. Any other unexpected console line remains **inconclusive**, now quoting a short offending excerpt to aid diagnosis. Neither the capture mode nor existing safe-reload, startup, or IPC behavior was changed.

**Follow-up tests:**
- [ ] With GilFinder loaded, `//am audit` should return a summary if only recognized Lua errors contaminate the console capture.
- [ ] Confirm that `console.log` still contains a complete heading/addon list and both matching AM markers.
- [ ] If still inconclusive, copy a small excerpt of `Windower/console.log` between `AM_LIST_BEGIN_...` and `AM_LIST_END_...`, omitting unrelated private lines, to calibrate the parser rather than disabling safeguards.
- [ ] Unload or disable malfunctioning GilFinder as needed before continued testing. The independent glint guard is on `rerorriM-Mirrorer/Windower-Addons` branch `fix/gilfinder-glint-index-20261022` for separate verification.
- [ ] Confirm successful audit creates no loads; a deliberate one-addon unload still results in one missing-only load after AddonManager restart.
- [ ] Confirm malformed/interleaved console output still aborts the audit and loads nothing.

**Verification:** GitHub Actions Lua 5.1 syntax + smoke/IPC and console parser regression passed on the development branch. The new parser test injects GilFinder-like error lines between ordinary addon rows, validates the expected count, and confirms unfamiliar log text still fails. This is simulated/static verification, not live FFXI.

**Git tracking:** code commits `1e9d7e22`, `ed8415ac`, `87d727cd`, repaired clean console parser `1808b20e`. Preserve `dev/addonmanager-v0.5-quiet-console` (last quiet-console development revision) and `dev/addonmanager-v0.5-safe-reload` (user-confirmed chat/Logger version). No changes to `main`.

---

# PREVIOUS TESTING — AddonManager

**Branch:** `dev/addonmanager-v0.5-quiet-console`
**Version:** 0.5.0-dev.4
**Date:** 2026-10-21
**Status:** The previous v0.5.0-dev.3 Cioara safe-reload/no-work and GilFinder-only recovery paths are **confirmed live** by the user. **Quiet console-file capture is experimental and has only simulated verification.** Main and the earlier development branches are preserved.

## Batch 5d — Quiet console list capture

**User request and evidence:** After confirming `//am restart` loaded only previously-unloaded GilFinder on Cioara, the user requested eliminating the long `lua list` output from the in-game chatlog. The user successfully ran `//lua list console` and prefers its native console display. The user noted we have ConsoleBGPlus and suggested capturing the native `console.log` rather than the official Logger chatlogs.

**Source findings:** On the `consolebg-plus` branch of `rerorriM-Mirrorer/Windower-Addons`, `addons/ConsoleBGPlus/ConsoleBGPlus.lua` runs `console_log 1` in its native-profile synchronization and activity command. ConsoleBGPlus does **not** read `console.log` to render; it draws a frame around Windower's native console, which renders the text itself. The ConsoleBGPlus source notes that console-file growth may come from another client, so capture must not confuse interleaved output. Windower documents `console_log 0|1` for controlling file logging to `Windower/console.log`; the native console is built in, but console-file logging is optional. Do not assume the Config plugin enables it.

### Experimental design

- `//am capture console` is the **default** for this build. `//am capture chat` retains the known-good `lua list` + incoming-text/Logger path. The choice is persisted as `capture=console|chat` in `data/options.txt`.
- Console capture reads the existing console log's current end position; issues `console_echo "AM_LIST_BEGIN_<token>"`, `lua list console`, then `console_echo "AM_LIST_END_<token>"`. It only accepts a freshly appended result with matching markers, the expected heading and indented addon names.
- An absent logfile, inactive logging, absent marker, missing end marker, duplicate heading, unexpected list text, or an overlapping marker from another client yields **inconclusive**; no automatic saved-profile loads occur. This is safer than guessing a client identity from a shared file.
- The manager does **not** run `console_log 1` or `console_log 0`, alter console popup settings, or silently revert to chat. `//am audit` stays read-only; loaded-import remains preview-before-confirmation; `//am apply` remains the user's explicit unfiltered load operation.
- On fresh character login, existing load behavior remains unchanged; only the post-load audit uses the selected capture method.
- The previous safe-reload branch is preserved and is the recovery option if console output formatting is unexpected.

### Live test checklist — pending

1. **Back up** the working `Windower/addons/AddonManager/` folder and keep the existing `data/` settings/profiles. Install complete `AddonManager/` from ZIP; do not replace the existing data.
2. Start Cioara with **ConsoleBGPlus already running**. In the console, `//lua list console` should continue to show the addon list. Confirm `Windower/console.log` actually grows; if it doesn't, check `console_log 1` or revert using `//am capture chat`.
3. Run `//am capture` (should say `console`). Then `//am audit`; expect a one-line summary **without a full list in FFXI chat**. The native Windower console may show the full list.
4. Reload AddonManager while logged in; expect only begin/list/end console commands for verification and **zero duplicate addon loads** if all configured entries are running.
5. Unload a nonessential listed addon such as GilFinder, then `//am restart`. Expect only that addon to load again, without the long in-game list.
6. Check `//am import loaded` still previews only and `//am import cancel` leaves profiles untouched.
7. Try `//am capture chat` and a manual audit; verify the prior Logger fallback remains functional. Switch back with `//am capture console` if successful.
8. With no current `console.log` activity, confirm the preflight says inconclusive and queues **zero addons**. Restore logging with your usual settings rather than letting AM change it. Do not deliberately break a working client mid-combat.
9. Run near-concurrent audits on two clients and inspect any overlapping output. A collision should fail closed, never produce an apparently authoritative merged list.
10. Compare file source names with the actual console output; if indentation or prefixes differ, preserve logs for a parser-only follow-up rather than bypassing completeness checks.

### Automated verification and remaining risks

The GitHub Actions workflow checks Lua 5.1 syntax, previous profile and IPC regressions, direct console snapshot tests for stale/partial/empty/interleaved output, and mocked integration of `lua list console` into safe reload. This does **not** demonstrate actual Windows console.log formatting or Windower's command ordering. No in-game success is asserted for dev.4 until user reports it.

**Delivery register:** Development commits and CI run to be confirmed at delivery. No changes to the known-good `dev/addonmanager-v0.5-safe-reload` branch or main. Preserve all prior testing history below.

---

# PREVIOUS TESTING — AddonManager

**Branch:** `dev/addonmanager-v0.5-safe-reload`
**Version:** 0.5.0-dev.3
**Date:** 2026-10-21
**Status:** Automated Lua 5.1 syntax and simulated checks passed. **Live Cioara safe-reload all-present and GilFinder-only recovery confirmed by user on 2026-10-21.** Snapshot-failure behavior, exact capture source, and quiet-output alternatives remain unverified in-game. Previous branches preserved.

## Batch 5c — Audit before addon reload; load only missing addons

**Live user report (2026-10-21, Cioara):** Following an AddonManager restart during gameplay, user reported: **“All configured addons already running. Nothing to load.”** This confirms the live audit's all-present/no-work decision in that session. The report does not establish which capture path succeeded, prove that no underlying Windower command was emitted beyond the audited decision, or validate missing-only loading and inconclusive handling. Those remain pending.

**Second live user report (2026-10-21, Cioara):** User deliberately unloaded `gilfinder`, ran `//am restart`, and reported **“only gilfinder reloaded!”** This confirms the successful missing-only recovery path for that addon in the live client, in addition to the previously reported all-present/no-load result. Exact capture mechanism and failure-mode behavior were not independently observed. The user also noted that the full `lua list` chatlog output is too long and requested a quiet/redirected verification mechanism.

**Quiet audit investigation (2026-10-21):** Windower developer Arcon documented `lua list console` as directing list output to the Windower console rather than the FFXI chatlog (Windower forum 2015). Windower also documents `console_log 1|0` logging console output to `Windower/console.log`. A console-file capture with per-request markers may be a possible experiment, but its behavior with multiple concurrent clients and existing console_log settings is **not verified**. `incoming text` callbacks can return a block value, but blanket blocking risks affecting Logger fallback or other chat. Avoid altering the known-good branch's capture/suppression until a separately tested solution exists. References: https://forums.windower.net/index.php?showtopic=724 ; https://docs.windower.net/commands/console/ ; https://docs.windower.net/addons/pluginmanager/ .

**User request:** Reloading AddonManager while already playing should avoid issuing 30+ redundant `lua load` requests. It should automatically inspect the client's currently loaded addons, compare them with the saved global and character profiles, and load only entries genuinely absent. The user also asked how Logger gets its text and whether AddonManager can use Logger's stream for verification.

**Source verification:** The official Windower Logger addon listens to `windower.register_event('incoming text', ...)`, strips color codes and saves messages to dated `Windower/logs/<Character>_YYYY.MM.DD.log`. AddonManager already registers the same event, but the user's Cioara live evidence showed Logger receiving full `lua list` entries while AM's own audit saw none. Batch 5b added an optional fresh-file fallback (watermark before query). This batch retains that fallback; it does not copy Logger into the addon or create an unsupported API.

**Behavioral change:**
- When AddonManager's `load` event runs **while a character is already logged in**, and `//am startup on`, it waits 0.5 seconds, audits current-client runtime addons, and **does not queue normal startup profile loads before the audit**.
- Only a captured, mappable list **including `AddonManager` itself and no unresolved display names** is eligible to authorize automatic loads. Matched expected addons are omitted from the queue; only missing items are queued, at the existing `//am delay` interval.
- On a failed/incomplete capture, folder scan error, or concurrent capture, automatic reload performs **zero profile load requests**, reports a reason, and leaves installed/loaded addons alone. **No retry.**
- After missing-load dispatches, `//am verify on` optionally performs the existing post-queue read-only audit. `//am verify off` suppresses only this *additional* audit; it does **not** bypass safe reload preflight.
- Actual **new character login** event continues the existing delayed profile queue, unchanged. `//am apply` remains the explicit **unfiltered** way to load the full combined profile, should the player choose to do so.
- Profiles/settings are not edited during a reload audit. Logout/unload/generation invalidation prevents continuing obsolete operations.
- Same-computer IPC coordinator `//am all load|reload` is unchanged.

### Install + in-game tests (pending)

1. Back up `Windower/addons/AddonManager/`, especially `data/profiles/` and `data/options.txt`. Extract the complete replacement addon folder containing `AddonManager.lua`, `am_cluster.lua`, `README.md`, `WORKFLOW.md`, `TESTING.md`; **do not replace the existing `data/` directory.**
2. On an already-playing Cioara with Logger running, run `//lua reload AddonManager`. Expect `Safe reload: auditing...`, an audit summary (or Logger recovery notice), then **no load requests** if all configured addons are running. Confirm no duplicate-load errors. **PARTIALLY CONFIRMED LIVE:** User reported all configured running / nothing to load after restart; no detailed console trace or explicit duplicate-error check supplied.
3. Deliberately unload one noncritical addon that exists in the profile, then reload AddonManager again. Expect **only that addon** to receive `lua load`. Verify visually/in `lua list`. **CONFIRMED LIVE:** GilFinder was unloaded and only GilFinder reloaded after `//am restart`; detailed console trace not provided.
4. With all entries already running, reload AddonManager again. Expect a successful audit and **zero load requests**.
5. Reproduce failed capture safely by unloading Logger (where AM's own live-event capture is also known to fail). Reload AM; it must say verification was inconclusive and **issue no load requests**. Restore Logger manually.
6. Try `//am verify off` then `//lua reload AddonManager`: the safety preflight must still run, but no additional post-queue audit follows. Restore `//am verify on` as desired.
7. Test actual logout/login or character selection separately. Fresh login retains the previous three-second-delayed profile queue; do not assume the reload tests establish fresh-login success.
8. Confirm `//am audit` and `//am import loaded` still produce read-only output and preview-first imports, and the cross-client `//am all reload trust` command remains unaffected.
9. On an inconclusive safe reload, use `//am apply` *only if you deliberately want the old unfiltered load behavior*. It is not an automatic fallback.

### Automated checks and remaining limits

GitHub Actions checks both addon Lua files and smoke programs with Lua 5.1, executes the baseline simulated profile-manager tests, the new reload tests (one missing, all present, incomplete/missing capture), Logger-only recovered reload, and the three-client IPC simulation. A passing test is **not equivalent to actual FFXI testing**.

**Caution:** Requiring an `AddonManager` entry and zero unmatched display names is a conservative *completeness guard*, not cryptographic proof that Windower emitted every addon. No documented silent `lua list` argument is used. Future versions could add a robust authoritative registry query if one becomes available.

**Delivery register:** Core safe reload `922f9999`; simulated tests `a024cd7c` and Logger-only scenario `ea221953`; documentation and final packaging commits tracked on this branch. No modifications to the previously tested dev.1/2 branches or to `main`. Final downloadable ZIP must correspond to the final passing GitHub Actions commit and retain all required package documents.

---

# PREVIOUS TESTING — AddonManager

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
