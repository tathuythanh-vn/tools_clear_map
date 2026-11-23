# Plan: Auto-clear (Safari raid) refill loop

Source: https://github.com/tathuythanh-vn/tools_clear_map/issues/1
Deliverables: new `run_auto_clear.ps1` + `Run_Auto_Clear.bat` (new files; do not modify `run_pokemon_stages.ps1`).

## 1. What the issue asks for

The game screen in the issue is the **Safari** raid list (not the Adventure map handled by `run_pokemon_stages.ps1`). It has a built-in auto-click toggle at the left edge (blue triangle = stopped, blue square = running). Each raid costs stamina (VIT, the red potion counter at top-left).

Decisions confirmed by the owner:
- The **VIT Purchase popup opens by itself** when VIT runs out while auto-click is running. That popup is the refill trigger. No stamina threshold and no OCR of the stamina number are needed to decide when to refill.
- Only **Hamburger** is ever used. **Bread is never used.**
- Hamburgers are not expected to run out. If they do, the script **stops** (never falls through to Buy).

Loop forever:

1. Tap the auto-click toggle to start clearing (if it shows the triangle).
2. Keep polling. While the toggle shows the square and no popup is open, do nothing.
3. When the VIT Purchase popup appears (auto-click is still showing the square), refill:
   1. Tap the toggle to stop auto-click (square -> triangle).
   2. Tap **Use Item** in the VIT Purchase popup. A "VIT Item" panel opens on the right listing Bread and Hamburger.
   3. Tap **Hamburger**. A quantity modal opens.
   4. Tap **MAX**, then **Use**.
   5. Close the VIT Purchase popup with the top-right X.
4. Tap the toggle again to resume clearing, and go back to step 2.

## 2. Hard safety constraints (from AGENTS.md, apply to the new script)

- The VIT Purchase popup contains a **Buy** button (50 diamonds -> 120 stamina) directly above **Use Item**. The script must NEVER tap it. The tap wrapper throws for any tap inside the Buy rectangle (see 3.5 and step 3 of section 4).
- **Bread** sits next to Hamburger in the VIT Item panel. The tap wrapper also blocks taps in the Bread rectangle, and the script selects the item by OCR label "Hamburger", never by position alone.
- Never tap sweep / "Raid x10" / "Raid" buttons or anything that spends diamonds. The script only ever taps: auto toggle, Use Item, Hamburger, quantity-modal MAX and Use, VIT popup close X, and Close on the "Raid Completed" dialog.
- Dispose all Bitmap/Stream objects in `finally`.
- Support `-DryRun`: classify and log what would be tapped, tap nothing.
- Stop conditions (all stop without tapping Buy):
  - **Out of Hamburgers** (see 3.4): clean stop, exit 0 with a clear "OUT OF HAMBURGERS" log line and a snapshot.
  - Any screen unrecognised for too long: exit non-zero with a snapshot.
  - A refill step does not reach its expected next state within its timeout: exit non-zero.

## 3. Design

### 3.1 Script shape

`run_auto_clear.ps1` is standalone. `run_pokemon_stages.ps1` runs its main flow at load, so it cannot be dot-sourced. Copy only the small pieces needed, using the same conventions:

- Parameters: `-AdbPath`, `-Serial`, `-OutputDir` (default `scratch`), `-DryRun`, `-MaxCycles` (0 = infinite, counts refills), `-PollSec` (default 3), `-UnknownTimeoutSec`, `-Lang`.
- Copy and trim: `Write-Log`, `Invoke-AdbRaw`, `Connect-AdbDevice`, `Capture-Screen`, `Open-UnlockedBitmap`, `Initialize-PokemonOcr` (WinRT OCR) and `Invoke-RegionOcr` (used to confirm popup titles and the "Hamburger" label).
- New: `Invoke-AdbTap` with the Buy and Bread guards, `Inspect-AutoClearScreen`, `Invoke-RefillStamina`, main loop.
- Keep `Set-StrictMode -Version Latest`, `$ErrorActionPreference='Stop'`, and 1600x900 validation (throw on any other resolution, same as `Inspect-GameScreen`).

### 3.2 Screen states to classify (pixel checks, same style as `Inspect-GameScreen`)

| State | How to detect |
|---|---|
| `AUTO_RUNNING` | toggle region has blue square, no popup open |
| `AUTO_STOPPED` | toggle region has blue triangle, no popup open |
| `VIT_PURCHASE` | popup with title "VIT Purchase" (OCR) and top-right X. Toggle may show square or triangle behind it. This is the refill trigger |
| `VIT_ITEM_PANEL` | VIT Purchase popup plus the "VIT Item" panel on the right (OCR "VIT Item") |
| `ITEM_QUANTITY` | quantity modal with MAX / Use / Cancel (OCR "Own:" and "Hamburger") |
| `RAID_RESULT` | "Raid Completed!" dialog with Close / Raid x10 |
| `UNKNOWN` | anything else: wait, retry, bail after `-UnknownTimeoutSec` |

Do not rely on a single pixel. Use a small cluster of points plus an OCR confirmation for popups, because scrolling announcement banners ("... got lucky in the Turntable ...") cross the top of the screen and overlap popup titles.

### 3.3 Detecting "out of VIT"

The game opens the VIT Purchase popup itself, so the script only watches for state `VIT_PURCHASE`. Stamina OCR is optional and used only for logging and for a post-refill sanity check (stamina after Use should be higher than before). If OCR fails, the sanity check is skipped with a warning; it never triggers or blocks a refill.

### 3.4 Main loop and out-of-Hamburger handling

```
connect adb; validate 1600x900
loop (until MaxCycles refills):
    capture; classify
    RAID_RESULT   -> tap Close, continue
    AUTO_STOPPED  -> tap toggle (start), verify AUTO_RUNNING
    VIT_PURCHASE  -> Invoke-RefillStamina, then resume (tap toggle, verify AUTO_RUNNING)
    AUTO_RUNNING  -> nothing
    UNKNOWN       -> count toward bailout
    sleep PollSec
```

`Invoke-RefillStamina` (each step waits for its expected next state, with a timeout, before the next tap):

1. Tap toggle to stop; verify triangle. (The toggle is visible behind the popup in the issue screenshots; confirm it is tappable while the popup is open.)
2. Check the green "You have VIT items in your Bag." line is present. If it is missing, there is nothing to use: stop (out of Hamburgers).
3. Tap **Use Item**; wait for `VIT_ITEM_PANEL`.
4. Find the entry labelled "Hamburger" by OCR. If not found, or its count is 0, stop (out of Hamburgers). Never tap Bread.
5. Tap Hamburger; wait for `ITEM_QUANTITY`; confirm "Hamburger" and "Own: N" with N > 0 (else stop).
6. Tap **MAX**, then **Use**.
7. Wait for the quantity modal to close; optional stamina sanity check (3.3).
8. Tap the VIT popup close X; verify back on the raid list.

The out-of-Hamburger stop saves a snapshot to `scratch/`, closes any open popup with its X or Cancel only (never Buy), and exits 0.

### 3.5 Coordinates (reference only, must be recalibrated)

Taken from the issue screenshots, which are 1919x1031 BlueStacks window captures including the title bar (~33px) and right toolbar (~32px). They are NOT 1600x900 game coordinates. Do not hardcode these.

| Target | Approx (screenshot space) |
|---|---|
| Auto toggle (triangle/square) | (98, 237) |
| Stamina counter (optional) | (325, 62) |
| Use Item (VIT popup) | (1150, 675) |
| **Buy (forbidden)** | (948, 595) |
| VIT popup close X | (1279, 306) |
| **Bread (forbidden)** | (1457, 410) |
| Hamburger item (label at ~(1457, 740)) | (1457, 637) |
| Quantity MAX | (1250, 497) |
| Quantity Use | (1100, 632) |
| Quantity Cancel | (788, 632) |
| Raid result Close | (801, 813) |

Calibration step (first task): run `adb exec-out screencap -p` to get real 1600x900 captures of each state, save under `scratch/`, and read off true coordinates. The existing `scratch/*.ps1` probe scripts show the pattern.

### 3.6 .bat launcher

`Run_Auto_Clear.bat` mirrors `Run_Pokemon_Bot.bat`: resolve `%~dp0run_auto_clear.ps1`, menu with Run (infinite), Dry Run, Run N refills, Exit, call `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...`.

## 4. Implementation steps

1. Capture reference screenshots of every state via ADB (including the auto-opened VIT popup, the item panel, the quantity modal, and an out-of-Hamburger case if reproducible); record real 1600x900 coordinates (3.5).
2. Skeleton script: params, logging, ADB connect, capture, resolution check, `-DryRun` plumbing.
3. `Invoke-AdbTap` with the Buy and Bread hard guards, plus a self-test that confirms both throw.
4. State classifier + OCR helpers; run against saved screenshots offline and print the detected state for each.
5. `Invoke-RefillStamina` with per-step state verification and the out-of-Hamburger stop; test with `-DryRun` first.
6. Main infinite loop with `-MaxCycles`, unknown-screen bailout, final-screen snapshot on exit/error.
7. `Run_Auto_Clear.bat`.
8. Update `AGENTS.md` (new entry points, Buy/Bread safety rules, calibration note).

## 5. Verification

No test suite exists; verify manually against a live BlueStacks:

1. Offline: run the classifier on the saved screenshots, expect the right state for each.
2. `-DryRun` on the live emulator: logs intended taps, performs none.
3. `-MaxCycles 1` live run, watching the first refill; confirm stamina rises and neither Buy nor Bread is touched.
4. Guard test: call the tap wrapper with coordinates inside the Buy and Bread rectangles, expect "SAFETY BLOCK" for each.
5. Out-of-Hamburger test: simulate by feeding a saved screenshot with no "Hamburger" entry (offline), expect a clean stop and no taps.
6. Long run: leave it for several cycles, check `scratch/` snapshots for stray states.

## 6. Risks

1. Scrolling announcement banners can mask popup titles, so detection must not depend on the title alone.
2. The item panel order may change (Bread above Hamburger in the issue). Select by OCR label, not position.
3. The toggle may not be tappable while the VIT popup is open. Confirm during calibration; if not, close the popup first, stop the toggle, then reopen via Use Item flow.
4. Auto-click may re-open the VIT popup right after closing if stamina is still too low (for example, MAX failed). The sanity check and a "same popup reappears within N seconds" counter should abort instead of looping.
