#!/usr/bin/env bash

###############################################################################
# Networking
###############################################################################

# Display the active default route
alias defroute='ip route show default'

# Display DNS resolver configuration
alias dns='resolvectl status'

# Display IP addresses
alias ipa='ip -brief address'

# Display NetworkManager device status
alias nmdev='nmcli device status'

# Test network connectivity with four ICMP echo requests
alias pingg='ping -c 4'

# Display listening TCP and UDP ports
alias ports='ss -tulpen'

# Show which interface is used to reach the Internet
alias route8='ip route get 8.8.8.8'

# Display the routing table
alias routes='ip route'

# List available Wi-Fi networks
alias wifi-list='nmcli dev wifi list'

# Show the currently connected Wi-Fi network
alias wifi-show='nmcli dev wifi show'
