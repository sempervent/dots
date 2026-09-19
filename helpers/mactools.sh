# shellcheck shell=bash
# helpers/mactools.sh — post-install notes for --with mactools (no force relaunches)
#
# Requires: DIR, DRY_RUN, has_component (optional)

dots_mactools_postinstall_notes() {
	[[ ${DRY_RUN:-0} -eq 1 ]] && {
		echo "[dry-run] would print mactools post-install notes"
		return 0
	}
	cat <<'EOF'

=== mactools post-install (manual) ===

Vorssaint consolidates common Mac utility roles (clipboard, windowing,
snippets, capture, per-app audio helpers). Do not expect CleanShot /
Dropover / SoundSource / BTT / PopClip by default.

Licenses (activate in-app; DOTS never stores licenses):
  Keyboard Maestro, Hazel, Little Snitch, Hookmark, DEVONthink,
  Loopback, Audio Hijack, TouchDesigner (as applicable)

Likely macOS permissions (grant in System Settings → Privacy & Security):
  Vorssaint / Raycast / Keyboard Maestro  Accessibility, Input Monitoring
  Vorssaint / OBS / Loopback / Audio Hijack  Screen Recording, Microphone,
                                              System Audio (where prompted)
  Hazel / DEVONthink / Hookmark           Full Disk Access (if you use those features)
  Little Snitch                           Network Extension / System Extension approval
  OrbStack                                Virtualization entitlements (as prompted)

Restart / reboot (DOTS does not do these automatically):
  Manual restart required: Raycast, Keyboard Maestro, Hazel, Little Snitch,
    Loopback, Audio Hijack, OBS, DEVONthink (after first config change)
  Reboot may be required: BlackHole 2ch kernel extension / audio driver

OrbStack: installed alongside existing Docker tooling. Migrating away from
Docker Desktop is a separate deliberate operation — not performed by setup.

mise: installed but not wired into shell by default (fnm / other runtimes
remain). See docs/MACTOOLS.md for optional integration.

Ghostty / Yazi configs are linked when present under configs/; iTerm and
Ranger remain unchanged.
EOF
}

# Idempotent deploy of portable mactools text configs (after backup + links).
# Safe when packages are not yet installed — configs are inert until used.
dots_mactools_deploy_configs() {
	local label dest src
	# Prefer declarative links.toml entries; this helper only prints status.
	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] mactools portable configs via links.toml (ghostty/yazi/mise/lazygit)"
		return 0
	fi
	for label in ghostty yazi mise lazygit; do
		case "${label}" in
		ghostty) dest="${HOME}/.config/ghostty/config" ;;
		yazi) dest="${HOME}/.config/yazi/yazi.toml" ;;
		mise) dest="${HOME}/.config/mise/config.toml" ;;
		lazygit) dest="${HOME}/.config/lazygit/config.yml" ;;
		esac
		if [[ -L ${dest} ]]; then
			echo "OK: mactools config ${dest}"
		elif [[ -e ${dest} ]]; then
			echo "Note: ${dest} exists (backed up before link if unmanaged)"
		else
			echo "Note: ${dest} not linked yet (run full setup links / check links.toml)"
		fi
	done
}
