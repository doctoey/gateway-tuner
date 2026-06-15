# route.bash

`route.bash` is a macOS split-tunneling helper script for temporarily adjusting route priorities and gateway metrics when you want only selected traffic to use a secondary connection.

## What it does

The script is designed around two operating modes:

- **CONNECT** - applies the split-tunneling changes, adds or updates the configured routes, and tunes gateway preference so the selected destinations use the intended path.
- **CLEAN** - removes the routes and metric changes created by `CONNECT`, restoring the machine to its normal networking state.

This makes it useful for workflows where you need to send only part of your traffic through a VPN, hotspot, tethered link, or alternate gateway without changing the entire system default route permanently.

## Prerequisites

Before running the script, make sure you have:

- **macOS** - the script is intended for macOS networking tools and routing behavior.
- **sudo access** - route and gateway changes require elevated privileges.
- **A known target interface/gateway** - verify the network interface and gateway values you plan to tune.

## Usage

Before running the script for the first time, ensure it has executable permissions:

```bash
chmod +x route.bash