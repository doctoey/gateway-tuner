# gateway-tuner

`gateway-tuner` is a macOS split-tunneling helper script for temporarily adjusting route priorities and gateway metrics when you want only selected traffic to use a secondary connection.

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

Run the script from Terminal with `sudo` and choose one of the supported modes:

    sudo ./gateway-tuner CONNECT
    sudo ./gateway-tuner CLEAN

If you're running the script from another directory, replace `./gateway-tuner` with the correct path to the script.

### Typical workflow

1. Review the configuration arrays in the script.
2. Update them with the gateways, interfaces, or destination networks you want to control.
3. Run `CONNECT` to apply the routing changes.
4. Confirm the resulting routes with macOS tools such as `netstat -rn` or `route -n get <destination>`.
5. Run `CLEAN` when you are done to remove the custom routing state.

## CONNECT mode

`CONNECT` is the setup phase. In this mode, the script typically:

- identifies the interface or gateway you want to favor
- adds the configured split-tunnel routes
- adjusts route metrics or gateway priority for the selected paths
- leaves the rest of the system traffic on the normal default path unless you explicitly configure otherwise

Use this mode when you want to activate the tuned routing behavior.

## CLEAN mode

`CLEAN` is the teardown phase. In this mode, the script typically:

- removes the routes created during `CONNECT`
- clears any temporary gateway or metric adjustments
- restores the original routing behavior as closely as possible

Use this mode before disconnecting the alternate network path or whenever you want to return to the default macOS network configuration.

## Configuration arrays

The script is intended to be customized by editing the arrays defined near the top of the file. While the exact variable names depend on your local script version, the arrays generally represent:

- **destination hosts or subnets** - the traffic that should be routed differently
- **gateway or next-hop values** - where those destinations should be sent
- **interface names** - the macOS network device to use (for example, `en0` for Wi‑Fi, `en1` for Ethernet, or the interface shown by `ifconfig`)
- **cleanup targets** - the routes or entries that `CLEAN` should remove

When editing these arrays:

- use valid macOS interface and gateway values
- keep related arrays aligned so each destination matches the intended route target
- double-check CIDR blocks, IP addresses, and route order before running `CONNECT`

## Notes and safety tips

- Because this script changes live routing state, test carefully on a machine where temporary network interruption is acceptable.
- Prefer running `CLEAN` before switching networks, disconnecting VPNs, or rebooting after a tuning session.
- If a route does not behave as expected, inspect the live routing table before re-running `CONNECT`.
