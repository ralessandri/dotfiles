#!/usr/bin/env bash

###############################################################################
# System Information
###############################################################################

# Display CPU information
alias cpu='lscpu'

# Display block devices and file systems
alias disks='lsblk -f'

# Display hostname information
alias hn='hostnamectl'

# Display memory usage
alias mem='free -h'

# Show mounted file systems
alias mounts='findmnt'

# Display operating system information
alias os='cat /etc/os-release'

# Show system uptime and load average
alias up='uptime'

###############################################################################
# Storage
###############################################################################

# Display disk usage
alias dfh='df -hT'

# Display inode usage
alias dfi='df -i'

###############################################################################
# Processes
###############################################################################

# Display process tree
alias pst='ps -ef --forest'

# Display processes sorted by CPU usage
alias pscpu='ps aux --sort=-%cpu'

# Display processes sorted by memory usage
alias psmem='ps aux --sort=-%mem'

###############################################################################
# Services & Logs
###############################################################################

# Show failed systemd services
alias failed='systemctl --failed'

# View the system journal with extended information
alias j='journalctl -xe'

# List all running services
alias running='systemctl list-units --type=service --state=running'

# Display service status
alias sc='systemctl status'

###############################################################################
# Security
###############################################################################

# Display active firewall configuration
alias fw='firewall-cmd --list-all'

# Show recent SELinux denials
alias seavc='ausearch -m avc -ts recent'

# List SELinux booleans
alias sebool='getsebool -a'

# Display SELinux status
alias sest='sestatus'

###############################################################################
# Desktop
###############################################################################

# Disable ERTM (required for some Bluetooth game controllers)
alias controller-on='sudo bash -c "echo Y > /sys/module/bluetooth/parameters/disable_ertm" && echo ERTM deactivated'

# Re-enable ERTM
alias controller-off='sudo bash -c "echo N > /sys/module/bluetooth/parameters/disable_ertm" && echo ERTM activated'
