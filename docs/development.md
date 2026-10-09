# Development guide

Local development only — there is no CI or container build in this repo. Compile on your machine with the Garmin SDK and VS Code.

## Prerequisites

- [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) 9.1.0 (via VS Code Monkey C extension or SDK Manager)
- VS Code with Monkey C extension, or CLI `monkeyc` on your PATH
- Garmin developer key (`developer_key`) for signed builds

## Build

### VS Code

Use **Monkey C: Build for Device** from the command palette.

### CLI

```bash
monkeyc -f monkey.jungle -d edge1050 -o bin/SensorBattery.prg -y developer_key -O3pz -w
```

Replace `edge1050` with any device ID from `manifest.xml`.

## Conventions

- **Monkey C** — no unnecessary abstractions; match existing patterns in `SensorBatteryView.mc`
- **Buffer reuse** — row arrays (`mRowSortKeys`, `mRowTexts`, `mRowColors`) and shift display parts are pre-allocated and reused in `onUpdate`
- **BLE pairing** — must happen in `compute()`, not in `onScanResults` callback (Garmin VM crash CIQQA-4261)
- **Identity feed** — throttle full ANT→BLE feed; use cheap live updates for active sensors
- **Minimal scope** — focused diffs; don't refactor unrelated code

## Do not commit

Listed in `.gitignore`:

```
/bin /dist /gen /mir /internal-mir
SensorBattery.prg* SensorBattery.iq SensorBattery-settings.json
developer_key
```

## Key paths

| Path | Purpose |
|------|---------|
| `source/SensorBatteryView.mc` | Main UI and ANT+ logic |
| `source/BleBatteryManager.mc` | BLE state machine |
| `resources/settings/` | User-configurable properties |
| `manifest.xml` | App metadata and device targets |
| `monkey.jungle` | Build entry point |

## Tests

The Jungle source paths include `tests/`. Test fixtures and entry points use
`(:test)` and are excluded from normal builds.

```bash
monkeyc -f monkey.jungle -d edge530 -o bin/SensorBattery-test.prg -y developer_key -O3pz -w -t
connectiq
monkeydo bin/SensorBattery-test.prg edge530 -t
```

Repeat normal and test builds and simulator tests for `edge1050`. Check the final
`PASSED`/`FAILED` summary: the local SDK's `monkeydo` can return exit code 1 even
when every test passes. Fixtures cover BLE matching, deferred pairing, failure
recovery, sample timing, and the view's ANT identity feed. Real Garmin hardware
is still needed to validate BLE timing and memory usage with actual sensors.
