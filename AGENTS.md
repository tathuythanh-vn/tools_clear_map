# AGENTS.md – Pokemon Stage Runner Bot

## Project Overview
BlueStacks automation bot for Pokemon game stage/dungeon clearing. Pure PowerShell with zero external dependencies (uses WinRT OCR, C# LockBits for pixel analysis, ADB for emulator control).

## Running the Bot

**Entry point:** `Run_Pokemon_Bot.bat` (interactive menu on Windows)
- Calls `run_pokemon_stages.ps1` with appropriate flags
- Menu options: Quick Run, Custom Run, Auto-Chain, List Maps

**Direct PowerShell:**
```powershell
.\run_pokemon_stages.ps1 -MapName "Tinh Ca Sa Mac" -Mode Hard -StartStage 1 -EndStage 5
```

## Auto-Clear (Safari Raid) Bot

**Entry point:** `Run_Auto_Clear.bat` → `run_auto_clear.ps1` (separate from the stage runner).

Keeps the game's built-in auto-click toggle running on the **Safari raid** screen forever. When VIT (stamina) runs out the game opens the "VIT Purchase" popup by itself; the script then stops the toggle, taps **Use Item** → **Hamburger** → **MAX** → **Use**, closes the popup, and resumes. Loops until out of Hamburgers (clean stop) or `-MaxCycles` refills.

**Key parameters:**
- `-DryRun`: classify + log intended taps, perform none
- `-MaxCycles N`: stop after N refills (0 = infinite)
- `-Calibrate`: capture the live screen + open a click-to-read-coordinates viewer
- `-SelfTest`: verify the tap safety guards (no ADB needed)
- `-ClassifyFile <png>`: classify a saved screenshot offline (no ADB)

**MUST calibrate before a live run:** all UI coordinates live in the `CALIBRATION TABLE` at the top of `run_auto_clear.ps1` and ship as placeholders. Run `-Calibrate` on each screen state (raid list, VIT popup, item panel, quantity modal, raid result) and fill in real 1600×900 values. The script refuses to run live until every coordinate is set.

**Safety rules (do NOT violate) — extra to the stage runner:**
- Never tap **Buy** in the VIT Purchase popup (spends diamonds) — hard guard in `Test-TapGuard`
- Never tap **Bread** — only Hamburger is ever used (hard guard)
- Never tap **Raid x10** / sweep buttons (hard guard)
- Out of Hamburgers → stop cleanly (exit 0), never fall through to Buy

## Key Script Parameters
- `-MapName`: Vietnamese chapter name or ASCII alias (see `locales/en.json` chapters)  
- `-Mode`: "Normal"/"Thuong" or "Hard"/"Elite"/"TinhAnh" (default: Normal)
- `-StartStage` / `-EndStage`: 1–50 (EndStage 0 = run to chapter end)
- `-SkipCleared`: Skip stages with ≥1 star already earned
- `-Chain`: Auto-advance to next chapter when current clears
- `-ListMaps`: List all chapter names/aliases without fighting
- `-DryRun`: Navigate to stage, log lock/star status, save preview PNG, **do not tap "Vào ải"**
- `-StageTimeoutSec`: Max seconds per battle (default 120)
- `-AdbPath`: BlueStacks ADB path (default: `C:\Program Files\BlueStacks_nxt\HD-Adb.exe`)
- `-Serial`: ADB device (default: `127.0.0.1:5555`)
- `-OutputDir`: Screenshot output (default: `scratch/`)
- `-Lang`: "auto"/"en"/"vi" (default: auto)

## Critical Implementation Details

**Stage selection:** 1600×900 resolution hardcoded. Dynamically scrolls stage list to any Ải N (1–50) using 7-segment number decoding and pixel analysis.

**OCR engine:** WinRT (native Windows.Media.Ocr.OcrEngine). Requires English language pack installed or falls back to user profile languages.

**Safety rules (do NOT violate):**
- Never tap "Tiếp" (1500, 700) on Victory screen → tap "Tiếp tục" (1500, 805) instead to return to STAGE_MODAL
- Never tap sweep buttons or spend diamonds
- Skip battles when `-DryRun` or `-ListMaps` set
- Dispose all Bitmap/Stream objects in finally blocks

**Victory detection:** Waits for VICTORY_EVAL state (stage complete or failed), never force-closes battle.

## Directory Structure
```
tools_clear_map/
├── run_pokemon_stages.ps1       # Stage/dungeon automation script
├── Run_Pokemon_Bot.bat            # Windows menu entry point (stage runner)
├── run_pokemon_stages.bat         # (secondary launcher)
├── run_auto_clear.ps1             # Safari raid auto-clear + VIT refill loop
├── Run_Auto_Clear.bat             # Windows menu entry point (auto-clear)
├── locales/
│   ├── en.json                    # English chapter names & aliases
│   └── vi.json                    # Vietnamese chapter names
├── scratch/                       # Screenshot output (auto-created)
└── AGENTS.md                      # This file
```

## Language Support
- Locales define chapter names, stage/button UI strings
- `-Lang auto`: detect from system; `-Lang vi` / `-Lang en`: override
- Chapter aliases allow flexibility: "Tinh Ca Sa Mac" = "Tình Ca Sa Mạc" (diacritics optional)

## Common Workflows

**List all maps:**
```powershell
.\run_pokemon_stages.ps1 -ListMaps
```

**Preview stage without fighting:**
```powershell
.\run_pokemon_stages.ps1 -MapName "Dong Bang Sao" -Mode Hard -StartStage 7 -DryRun
```

**Clear stages 1–10, skip already-cleared:**
```powershell
.\run_pokemon_stages.ps1 -MapName "Tình Ca Sa Mạc" -StartStage 1 -EndStage 10 -SkipCleared
```

**Auto-chain: clear all chapters in sequence:**
```powershell
.\run_pokemon_stages.ps1 -MapName "Tình Ca Sa Mạc" -Chain
```

## Configuration for Agents
- **No build/test/lint:** This is automation tooling, not a library. No package.json, no CI.
- **No git user config:** Existing commits use default system user. Set if committing new work.
- **Image artifacts:** Screenshots saved to `scratch/`. Existing `scratch/` captures are committed; new ones are untracked until added.
- **ADB must be installed:** BlueStacks ADB at default path or pass `-AdbPath`.
- **WinRT OCR:** Windows 10+ only; requires at least one OCR language pack (en-US preferred).

## Common Pitfalls
- Forgetting `-DryRun` before testing a new chapter → bot enters battle unintended
- Stage timeout too short on slow devices → increase `-StageTimeoutSec`
- Map name typo → use `-ListMaps` to verify exact names
- Tapping victory button wrong → safe code returns to STAGE_MODAL, never soft-locks
- Auto-clear: running a live loop before calibrating → script refuses to start (by design); run `-Calibrate` first
- Auto-clear: scrolling announcement banners can mask popup titles → classifier anchors on "Use Item" / "Own:" / gold X, not the title
- PowerShell 5.1: `New-Object Type($a, $b, $expr * $expr, ...)` with unparenthesized binary expressions in the arg list fails to unroll into constructor args — precompute into plain variables first
