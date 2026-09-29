#!/usr/bin/env bash

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
