#!/bin/bash
# Removes the default Internet routing via VPN and routes provided hosts back
# through the VPN.
#
# Written and tested on MacOS Sonoma 14.7. Should work on other versions too.
# su access is required due to routing table being modified.
#
# Usage:
# ./vpn-reroute.sh [-f hosts file] [...hosts]
#
# Hosts can be provided by:
# - [-f file] with host per line,
# - positional args,
# - stdin with host per line (if none were provided by other options).s
#
# Example:
# ./vpn-reroute.sh example1.internal.company.com example2.internal.company.com
# ./vpn-reroute.sh -f hosts.txt
# cat hosts.txt | ./vpn-reroute.sh
#
# How it works:
# 1. Find the gateway that routes 0.0.0.0 - if connected to a VPN, this will be
#    a utun* interface - if not, exit
# 2. Remove the 0.0.0.0 route via VPN
# 3. Find the next default route - this should be the "pre-VPN" default route
#    and re-add it
# 4. Iterate through all hosts and route them via the VPN interface

set -e

input_file=""

usage () {
    echo "Usage: $0 [-f hosts file] [...hosts]"
    exit 1
}

# Parse options
while getopts "f:" opt; do
    case "$opt" in
        # -f <path to hosts file>
        f) input_file=$OPTARG
            ;;
        *) 
            usage
    esac
done

# Shift all options parsed by getopts so we have positional args in $@
shift $((OPTIND-1))

run() {
	echo "+ $*"
	$*
}

get_default_route () {
    # Get the first default route from netstat
    netstat -nr -f inet | grep default | head -n1
}

get_default_gateway () {
    # Get gateway value from default route
    get_default_route | awk '{print $2}'
}

get_default_interface () {
    # Get interface name value from default route
    get_default_route | awk '{print $4}'
}

add_default_route () {
    # Adds a default route via provided IP address ($1)
    run route add default "$1"
}

remove_default_route () {
    # Removes a default route via interface ($1)
    run route delete -net "0.0.0.0" -ifp "$1"
}

add_hostname_route () {
    # Adds a route for given hostname ($1) via interface ($2)
    run route add -host "$1" -interface "$2"
}

# Get the default route interface name
vpn_interface=$(get_default_interface)

# If it doesn't start with utun*, exit
if [[ $vpn_interface != utun* ]] ;
then
    echo "ERROR: Internet traffic is not going through a VPN interface."
    echo "Possible causes:"
    echo " - are you connected to a VPN?"
    echo " - did you run the script already while connected to a VPN?"
    exit 1
fi

echo "Deleting VPN default route"
remove_default_route "$vpn_interface"

# The default gateway should be the gateway we want to route Internet through
default_gateway=$(get_default_gateway)

echo "Re-adding old default route"
add_default_route "$default_gateway"

hosts_provided=0

# Read hosts from input file, if provided
if [ -n "$input_file" ];
then
    hosts_provided=1
    while IFS="" read -r host || [ -n "$host" ]
    do
        echo "Redirecting $host through VPN"
        add_hostname_route "$host" "$vpn_interface"
    done < <(grep -v '^#' "$input_file")
fi

# Read hosts from positional args
if [ "$#" -gt 0 ]; then
    hosts_provided=1
    for host in "$@"
    do
        echo "Redirecting $host through VPN"
        add_hostname_route "$host" "$vpn_interface"
    done
fi

# Read hosts from stdin if none were provided before
if [ $hosts_provided -eq 0 ]
then
    while read -r host
    do
        [ -z "$host" ] && break
        echo "Redirecting $host through VPN"
        add_hostname_route "$host" "$vpn_interface"
    done < <(grep -v '^#' /dev/stdin)
fi
