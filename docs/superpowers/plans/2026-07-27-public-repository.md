# macOS Hangul Switch Public Repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package the verified physical-keyboard and Moonlight/Sunshine Han/Yeong switching setup as a safe, reversible, public GitHub repository.

**Architecture:** User-level Bash scripts install a LaunchAgent that reapplies a merged `hidutil` mapping and configure macOS symbolic hotkey 60 to F18. A separate Sunshine helper adds or removes only the `0xA5 → 0x81` pair in `sunshine.conf`; all system-facing operations are injectable so integration tests run against temporary fixtures without changing the developer machine.

**Tech Stack:** macOS Bash 3.2-compatible shell, `hidutil`, `launchctl`, `defaults`, `plutil`, `awk`, Sunshine configuration, GitHub Actions on `macos-latest`

## Global Constraints

- Do not require Karabiner-Elements or another third-party key remapping application.
- Apply physical-keyboard remapping globally rather than to a specific keyboard model.
- Preserve pre-existing `hidutil`, symbolic-hotkey, LaunchAgent, and Sunshine settings whenever they do not conflict.
- Treat an existing Sunshine mapping for source `0xA5` to a destination other than `0x81` as a conflict and leave the file unchanged.
- Do not claim that Caps Lock switching or Chromium marked-text composition is fixed.
- Keep the default physical profile to HID `LANG1` and Right Alt; add Right Command only with `--right-command`.
- Do not restart Sunshine implicitly because that disconnects active Moonlight sessions.
- Support the user’s verified environment, macOS 26.3.1 on Apple Silicon, while avoiding architecture-specific paths.
- Keep tests isolated under temporary homes and fake command adapters.

---

### Task 1: Repository Baseline and Test Harness

**Files:**
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `Makefile`
- Create: `tests/test_helper.bash`
- Create: `tests/run.bash`

**Interfaces:**
- Consumes: an empty directory selected by the user
- Produces: a `main` Git repository and the `run_test`, `assert_eq`, `assert_file_contains`, and fixture lifecycle test interfaces

- [ ] **Step 1: Initialize the designated repository**

Run:

```bash
git init -b main
```

Expected: `git status --short --branch` reports `## No commits yet on main`.

- [ ] **Step 2: Add the failing test harness smoke case**

Create a runner that loads every `tests/test_*.bash` except `test_helper.bash`, prints TAP-like `ok`/`not ok` lines, and returns nonzero if any test fails.

```bash
run_test "missing installer fails smoke test" test_missing_installer
```

Expected break caught: a missing top-level `install.sh` must make the smoke test fail.

- [ ] **Step 3: Run the harness and verify RED**

Run:

```bash
/bin/bash tests/run.bash
```

Expected: nonzero exit with a failure naming the missing installer.

- [ ] **Step 4: Add repository metadata**

Use an MIT license attributed to “macos-hangul-switch contributors”, ignore `.DS_Store`, editor files, test artifacts, and local state, and expose these commands:

```make
test:
	/bin/bash tests/run.bash

lint:
	/bin/bash -n install.sh uninstall.sh status.sh scripts/*.bash tests/*.bash

verify: lint test
```

- [ ] **Step 5: Verify metadata syntax**

Run:

```bash
make lint
```

Expected: it remains RED only because production scripts do not exist yet.

### Task 2: Physical Mapping and F18 Shortcut

**Files:**
- Create: `tests/test_install.bash`
- Create: `scripts/common.bash`
- Create: `assets/com.local.global-hangul-switch.plist.in`
- Create: `install.sh`
- Create: `uninstall.sh`
- Create: `status.sh`

**Interfaces:**
- Consumes: `MHS_HOME`, optional fake `MHS_HIDUTIL`/`MHS_LAUNCHCTL`, and optional `MHS_SYMBOLIC_HOTKEYS_PLIST`
- Produces: `install.sh [--lang1-only] [--right-command] [--sunshine]`, `uninstall.sh [--keep-sunshine]`, and `status.sh`

- [ ] **Step 1: Write fixture-driven failing install tests**

The tests must execute the real scripts and assert these observable outcomes:

```text
fresh install:
  LaunchAgent exists
  LANG1 (30064771216) maps to F18 (30064771181)
  Right Alt (30064771302) maps to F18
  Right Command is absent by default
  symbolic hotkey 60 is enabled with [65535, 79, 8388608]

--right-command:
  Right Command (30064771303) maps to F18

--lang1-only:
  Right Alt remains unmapped while LANG1 still maps to F18

existing unrelated mapping:
  mapping remains in the generated hidutil JSON

repeat install:
  first-run backups are not overwritten

uninstall:
  previous LaunchAgent, mapping, and hotkey 60 are restored
```

Expected break caught: missing or destructive install/uninstall behavior.

- [ ] **Step 2: Run install tests and verify RED**

Run:

```bash
/bin/bash tests/test_install.bash
```

Expected: nonzero exit because the scripts and template do not exist.

- [ ] **Step 3: Implement shared macOS operations**

`scripts/common.bash` must:

```bash
MHS_EFFECTIVE_HOME="${MHS_HOME:-$HOME}"
MHS_STATE_DIR="$MHS_EFFECTIVE_HOME/Library/Application Support/macos-hangul-switch"
MHS_LAUNCH_AGENT="$MHS_EFFECTIVE_HOME/Library/LaunchAgents/com.local.global-hangul-switch.plist"
```

It must export/import the current symbolic-hotkey domain, convert `hidutil`’s OpenStep output into typed plist integers, merge mappings by source usage, refuse conflicts, and skip only the runtime service calls when `MHS_SKIP_RUNTIME=1`.

- [ ] **Step 4: Implement the LaunchAgent template and installer**

The generated LaunchAgent must execute:

```text
/usr/bin/hidutil property --set {"UserKeyMapping":[...]}
```

with `RunAtLoad=true` and `StartInterval=10`. The installer must save first-run backups, configure F18 as symbolic hotkey 60, generate the merged LaunchAgent, bootstrap it, and remain idempotent.

- [ ] **Step 5: Implement conservative uninstall and status**

The uninstaller must boot out the managed LaunchAgent, restore only recorded pre-install state, and warn instead of overwriting a hotkey or runtime mapping that no longer matches the installed value. Status must report physical LaunchAgent, live HID mapping, F18 shortcut, and Sunshine mapping independently.

- [ ] **Step 6: Run install tests and verify GREEN**

Run:

```bash
/bin/bash tests/test_install.bash
```

Expected: every physical-install test passes with no writes outside its temporary fixture.

### Task 3: Sunshine Configuration Merger

**Files:**
- Create: `tests/test_sunshine.bash`
- Create: `scripts/sunshine.bash`

**Interfaces:**
- Consumes: default `~/.config/sunshine/sunshine.conf` or `MHS_SUNSHINE_CONFIG`
- Produces: `scripts/sunshine.bash install|uninstall|status`

- [ ] **Step 1: Write failing Sunshine behavior tests**

Execute the real helper against fixtures and cover:

```text
no keybindings block -> append 0xA5, 0x81 and final newline
one-line block -> preserve existing pairs and add the pair
multiline block -> preserve existing pairs and add the pair
existing exact pair -> no file change
existing 0xA5 conflict -> fail and byte-preserve file
uninstall with other pairs -> remove only 0xA5, 0x81
uninstall with only managed pair -> remove the empty block
odd element count or unclosed block -> fail and byte-preserve file
```

Expected break caught: destructive or malformed Sunshine edits.

- [ ] **Step 2: Run Sunshine tests and verify RED**

Run:

```bash
/bin/bash tests/test_sunshine.bash
```

Expected: nonzero exit because the helper is missing.

- [ ] **Step 3: Implement parse-before-write behavior**

Parse the single `keybindings` block into source/destination pairs before creating a replacement. Use a temporary file in the destination directory, preserve file permissions, atomically move it into place, create a timestamped safety backup, and always terminate the result with a newline.

- [ ] **Step 4: Integrate optional Sunshine setup**

`install.sh --sunshine` must call the helper but must not restart Sunshine. `uninstall.sh` removes the managed pair unless `--keep-sunshine` is supplied.

- [ ] **Step 5: Run Sunshine and full tests GREEN**

Run:

```bash
/bin/bash tests/test_sunshine.bash
/bin/bash tests/run.bash
```

Expected: all tests pass and fixture checks prove unrelated configuration survives.

### Task 4: Public Documentation and Continuous Integration

**Files:**
- Create: `README.md`
- Create: `README.en.md`
- Create: `docs/how-it-works.md`
- Create: `docs/troubleshooting.md`
- Create: `CONTRIBUTING.md`
- Create: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: verified script flags and known limitations
- Produces: Korean-first quick start, English documentation, diagnostic guidance, contribution workflow, and macOS CI

- [ ] **Step 1: Document exact support and limitations**

The README feature table must distinguish:

```text
Physical LANG1/Right Alt: supported
Optional Right Command: supported
Moonlight/Sunshine Right Alt path: supported with --sunshine
Persistence after login/reconnect: LaunchAgent-backed
Caps Lock switching: not guaranteed / unresolved
Chromium marked-text composition issue: unresolved application behavior
```

- [ ] **Step 2: Document installation, migration, rollback, and manual restart**

Show these exact flows:

```bash
./install.sh
./install.sh --right-command --sunshine
./status.sh
./uninstall.sh
```

Explain that restarting Sunshine disconnects Moonlight and must be performed manually after saving work.

- [ ] **Step 3: Explain implementation and troubleshooting**

Describe HID usages `0x90`, `0xE6`, optional `0xE7`, F18 usage `0x6D`, macOS key code 79, and Sunshine `0xA5 → 0x81`. Include recovery steps that use the project uninstaller rather than deleting broad directories.

- [ ] **Step 4: Add CI**

Use:

```yaml
runs-on: macos-latest
steps:
  - uses: actions/checkout@v6
  - run: make verify
```

Grant only `contents: read`.

- [ ] **Step 5: Review documentation against behavior**

Run every command shown in non-mutating fixture mode or compare it to the tested command interface. Remove any claim not covered by tests or the prior real-session verification.

### Task 5: Final Verification

**Files:**
- Verify: all repository files

**Interfaces:**
- Consumes: completed implementation
- Produces: evidence-backed handoff without committing or pushing

- [ ] **Step 1: Run complete automated verification**

Run:

```bash
make verify
```

Expected: Bash syntax checks pass and the full test suite reports zero failures.

- [ ] **Step 2: Validate all plist assets**

Generate a fixture LaunchAgent through the installer and run:

```bash
plutil -lint /path/to/fixture/Library/LaunchAgents/com.local.global-hangul-switch.plist
```

Expected: `OK`.

- [ ] **Step 3: Inspect repository scope**

Run:

```bash
git status --short
git diff --check
rg -n 'Documents/Codex|sunshine_state|credentials|password|token' .
```

Expected: only intended public files are present, whitespace checks pass, and no personal absolute paths or credentials appear outside this implementation plan’s verification command.

- [ ] **Step 4: Report manual verification boundary**

State clearly that fixture automation verifies safe configuration generation and rollback, while a fresh public machine and live Moonlight reconnect remain manual integration checks.
