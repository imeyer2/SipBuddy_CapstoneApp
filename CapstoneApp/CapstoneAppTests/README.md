# SipBuddy Test Suite

## Overview

This directory contains the **unit tests** for SipBuddy. A companion set of **UI tests** lives in `../CapstoneAppUITests/`. Together they verify that core logic is correct and that the app launches and behaves properly from a user's perspective.

---

## Test Files at a Glance

| File | Type | What it covers |
|---|---|---|
| `CapstoneAppTests.swift` | Unit | BLE device persistence, `KnownDevice` serialisation, notification names |
| `FR2ParsersTests.swift` | Unit | Streaming binary parsers (`SigFinder`, `BUFHeaderParser`, `FR2Assembler`) |
| `../CapstoneAppUITests/CapstoneApp_UITests.swift` | UI | Sign-up and login flows against Firebase Auth |
| `../CapstoneAppUITests/CapstoneAppUITests.swift` | UI | Basic launch and launch-performance benchmarks |
| `../CapstoneAppUITests/CapstoneAppUITestsLaunchTests.swift` | UI | Launch screenshot capture across UI configurations |

---

## Why These Tests Matter

### BLE Device Persistence (`CapstoneAppTests`)
SipBuddy pairs with a BLE hardware device. If known-device data is lost, corrupted, or sorted incorrectly, users would have to re-pair every session. These tests guarantee:

- **`testKnownDeviceCodableRoundTrip`** — A `KnownDevice` can be encoded to JSON and decoded back without data loss. This protects against silent schema drift that could wipe saved pairings.
- **`testBLEManagerLoadsAndSortsKnownDevices`** — Devices stored in `UserDefaults` are loaded at init and sorted most-recent-first so the UI always shows the right default connection.
- **`testBLEManagerKnownDeviceLookupAndRemoval`** — Lookup (`isKnownDevice`) and removal work correctly, ensuring the "forget device" feature actually deletes the entry.
- **`testAutoConnectEnabledPersists`** — The auto-connect toggle round-trips through `UserDefaults`, so flipping it in Settings survives an app restart.
- **`testNotificationNamesExist`** — Guards the raw string values of custom `Notification.Name`s (`SB.didStartIncident`, `SB.forceDefaultDetect`). A typo here would silently break cross-module communication.

### Binary Protocol Parsers (`FR2ParsersTests`)
SipBuddy receives a live camera stream from its BLE device using a custom binary protocol (`BUF` headers and `FR2` frames). These parsers reassemble JPEG frames from fragmented BLE packets. Bugs here would produce corrupt frames or crashes.

- **`testSigFinderBasic` / `testSigFinderOverlapping`** — Validates the streaming signature matcher that detects the start of each header. The overlapping test (`"ABABA"` → 2 matches of `"ABA"`) ensures the state machine resets correctly at boundaries — a common source of off-by-one bugs.
- **`testBUFHeaderValidAcrossChunks`** — Feeds a BUF header split across four separate `consume()` calls to simulate real-world BLE fragmentation. Verifies that width, height, and frame count are parsed correctly regardless of chunk boundaries.
- **`testBUFHeaderIncomplete`** — Confirms the parser stays in a "waiting" state when it receives an incomplete signature and does not falsely report a header.
- **`testFR2AssemblerValid`** — Constructs a full FR2 frame (header + JPEG payload) and feeds it in small, irregular fragments. Asserts the assembled JPEG exactly matches the original payload and that `takeJPEG()` resets the assembler for the next frame.
- **`testFR2AssemblerZeroSize`** — Edge case: a frame with a zero-byte payload should immediately report `done` and return empty data rather than hanging or crashing.
- **`testFR2AssemblerInvalidAndPostDone`** — After assembly is complete, further calls to `consume()` must return 0 (no bytes consumed). Prevents the assembler from accidentally eating bytes that belong to the next frame.

### UI & Auth Tests (`CapstoneAppUITests/`)
- **`testCreateAccountFlow`** — Drives the sign-up form end-to-end: fills email/password, taps "Create Account", and asserts the Welcome screen appears. Catches regressions in the auth → onboarding transition.
- **`testLoginFlowWithProvidedCredentials`** — Same flow for an existing account. Skips gracefully via `XCTSkip` when CI credentials are not provided, so the test never fails due to missing secrets.
- **`testLaunchPerformance`** — Uses `XCTApplicationLaunchMetric` to flag launch-time regressions.
- **`testLaunch` (LaunchTests)** — Captures a screenshot of the launch screen under every UI configuration (`runsForEachTargetApplicationUIConfiguration = true`). The screenshot is saved as a test attachment (`lifetime = .keepAlways`) for visual review after each run.

---

## How We Know the Tests Are Doing Their Jobs

### 1. Assertions that mirror real invariants
Each test encodes a concrete invariant the app depends on (e.g., "decoded device == original device"). If the invariant breaks, either the test itself is wrong (unlikely after code review) or the production code has regressed.

### 2. Edge-case and fragmentation coverage
The parser tests deliberately simulate worst-case BLE behaviour — packets arriving one byte at a time, overlapping signatures, zero-length payloads. Passing these cases gives high confidence that happy-path streaming will also work.

### 3. Isolation via setup/teardown
`clearBLEUserDefaults()` wipes `UserDefaults` before and after every BLE test. This guarantees tests don't pass because of leftover state from a previous run, and don't pollute future runs.

### 4. Skip guards for environment-dependent tests
UI tests that require Firebase or CI credentials use `XCTSkip` instead of force-failing. This means a green test run always reflects genuine success, not a silenced failure.

### 5. Deterministic data construction
All binary headers are built byte-by-byte inside the test with known widths, heights, and payload sizes. The expected output is mathematically determined — there is no external file or network dependency that could introduce flakiness.

### 6. CI integration
These tests run on every push via the project's GitHub Actions workflow. A red build on `main` blocks merging, so regressions are caught before they ship.

---

## Running the Tests

```bash
# Unit tests (no device/simulator required for parser tests)
xcodebuild test \
  -project CapstoneApp.xcodeproj \
  -scheme CapstoneApp \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# UI tests only
xcodebuild test \
  -project CapstoneApp.xcodeproj \
  -scheme CapstoneApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:CapstoneAppUITests
```

Or press **⌘U** in Xcode to run the full suite.
