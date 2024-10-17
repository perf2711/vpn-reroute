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
# 1. Find the default route - if connected to a VPN, this will route via 
#    a utun* interface - if not, exit
# 2. Find the next default route - this should be the "pre-VPN" default route
# 3. Remove the 0.0.0.0 route via VPN
# 4. Re-add the pre-VPN default route
# 4. Iterate through all hosts and route them via the VPN interface

set -e

input_file=""
dry_run=0

usage () {
    echo "Usage: $0 [-f hosts file] [...hosts]"
    exit 1
}

# Parse options
while getopts "nf:" opt; do
    case "$opt" in
        # -f <path to hosts file>
        f) input_file=$OPTARG
            ;;
        n) dry_run=1
            ;;
        *) 
            usage
    esac
done

# Shift all options parsed by getopts so we have positional args in $@
shift $((OPTIND-1))

hosts=()

# Read hosts from input file, if provided
if [ -n "$input_file" ];
then
    while IFS="" read -r host || [ -n "$host" ]
    do
        hosts+=("$host")
    done < <(grep -v '^#' "$input_file")
fi

# Read hosts from positional args
if [ "$#" -gt 0 ]; then
    hosts=( "${hosts[@]}" "$@" )
fi

# Read hosts from stdin if none were provided before
if [ ${#hosts[@]} -eq 0 ]; then
    while read -r host
    do
        [ -z "$host" ] && break
        [[ $host == \#* ]] && continue
        hosts+=("$host")
    done
fi

if [ ${#hosts[@]} -eq 0 ]; then
    echo "ERROR: No hosts provided."
    usage
fi


run() {
	echo "+ $*"
    if [ $dry_run -eq 0 ]; then 
        $*
    fi
}

get_default_route () {
    # Get the nth ($1) default route from netstat
    netstat -nr -f inet | grep default | head -n "${1:-1}" | tail -n1
}

get_route_gateway () {
    # Get gateway value from route ($1)
    echo "$1" | awk '{print $2}'
}

get_route_interface () {
    # Get interface name value from route ($1)
    echo "$1" | awk '{print $4}'
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
vpn_route=$(get_default_route 1)
vpn_interface=$(get_route_interface "$vpn_route")
echo "Found default route:"
echo "$vpn_route"

# If it doesn't start with utun*, exit
if [[ $vpn_interface != utun* ]] ;
then
    echo "ERROR: Internet traffic is not going through a VPN interface."
    echo "Possible causes:"
    echo " - are you connected to a VPN?"
    echo " - did you run the script already while connected to a VPN?"
    exit 1
fi

# Get the second default gateway (after VPN)
default_route=$(get_default_route 2)
default_gateway=$(get_route_gateway "$default_route")
echo "Found non-VPN default route: "
echo "$default_route"

echo "Deleting default (VPN) route"
remove_default_route "$vpn_interface"

echo "Re-adding non-VPN default route"
add_default_route "$default_gateway"

echo "Redirecting ${#hosts[@]} host(s) through VPN"
for host in "${hosts[@]}"
do
    add_hostname_route "$host" "$vpn_interface"
done
