#!/usr/bin/env bash
# scripts/mactools/docker-orbstack-audit.sh — read-only Docker Desktop / OrbStack inventory
#
# Never starts, stops, deletes, or migrates anything.
set -euo pipefail

echo "=== DOTS Docker / OrbStack audit (read-only) ==="
echo "Host: $(uname -s) $(uname -m)"
echo ""

_have() { command -v "$1" >/dev/null 2>&1; }

echo "-- Presence --"
if [[ "$(uname -s)" == "Darwin" ]]; then
	[[ -d /Applications/Docker.app ]] && echo "Docker Desktop.app: present" || echo "Docker Desktop.app: absent"
	[[ -d /Applications/OrbStack.app ]] && echo "OrbStack.app: present" || echo "OrbStack.app: absent"
else
	echo "(non-Darwin: app bundle checks skipped)"
fi
_have docker && echo "docker CLI: $(command -v docker) ($(docker --version 2>/dev/null | head -1))" || echo "docker CLI: missing"
_have orbstack && echo "orbstack CLI: $(command -v orbstack)" || echo "orbstack CLI: missing"
_have orb && echo "orb CLI: $(command -v orb)" || true

echo ""
echo "-- Docker context --"
if _have docker; then
	docker context ls 2>/dev/null || echo "(docker context ls failed)"
	echo "Current context: $(docker context show 2>/dev/null || echo unknown)"
else
	echo "(skipped — no docker)"
fi

echo ""
echo "-- Workloads (summary) --"
if _have docker; then
	echo "Containers:"
	docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null | head -40 || echo "(ps failed)"
	echo ""
	echo "Images (top 30 by size):"
	docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' 2>/dev/null | head -31 || echo "(images failed)"
	echo ""
	echo "Volumes:"
	docker volume ls 2>/dev/null | head -40 || echo "(volumes failed)"
	echo ""
	echo "Networks:"
	docker network ls 2>/dev/null || echo "(networks failed)"
	echo ""
	echo "Disk:"
	docker system df 2>/dev/null || echo "(system df failed)"
else
	echo "(skipped)"
fi

echo ""
echo "-- Potential blockers (informational) --"
echo "- Named volumes with irreplaceable data need explicit backup before context switch"
echo "- Compose projects may pin DOCKER_HOST / context names"
echo "- Credential helpers may differ between Docker Desktop and OrbStack"
echo "- Do NOT uninstall Docker Desktop from this script"
echo ""
echo "Playbook: docs/ORBSTACK_MIGRATION.md"
echo "OK: audit complete (no mutations)"
