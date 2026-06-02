#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/root/agillm4_opportunistic}"
UPGRADE="${AGILLM4_UPGRADE:-/root/agillm4_upgrade}"

mkdir -p "$ROOT"/{code,runtime,current,updates,heartbeats,logs,state}

cp "$UPGRADE/training_bench/agillm4_slice_bench_worker.py" "$ROOT/code/agillm4_slice_bench_worker.py"
cp "$UPGRADE/runtime/nB300_agillm4.py" "$ROOT/runtime/nB300_agillm4.py"
cp "$UPGRADE/runtime/dblocks_train.py" "$ROOT/runtime/dblocks_train.py"
cp "$UPGRADE/runtime/fused_ce.py" "$ROOT/runtime/fused_ce.py"
if [ -f "$UPGRADE/runtime/anchor_memory.py" ]; then
  cp "$UPGRADE/runtime/anchor_memory.py" "$ROOT/runtime/anchor_memory.py"
fi

cat > "$ROOT/nodes.json" <<'JSON'
{
  "policy": {
    "mode": "async_optional",
    "description": "Vast.ai 4090 remains the master trainer. Hetzner/GETH nodes are reliable side-workers. The laptop is opportunistic: it may duplicate covered DBlocks, but it is never a required owner and stale/missing updates are ignored.",
    "master": {
      "name": "vast-4090",
      "role": "fast-but-less-reliable-master",
      "baseline_tok_per_sec": 3357.167
    },
    "reliable_pool": "hetzner-geth-mcp-prime-communist-web",
    "opportunistic_deadline_sec": 900,
    "stale_update_sec": 1800
  },
  "reliable": [
    {"name": "geth", "kind": "local", "blocks": [0], "class": "reliable"},
    {"name": "mcp", "kind": "ssh", "host": "10.0.1.20", "blocks": [1], "class": "reliable"},
    {"name": "prime", "kind": "ssh", "host": "10.0.1.30", "blocks": [2], "class": "reliable"},
    {"name": "communist-web", "kind": "ssh", "host": "10.0.1.1", "blocks": [3], "class": "reliable"}
  ],
  "opportunistic": [
    {
      "name": "laptop-auto",
      "kind": "outbound_windows_pull",
      "blocks": [0, 1, 2, 3],
      "class": "opportunistic",
      "device_preference": "cuda_then_cpu",
      "threads": "auto",
      "note": "Scott's laptop may be off. It pulls leases outbound from GETH when awake; coordinator never waits for it and never assigns it sole block ownership."
    }
  ]
}
JSON

cat > "$ROOT/README.md" <<'MD'
# AGILLM4 Opportunistic Worker Pool

This directory is a non-blocking side-worker queue. Vast.ai remains the AGILLM4
master trainer. Hetzner/GETH nodes are the reliable pool. The laptop is an
opportunistic outbound-pull worker: if it is off, asleep, or slow, the master
continues without it.

Expected current lease layout:

```text
current/shared_frozen.pt
current/lease_laptop-auto.pt
current/lease_laptop-auto.json
```

Worker updates land in `updates/` and must be treated as optional side-updates.
Do not make the master or a synchronous round wait for laptop updates.
MD

printf '{"event":"registered","root":"%s","updated_at":"%s"}\n' "$ROOT" "$(date -Is)" | tee "$ROOT/state/register.json"
