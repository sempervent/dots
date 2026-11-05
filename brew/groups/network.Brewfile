# brew/groups/network.Brewfile — network / remote CLIs
#
# Install-only. DOTS never:
#   - runs `tailscale up` / login / auth / set
#   - scans hosts/subnets (nmap/mtr/gping)
#   - starts iperf3 server/client
#   - captures packets (termshark/tshark/bandwhich)
# mitmproxy: opt-in — ./setup.sh --with mitmproxy
# stern / kubectx live in brew/groups/k8s.Brewfile
#
# termshark: Homebrew formula disabled (2026-01-03); not listed here.
# tshark/wireshark: not auto-installed on Darwin (capture privilege prompts).

brew "tailscale"
brew "mosh"
brew "rclone"
brew "bandwhich"
brew "gping"
brew "doggo"
brew "grpcurl"
brew "websocat"
# v1.7 Phase 6
brew "mtr"
brew "nmap"
brew "iperf3"
