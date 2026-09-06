# Sensor Battery — AI assistant guide

Garmin Connect IQ **data field** that shows battery levels for ANT+ and BLE cycling sensors on a single sorted list.

## Quick context

| | |
|---|---|
| Language | Monkey C (Connect IQ SDK 9.1.0) |
| Entry | `source/SensorBatteryApp.mc` |
| Main logic | `source/SensorBatteryView.mc` (~2000 lines) |
| BLE engine | `source/BleBatteryManager.mc` (~2200 lines) |
| Devices | 59 products in `manifest.xml` |

### Architecture at a glance

```
SensorBatteryApp
  └── SensorBatteryView (DataField)
        ├── ANT+ listeners (PM, shifting, lights, cadence, speed, radar)
        ├── BleBatteryManager (HRM / PM / Di2 round-robin BLE)
        └── onUpdate row rendering (reused buffers, font ladder)
```

BLE pairing **must** happen in `compute()`, not in scan callbacks (Garmin VM crash CIQQA-4261).

## Detailed documentation

Read these before making non-trivial changes:

| Doc | Use when |
|-----|----------|
| [docs/architecture.md](docs/architecture.md) | Class design, data flow, ANT+ vs BLE responsibilities |
| [docs/specs.md](docs/specs.md) | Behavior, timings, retries, state machines, settings |
| [docs/development.md](docs/development.md) | Build, CI, conventions, secrets |

## Coding conventions

- **Minimal scope** — focused diffs; don't refactor unrelated code.
- **No over-abstraction** — match existing patterns in `SensorBatteryView.mc`.
- **Buffer reuse** — row arrays and shift parts are pre-allocated; avoid `[]` in `onUpdate`.
- **BLE safety** — defer `pairDevice()` to `processPendingPair()` in `compute()`.
- **Identity feed** — throttle full ANT→BLE feed (`FEED_IDENTITY_INTERVAL`); use cheap live updates for active sensors.
- **Comments** — only for non-obvious logic (matching rules, Garmin quirks).

## Key files

```
source/SensorBatteryApp.mc       App entry, settings reload
source/SensorBatteryView.mc      UI, ANT+ listeners, identity feed, compute/onUpdate
source/SensorBatteryBackground.mc  White background drawable
source/BleBatteryManager.mc      BLE scan/pair/read state machine
resources/settings/              User-configurable properties
manifest.xml                     App ID, permissions, device targets
.ci/                             Podman CI build scripts
.github/workflows/               PR compile check
```

## Do not commit

`developer_key`, `bin/`, `gen/`, `mir/`, `*.prg`, `*.iq` — see `.gitignore`.

## Build

```bash
monkeyc -f monkey.jungle -d edge1050 -o bin/SensorBattery.prg -y developer_key -O3pz -w
```

CI (Podman): see [README.md](README.md) and [docs/development.md](docs/development.md).
