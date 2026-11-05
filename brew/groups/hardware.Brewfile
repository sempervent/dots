# brew/groups/hardware.Brewfile — storage / bus / serial diagnostics
#
# Install-only. DOTS never:
#   - runs SMART self-tests (smartctl -t)
#   - runs fio workloads / writes to disks
#   - opens /dev/tty* or sends serial data
#   - requires sudo for setup/check
#
# usbutils / pciutils: available via brew but Linux-native is stronger;
# Darwin users get brew formulae when selected (limited device access).

brew "smartmontools"
brew "fio"
brew "picocom"
brew "usbutils"
brew "pciutils"
