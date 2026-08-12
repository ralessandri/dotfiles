###############################################################################
# Shell
###############################################################################

# Reload the current Bash configuration
alias reload='source ~/.bashrc'

# Clear the terminal screen
alias c='clear'

# Exit the current shell
alias q='exit'

###############################################################################
# Navigation
###############################################################################

# Change to the parent directory
alias ..='cd ..'

# Change to the grandparent directory
alias ...='cd ../..'

# Change three levels up
alias ....='cd ../../..'

###############################################################################
# File Management
###############################################################################

# Use bat as a replacement for cat
alias cat='bat'

# Show directory sizes (current level only)
alias du='du -h --max-depth=1'

# Short directory listing
alias l='ls -CF'

# List all files except . and ..
alias la='ls -A'

# Detailed directory listing
alias ll='ls -alF'

# Detailed directory listing with human-readable file sizes
alias llh='ls -alFh'

# Enable colored output for ls
alias ls='ls --color=auto'

# Display PATH entries line by line
alias path='echo -e ${PATH//:/\\n}'

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
# Kernel
###############################################################################

# List all installed kernel packages
alias ka='rpm -q kernel'

# Show all installed kernel-related RPM packages
alias kli='rpm -qa | grep "^kernel" | sort'

# Show kernel packages ordered by installation date
alias kinst='rpm -qa --last | grep "^kernel"'

# Show the currently running kernel version
alias kc='uname -r'

# Display the current kernel command line
alias kcmd='cat /proc/cmdline'

# Display the default kernel configured for the next boot
alias kd='grubby --default-kernel'

# Show kernel ring buffer with human-readable timestamps
alias kdmesg='dmesg -T | less'

# Show information about all GRUB boot entries
alias kg='grubby --info=ALL'

# Show GRUB menu entries
alias kgrub='grep "^menuentry" /boot/grub2/grub.cfg'

# Display complete kernel and system information
alias ku='uname -a'

# List available kernel packages from configured repositories
alias kav='dnf list --available kernel'

# Show system architecture
alias karch='uname -m'

# Display kernel messages from the current boot
alias klog='journalctl -k -b'

# Display kernel messages from the previous boot
alias klogprev='journalctl -k -b -1'

# List modules available for the running kernel
alias kmods='find /lib/modules/$(uname -r) -maxdepth 1'

# Display loaded kernel modules
alias klsmod='lsmod | less'

# Check whether a reboot is required after a kernel update
alias kreboot='needs-restarting -r'

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
# Development
###############################################################################

# Export the current DDEV database with a timestamp
alias ddev-dump='ddev export-db > $(basename $(pwd))-$(date +%Y%m%d-%H%M%S).sql.gz'

alias n='nvim'

###############################################################################
# Desktop
###############################################################################

# Disable ERTM (required for some Bluetooth game controllers)
alias controller-on='sudo bash -c "echo Y > /sys/module/bluetooth/parameters/disable_ertm" && echo ERTM deactivated'

# Re-enable ERTM
alias controller-off='sudo bash -c "echo N > /sys/module/bluetooth/parameters/disable_ertm" && echo ERTM activated'

###############################################################################
# Custom Scripts
###############################################################################

# Generate an AI-assisted Git commit message
alias ai-commit='ai-commit.sh'

# Launch dmenu
alias dmenu='dmenu.sh'

# Run backup script
alias dobackup='dobackup.sh'

# Start PhpStorm
alias phpstorm='phpstorm.sh'

# Rename dump files
alias renadump='renamdump.sh'

# Launch Toolbox helper
alias tbx='tbx.sh'

# Run the system update script
alias update='update.sh'
