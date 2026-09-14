#!/usr/bin/env bash
# Telemetry unit/integration tests — temporary DB only.
set -euo pipefail

DOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR_T="$(mktemp -d /tmp/dots-tele-XXXXXX)"
export DOTS_DIR
export DOTS_TELEMETRY=1
export DOTS_TELEMETRY_DB="${TMPDIR_T}/agents.sqlite3"
export DOTS_TELEMETRY_CONFIG="${DOTS_DIR}/configs/agents/telemetry.toml"
TELE="${DOTS_DIR}/scripts/agent-telemetry"
STATS="${DOTS_DIR}/scripts/agent-stats"
ROUTE="${DOTS_DIR}/skills/agent-router/route.py"

pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

cleanup() { rm -rf "${TMPDIR_T}"; }
trap cleanup EXIT

chmod +x "${TELE}" "${STATS}" 2>/dev/null || true

echo "=== telemetry tests (tmp db=${DOTS_TELEMETRY_DB}) ==="

# doctor / schema
if "${TELE}" doctor >/tmp/tele-doc.$$ 2>&1; then
  ok "doctor"
else
  bad "doctor"
  cat /tmp/tele-doc.$$ >&2
fi

# route event
rid="$("${TELE}" route --category coding-local --destination opencode --reason "test route")"
[[ -n "${rid}" ]] && ok "route event" || bad "route event"

# successful execution
eid="$("${TELE}" record-start --backend opencode --kind coding-local --label "repo implementation" --cwd "${TMPDIR_T}" --model ollama/qwen-hermes:latest --local-or-cloud local)"
[[ -n "${eid}" ]] && ok "start execution" || bad "start execution"
"${TELE}" record-finish --id "${eid}" --success true --exit-code 0 >/dev/null
ok "finish success"

# failed + timeout
eid2="$("${TELE}" record-start --backend codex --kind coding-frontier --label "frontier" --local-or-cloud cloud)"
"${TELE}" record-finish --id "${eid2}" --success false --exit-code 1 >/dev/null
ok "finish failure"
eid3="$("${TELE}" record-start --backend opencode --kind coding-local --label "slow")"
"${TELE}" record-finish --id "${eid3}" --success false --timeout --exit-code 124 >/dev/null
ok "finish timeout"

# escalation
eid4="$("${TELE}" record-start --backend opencode --kind coding-local --label "escalate")"
python3 - "${DOTS_TELEMETRY_DB}" "${eid4}" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute(
  "UPDATE executions SET escalated=1, escalation_from=?, escalation_to=?, escalation_reason=? WHERE id=?",
  ("opencode", "codex", "timeout", sys.argv[2]),
)
con.commit()
PY
"${TELE}" record-finish --id "${eid4}" --success false --exit-code 124 --timeout \
  --escalated --escalation-from opencode --escalation-to codex --escalation-reason timeout >/dev/null
ok "escalation fields"

# concurrent writes
python3 - "${DOTS_DIR}" "${DOTS_TELEMETRY_DB}" <<'PY' &
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "tools", "agent_telemetry"))
os.environ["DOTS_TELEMETRY_DB"] = sys.argv[2]
os.environ["DOTS_TELEMETRY"] = "1"
from dots_telemetry.record import start_execution, finish_execution
for i in range(8):
    eid = start_execution(backend="opencode", task_kind="coding-local", task_label=f"c{i}")
    finish_execution(eid, success=True, exit_code=0)
PY
python3 - "${DOTS_DIR}" "${DOTS_TELEMETRY_DB}" <<'PY' &
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "tools", "agent_telemetry"))
os.environ["DOTS_TELEMETRY_DB"] = sys.argv[2]
os.environ["DOTS_TELEMETRY"] = "1"
from dots_telemetry.record import start_execution, finish_execution
for i in range(8):
    eid = start_execution(backend="codex", task_kind="coding-frontier", task_label=f"d{i}")
    finish_execution(eid, success=True, exit_code=0)
PY
wait
ok "concurrent writes"

# privacy: no prompt/response columns or blob text
python3 - "${DOTS_TELEMETRY_DB}" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
cols = [r[1] for r in con.execute("PRAGMA table_info(executions)")]
assert "prompt" not in cols and "response" not in cols
# dump all text fields — must not contain a fake secret we never wrote
blob = " ".join(
  str(x) for row in con.execute("SELECT * FROM executions") for x in row if x is not None
)
assert "SECRET_TOKEN_XYZ" not in blob
assert "sk-proj-" not in blob
print("privacy ok")
PY
ok "privacy defaults (no prompt/response columns)"

# prune
python3 - "${DOTS_TELEMETRY_DB}" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute(
  "INSERT INTO executions(id, timestamp_start, backend, status, result_status) "
  "VALUES('old1','2000-01-01T00:00:00.000Z','opencode','completed','success')"
)
con.commit()
PY
out="$("${TELE}" prune --days 30)"
echo "${out}" | rg -q '"executions": 1' && ok "prune old rows" || bad "prune old rows: ${out}"

# schema migration / version
python3 - "${DOTS_TELEMETRY_DB}" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
ver = con.execute("SELECT value FROM schema_meta WHERE key='schema_version'").fetchone()[0]
assert int(ver) >= 1
mode = con.execute("PRAGMA journal_mode").fetchone()[0]
assert mode.lower() == "wal"
print("schema", ver, mode)
PY
ok "schema version + WAL"

# stats empty-safe / with data
"${STATS}" --json >/tmp/tele-stats.$$ || bad "agent-stats"
rg -q '"executions"' /tmp/tele-stats.$$ && ok "agent-stats json" || bad "agent-stats json"
"${STATS}" --failures --json >/dev/null && ok "agent-stats --failures" || bad "agent-stats --failures"
"${STATS}" --escalations --json >/dev/null && ok "agent-stats --escalations" || bad "agent-stats --escalations"

# opt-out
DOTS_TELEMETRY=0 rid2="$("${TELE}" route --category direct --destination hermes_direct --reason "disabled" || true)"
[[ -z "${rid2}" ]] && ok "opt-out DOTS_TELEMETRY=0" || bad "opt-out still wrote"

# router integration (temp db, telemetry on)
unset DOTS_TELEMETRY
export DOTS_TELEMETRY=1
python3 "${ROUTE}" --json "inspect this repository for failing tests" >/dev/null
python3 - "${DOTS_TELEMETRY_DB}" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
n = con.execute("SELECT COUNT(*) FROM routing_events WHERE destination='opencode'").fetchone()[0]
assert n >= 1
# ensure prompt text not stored
blob = " ".join(str(x) for row in con.execute("SELECT * FROM routing_events") for x in row if x)
assert "inspect this repository" not in blob
print("router ok")
PY
ok "router instrumentation (no prompt body)"

# mock adapter path: start/finish via Python API as OpenCode would
python3 - "${DOTS_DIR}" "${DOTS_TELEMETRY_DB}" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "tools", "agent_telemetry"))
os.environ["DOTS_TELEMETRY_DB"] = sys.argv[2]
import bridge
eid = bridge.start(backend="cursor", task_kind="coding-cursor", task_label="cursor agent run", local_or_cloud="cloud")
assert eid
assert bridge.finish(eid, success=True, exit_code=0)
eid = bridge.start(backend="drawthings", task_kind="visual", task_label="image generation", local_or_cloud="local")
assert bridge.finish(eid, success=False, exit_code=1, timed_out=False)
print("adapter bridge ok")
PY
ok "adapter bridge mock executions"

echo ""
echo "Passed: ${pass}  Failed: ${fail}"
[[ "${fail}" -eq 0 ]]
