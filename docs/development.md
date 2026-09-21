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
