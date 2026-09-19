# shellcheck shell=bash
# helpers/backup.sh — coherent snapshot / restore for DOTS-managed paths
#
# Snapshot root: ~/.local/state/dots/backups/<stamp>-<name>/
#   manifest.toml
#   files/          # paths mirrored relative to HOME (symlinks preserved)
#
# Requires: DIR, HOME
# Optional: DRY_RUN, PROFILE_NAME / DOTS_PROFILE, dots_version, dots_links_list

dots_backup_root() {
	printf '%s\n' "${HOME}/.local/state/dots/backups"
}

dots_backup_legacy_dir() {
	printf '%s\n' "${HOME}/.old_dots"
}

dots_backup_stamp() {
	date +%Y-%m-%dT%H%M%S 2>/dev/null || date +%Y%m%d%H%M%S
}

# Sanitize snapshot name fragment (filesystem-safe)
dots_backup_slug() {
	local s="${1:-manual}"
	s="$(printf '%s' "${s}" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-//;s/-$//')"
	[[ -n ${s} ]] || s="manual"
	printf '%s\n' "${s}"
}

# Absolute paths DOTS may manage (inventory). One path per line.
dots_backup_inventory() {
	local dest
	# Managed links from links.toml
	if declare -F dots_links_list >/dev/null 2>&1; then
		while IFS=$'\t' read -r _src tgt; do
			[[ -z ${tgt} ]] && continue
			if declare -F dots_expand_target >/dev/null 2>&1; then
				dest="$(dots_expand_target "${tgt}")"
			else
				dest="${tgt/#\~/${HOME}}"
			fi
			printf '%s\n' "${dest}"
		done < <(dots_links_list 2>/dev/null || true)
	fi
	# Additional managed destinations (not always symlinks)
	printf '%s\n' \
		"${HOME}/.config/nvim" \
		"${HOME}/.config/herdr/config.toml" \
		"${HOME}/.config/starship.toml" \
		"${HOME}/.config/dots/runtime.env" \
		"${HOME}/.config/dots/active-profile" \
		"${HOME}/.config/dots/models.toml" \
		"${HOME}/.config/dots/skills/skills-lock.json"
}

# Paths considered for automatic pre-change snapshots (excludes DOTS state files
# that are rewritten in place without replacing user-owned content).
dots_backup_collision_candidates() {
	local dest
	if declare -F dots_links_list >/dev/null 2>&1; then
		while IFS=$'\t' read -r _src tgt; do
			[[ -z ${tgt} ]] && continue
			if declare -F dots_expand_target >/dev/null 2>&1; then
				dest="$(dots_expand_target "${tgt}")"
			else
				dest="${tgt/#\~/${HOME}}"
			fi
			printf '%s\n' "${dest}"
		done < <(dots_links_list 2>/dev/null || true)
	fi
	printf '%s\n' \
		"${HOME}/.config/nvim" \
		"${HOME}/.config/herdr/config.toml" \
		"${HOME}/.config/starship.toml"
}

dots_backup_inventory_unique() {
	dots_backup_inventory | awk 'NF && !seen[$0]++'
}

dots_backup_path_is_managed_ok() {
	local path="$1"
	# Correct repo symlink
	if [[ -L ${path} && -n ${DIR:-} ]]; then
		local cur
		cur="$(readlink "${path}" 2>/dev/null || true)"
		case "${cur}" in
		"${DIR}" | "${DIR}"/*) return 0 ;;
		esac
	fi
	# Neovim already matches managed init.lua
	if [[ ${path} == "${HOME}/.config/nvim" && -n ${DIR:-} ]]; then
		if [[ -f ${path}/init.lua && -f ${DIR}/configs/nvim/init.lua ]] &&
			cmp -s "${path}/init.lua" "${DIR}/configs/nvim/init.lua" 2>/dev/null; then
			return 0
		fi
	fi
	return 1
}

# True if path is under HOME (or equals HOME) — reject escapes.
dots_backup_path_allowed() {
	local p="$1" home="${HOME}"
	case "${p}" in
	"${home}" | "${home}"/*) return 0 ;;
	*) return 1 ;;
	esac
}

# Relative path under HOME for archive storage
dots_backup_relpath() {
	local p="$1"
	if [[ ${p} == "${HOME}" ]]; then
		printf '.\n'
		return 0
	fi
	printf '%s\n' "${p#"${HOME}"/}"
}

# Copy one live path into snapshot files/ tree (preserves type/symlink).
dots_backup_capture_one() {
	local snap="$1" path="$2"
	local rel dest parent
	dots_backup_path_allowed "${path}" || {
		echo "Error: refuse to snapshot path outside HOME: ${path}" >&2
		return 1
	}
	[[ -e ${path} || -L ${path} ]] || return 0
	rel="$(dots_backup_relpath "${path}")"
	[[ ${rel} == "." ]] && return 1
	# Reject traversal in relative form
	case "${rel}" in
	*..*)
		echo "Error: path traversal rejected: ${rel}" >&2
		return 1
		;;
	esac
	dest="${snap}/files/${rel}"
	parent="$(dirname "${dest}")"
	mkdir -p "${parent}"
	# Use cp -a / ditto-style: preserve symlink as symlink (do not follow)
	if [[ -L ${path} ]]; then
		rm -rf "${dest}" 2>/dev/null || true
		cp -P "${path}" "${dest}" 2>/dev/null || ln -s "$(readlink "${path}")" "${dest}"
	elif [[ -d ${path} ]]; then
		mkdir -p "${dest}"
		# Copy directory tree without following external symlinks at top level
		if command -v rsync >/dev/null 2>&1; then
			rsync -a --copy-unsafe-links "${path}/" "${dest}/" 2>/dev/null ||
				cp -a "${path}/." "${dest}/"
		else
			cp -a "${path}/." "${dest}/"
		fi
	elif [[ -f ${path} ]]; then
		cp -p "${path}" "${dest}"
	else
		# special nodes — skip
		return 0
	fi
	printf '%s\n' "${rel}"
}

dots_backup_write_manifest() {
	local snap="$1" name="$2" reason="$3"
	local created profile version count
	created="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
	profile="${PROFILE_NAME:-${DOTS_PROFILE:-}}"
	version="unknown"
	if declare -F dots_version >/dev/null 2>&1; then
		version="$(dots_version)"
	elif [[ -f ${DIR}/VERSION ]]; then
		version="$(tr -d '[:space:]' <"${DIR}/VERSION")"
	fi
	count=0
	if [[ -d ${snap}/files ]]; then
		count="$(find "${snap}/files" \( -type f -o -type l -o -type d \) ! -path "${snap}/files" 2>/dev/null | wc -l | tr -d ' ')"
	fi
	cat >"${snap}/manifest.toml" <<EOF
# DOTS snapshot manifest
name = "${name}"
reason = "${reason}"
created = "${created}"
dots_version = "${version}"
profile = "${profile}"
home = "${HOME}"
entry_count = ${count}
EOF
}

# Create snapshot of listed paths (absolute). Args after options are paths.
# Options: --name NAME --reason REASON
# Prints snapshot id (dirname) on success; empty if nothing captured.
dots_backup_create() {
	local name="manual" reason="manual"
	local -a paths=()
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--name)
			name="${2:-manual}"
			shift 2
			continue
			;;
		--name=*)
			name="${1#*=}"
			shift
			continue
			;;
		--reason)
			reason="${2:-manual}"
			shift 2
			continue
			;;
		--reason=*)
			reason="${1#*=}"
			shift
			continue
			;;
		--)
			shift
			break
			;;
		-*)
			echo "Unknown backup option: $1" >&2
			return 1
			;;
		*)
			paths+=("$1")
			shift
			continue
			;;
		esac
	done
	while [[ $# -gt 0 ]]; do
		paths+=("$1")
		shift
	done

	if [[ ${#paths[@]} -eq 0 ]]; then
		echo "Error: dots_backup_create requires paths" >&2
		return 1
	fi

	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] would create snapshot '${name}' (${reason}) with ${#paths[@]} path(s)"
		return 0
	fi

	local stamp slug snap captured=0 rel
	stamp="$(dots_backup_stamp)"
	slug="$(dots_backup_slug "${name}")"
	snap="$(dots_backup_root)/${stamp}-${slug}"
	mkdir -p "${snap}/files"

	for p in "${paths[@]}"; do
		[[ -z ${p} ]] && continue
		if [[ -e ${p} || -L ${p} ]]; then
			if rel="$(dots_backup_capture_one "${snap}" "${p}")"; then
				[[ -n ${rel} ]] && captured=$((captured + 1))
			fi
		fi
	done

	if [[ ${captured} -eq 0 ]]; then
		rm -rf "${snap}"
		return 0
	fi

	dots_backup_write_manifest "${snap}" "${slug}" "${reason}"
	echo "OK: snapshot ${stamp}-${slug} (${captured} item(s))" >&2
	printf '%s\n' "${stamp}-${slug}"
}

# Snapshot unmanaged collisions among inventory (paths that exist and are not
# already the correct DOTS symlink). Returns 0 when none needed or snapshot OK;
# returns 1 when a required snapshot cannot be created (setup must abort).
dots_backup_snapshot_collisions() {
	local name="${1:-pre-change}"
	local reason="${2:-pre-change}"
	local -a collide=()
	local path src_expected

	# Ensure links helper available when possible
	if [[ -n ${DIR:-} ]] && [[ -f ${DIR}/helpers/links.sh ]]; then
		# shellcheck source=links.sh
		source "${DIR}/helpers/links.sh" 2>/dev/null || true
	fi

	while IFS= read -r path; do
		[[ -z ${path} ]] && continue
		dots_backup_path_allowed "${path}" || continue
		if [[ ! -e ${path} && ! -L ${path} ]]; then
			continue
		fi
		if dots_backup_path_is_managed_ok "${path}"; then
			continue
		fi
		collide+=("${path}")
	done < <(dots_backup_collision_candidates | awk 'NF && !seen[$0]++')

	if [[ ${#collide[@]} -eq 0 ]]; then
		echo "Backup: none needed (no unmanaged collisions)"
		return 0
	fi

	# Distinguish first-time vs reconfigure naming
	if [[ ! -f ${HOME}/.config/dots/active-profile ]] && [[ ${name} == "pre-change" || ${name} == "pre-setup" ]]; then
		name="pre-dots"
		reason="pre-dots"
	fi

	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] would snapshot ${#collide[@]} unmanaged collision(s) before config mutation"
		return 0
	fi

	# HARD GATE: unmanaged targets must be snapshotted before any link/config mutate.
	local id create_rc=0 out
	set +e
	out="$(dots_backup_create --name "${name}" --reason "${reason}" "${collide[@]}" 2>&1)"
	create_rc=$?
	set -e
	printf '%s\n' "${out}" >&2
	id="$(printf '%s\n' "${out}" | tail -1)"
	# Create prints the snapshot id on the last stdout line; reject empty/missing trees.
	if [[ ${create_rc} -ne 0 ]] || [[ -z ${id} ]] || [[ ! -d "$(dots_backup_root)/${id}" ]]; then
		echo "Error: pre-change backup failed; refusing to mutate configuration or symlinks" >&2
		return 1
	fi
	echo "Backup created: ${id}"
	DOTS_LAST_BACKUP_ID="${id}"
	export DOTS_LAST_BACKUP_ID
	return 0
}

dots_backup_list() {
	local root legacy
	root="$(dots_backup_root)"
	legacy="$(dots_backup_legacy_dir)"
	if [[ -d ${legacy} ]] && [[ -n "$(ls -A "${legacy}" 2>/dev/null || true)" ]]; then
		echo "Legacy backup directory detected: ${legacy}"
		echo "  Import with: ./dots backup import-legacy"
		echo ""
	fi
	if [[ ! -d ${root} ]] || [[ -z "$(ls -A "${root}" 2>/dev/null || true)" ]]; then
		echo "(no snapshots under ${root})"
		return 0
	fi
	local d base mf name profile ver created count
	# Newest first
	while IFS= read -r d; do
		[[ -d ${d} ]] || continue
		base="$(basename "${d}")"
		mf="${d}/manifest.toml"
		name="${base}"
		profile="-"
		ver="-"
		created="-"
		count="?"
		if [[ -f ${mf} ]]; then
			name="$(grep -E '^name[[:space:]]*=' "${mf}" 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/' || echo "${base}")"
			profile="$(grep -E '^profile[[:space:]]*=' "${mf}" 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/' || echo "-")"
			ver="$(grep -E '^dots_version[[:space:]]*=' "${mf}" 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/' || echo "-")"
			created="$(grep -E '^created[[:space:]]*=' "${mf}" 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/' || echo "-")"
			count="$(grep -E '^entry_count[[:space:]]*=' "${mf}" 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*//' || echo "?")"
		fi
		[[ -z ${profile} ]] && profile="-"
		printf '%s  name=%-20s  profile=%-8s  files=%-4s  dots=%s\n' \
			"${base}" "${name}" "${profile}" "${count}" "${ver}"
	done < <(find "${root}" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -r)
}

dots_backup_latest_id() {
	local root d
	root="$(dots_backup_root)"
	[[ -d ${root} ]] || return 1
	d="$(find "${root}" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -r | head -1 || true)"
	[[ -n ${d} ]] || return 1
	basename "${d}"
}

dots_backup_resolve_id() {
	local id="$1" root cand
	root="$(dots_backup_root)"
	[[ -n ${id} ]] || return 1
	if [[ -d ${root}/${id} ]]; then
		printf '%s\n' "${root}/${id}"
		return 0
	fi
	# Prefix match
	cand="$(find "${root}" -mindepth 1 -maxdepth 1 -type d -name "${id}*" -print 2>/dev/null | head -1 || true)"
	if [[ -n ${cand} && -d ${cand} ]]; then
		printf '%s\n' "${cand}"
		return 0
	fi
	return 1
}

# Restore snapshot. Options: --dry-run --yes
dots_backup_restore() {
	local dry=0 yes=0 id=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--dry-run) dry=1 ;;
		--yes | -y) yes=1 ;;
		-*)
			echo "Unknown restore option: $1" >&2
			return 1
			;;
		*)
			id="$1"
			;;
		esac
		shift
	done
	if [[ -z ${id} ]]; then
		echo "Usage: dots_backup_restore <snapshot-id> [--dry-run] [--yes]" >&2
		return 1
	fi
	local snap
	snap="$(dots_backup_resolve_id "${id}")" || {
		echo "Error: snapshot not found: ${id}" >&2
		return 1
	}
	local files="${snap}/files"
	[[ -d ${files} ]] || {
		echo "Error: snapshot has no files/: ${snap}" >&2
		return 1
	}

	echo "Restore from: $(basename "${snap}")"
	echo "Will restore:"
	(
		cd "${files}" && find . \( -type f -o -type l -o -type d \) ! -path . 2>/dev/null | sed 's|^\./||' | head -50
	)
	echo ""

	if [[ ${dry} -eq 1 ]]; then
		echo "[dry-run] would create pre-restore safety snapshot, then restore"
		return 0
	fi

	if [[ ${yes} -ne 1 ]]; then
		printf "Proceed with restore? [y/N] "
		# shellcheck disable=SC2162
		read ans
		case "${ans}" in
		y | Y | yes | YES) ;;
		*)
			echo "Aborted."
			return 1
			;;
		esac
	fi

	# Safety snapshot of current versions of those paths
	local -a current=()
	local rel live
	while IFS= read -r rel; do
		[[ -z ${rel} ]] && continue
		case "${rel}" in
		*..*) continue ;;
		esac
		live="${HOME}/${rel}"
		if [[ -e ${live} || -L ${live} ]]; then
			current+=("${live}")
		fi
	done < <(cd "${files}" && find . \( -type f -o -type l \) 2>/dev/null | sed 's|^\./||')

	if [[ ${#current[@]} -gt 0 ]]; then
		local prev_dry="${DRY_RUN:-0}"
		DRY_RUN=0
		dots_backup_create --name "pre-restore" --reason "pre-restore" "${current[@]}" >/dev/null || true
		DRY_RUN="${prev_dry}"
	fi

	# Restore each entry
	while IFS= read -r rel; do
		[[ -z ${rel} ]] && continue
		case "${rel}" in
		*..* | /*)
			echo "Error: reject unsafe archive entry: ${rel}" >&2
			return 1
			;;
		esac
		live="${HOME}/${rel}"
		dots_backup_path_allowed "${live}" || {
			echo "Error: restore target outside HOME: ${live}" >&2
			return 1
		}
		mkdir -p "$(dirname "${live}")"
		rm -rf "${live}" 2>/dev/null || true
		if [[ -L ${files}/${rel} ]]; then
			ln -s "$(readlink "${files}/${rel}")" "${live}"
		elif [[ -d ${files}/${rel} ]]; then
			mkdir -p "${live}"
			cp -a "${files}/${rel}/." "${live}/"
		elif [[ -f ${files}/${rel} ]]; then
			cp -p "${files}/${rel}" "${live}"
		fi
		echo "Restored: ${live}"
	done < <(cd "${files}" && find . \( -type f -o -type l -o -type d \) ! -path . 2>/dev/null | sed 's|^\./||' | sort)

	echo "OK: restore complete"
	return 0
}

# Import unambiguous ~/.old_dots entries into a new snapshot.
dots_backup_legacy_import() {
	local legacy
	legacy="$(dots_backup_legacy_dir)"
	if [[ ! -d ${legacy} ]]; then
		echo "No legacy directory at ${legacy}"
		return 0
	fi
	local -a mapped=() ambiguous=()
	local f base dest stem

	# Known basename → destination map (unambiguous only)
	_dots_legacy_map() {
		case "$1" in
		.bashrc | bashrc) printf '%s\n' "${HOME}/.bashrc" ;;
		.zshrc | zshrc) printf '%s\n' "${HOME}/.zshrc" ;;
		.zshenv | zshenv) printf '%s\n' "${HOME}/.zshenv" ;;
		.zprofile | zprofile) printf '%s\n' "${HOME}/.zprofile" ;;
		.vimrc | vimrc) printf '%s\n' "${HOME}/.vimrc" ;;
		.tmux.conf | tmux.conf) printf '%s\n' "${HOME}/.tmux.conf" ;;
		starship.toml) printf '%s\n' "${HOME}/.config/starship.toml" ;;
		*) return 1 ;;
		esac
	}

	shopt -s nullglob 2>/dev/null || true
	for f in "${legacy}"/*; do
		[[ -e ${f} || -L ${f} ]] || continue
		base="$(basename "${f}")"
		# Strip timestamp suffix _YYYY-MM-DD_HHMMSS or _YYYYMMDDHHMMSS
		stem="$(printf '%s' "${base}" | sed -E 's/_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}$//; s/_[0-9]{8,14}$//; s/_symlink$//; s/_symlink_[0-9].*$//')"
		if dest="$(_dots_legacy_map "${stem}")"; then
			# Capture the legacy file itself under the mapped destination name in a temp layout
			mapped+=("${f}|${dest}")
		else
			ambiguous+=("${base}")
		fi
	done

	if [[ ${#ambiguous[@]} -gt 0 ]]; then
		echo "Ambiguous legacy entries (not auto-imported):"
		for a in "${ambiguous[@]}"; do
			echo "  ${a}"
		done
		echo "Map manually or leave in ~/.old_dots."
	fi

	if [[ ${#mapped[@]} -eq 0 ]]; then
		echo "No unambiguous legacy entries to import."
		return 0
	fi

	if [[ ${DRY_RUN:-0} -eq 1 ]]; then
		echo "[dry-run] would import ${#mapped[@]} legacy entr(y/ies) into a snapshot"
		return 0
	fi

	local stamp slug snap
	stamp="$(dots_backup_stamp)"
	slug="$(dots_backup_slug "import-legacy")"
	snap="$(dots_backup_root)/${stamp}-${slug}"
	mkdir -p "${snap}/files"
	local pair src tgt rel
	for pair in "${mapped[@]}"; do
		src="${pair%%|*}"
		tgt="${pair##*|}"
		rel="$(dots_backup_relpath "${tgt}")"
		case "${rel}" in *..*) continue ;; esac
		mkdir -p "$(dirname "${snap}/files/${rel}")"
		if [[ -L ${src} ]]; then
			cp -P "${src}" "${snap}/files/${rel}" 2>/dev/null || ln -s "$(readlink "${src}")" "${snap}/files/${rel}"
		elif [[ -d ${src} ]]; then
			mkdir -p "${snap}/files/${rel}"
			cp -a "${src}/." "${snap}/files/${rel}/"
		else
			cp -p "${src}" "${snap}/files/${rel}"
		fi
		echo "Imported: ${src} → ${rel}"
	done
	dots_backup_write_manifest "${snap}" "${slug}" "import-legacy"
	echo "OK: legacy import snapshot ${stamp}-${slug}"
	printf '%s\n' "${stamp}-${slug}"
}

# Status snippet for ./dots status
dots_backup_status_lines() {
	local root count latest
	root="$(dots_backup_root)"
	count=0
	if [[ -d ${root} ]]; then
		count="$(find "${root}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
	fi
	echo "Backups:"
	if latest="$(dots_backup_latest_id 2>/dev/null)"; then
		echo "  latest: ${latest}"
		echo "  count: ${count}"
	else
		echo "  latest: (none)"
		echo "  count: ${count}"
	fi
	if [[ -d "$(dots_backup_legacy_dir)" ]] && [[ -n "$(ls -A "$(dots_backup_legacy_dir)" 2>/dev/null || true)" ]]; then
		echo "  legacy: ~/.old_dots present (./dots backup import-legacy)"
	fi
}
