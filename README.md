# VPN Reroute

Removes the default Internet routing via VPN and routes provided hosts back
through the VPN.

Written and tested on MacOS Sonoma 14.7. Should work on other versions too.
`su` access is required due to routing table being modified.

## Usage

```
./vpn-reroute.sh [-f hosts file] [...hosts]
```

Hosts can be provided by:

-   `[-f file]` with host per line,
-   positional args,
-   stdin with host per line (if none were provided by other options).

### Example

```sh
./vpn-reroute.sh example1.internal.company.com example2.internal.company.com
./vpn-reroute.sh -f hosts.txt
cat hosts.txt | ./vpn-reroute.sh
```

## How it works

1. Find the gateway that routes 0.0.0.0 - if connected to a VPN, this will be
   a `utun*` interface - if not, exit
2. Remove the `0.0.0.0` route via VPN
3. Find the next default route - this should be the "pre-VPN" default route
   and re-add it
4. Iterate through all hosts and route them via the VPN interface
