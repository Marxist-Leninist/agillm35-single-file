---
library_name: pytorch
tags:
  - agillm
  - transformer
  - diffusion-block
  - single-file
license: other
---

# AGILLM3.5 Single File

AGILLM3.5 is the AGILLM3 checkpoint/tokenizer contract running on the AGILLM4 runtime and DiffusionBlock training path.

The runnable artifact is `agillm35.py`. The helper modules are folded into that one file so the runtime can be cloned, inspected, and launched without restoring the whole AGILLM4 source tree.

## Public Join Scripts

`public_join/agillm35_network_host.py` starts a signed-lease HTTPS coordinator for people who want to run their own network.

`public_join/agillm35_join_worker.py` is an outbound-only worker for untrusted joiners. It requests short-lived leases, verifies package hashes, runs a local worker command, and submits results to quarantine rather than exposing SSH or writing directly into the master merge path.

## Distributed Inference

`distributed_infer/agillm35_distributed_infer.py` is a single-file distributed AR inference harness for the real AGILLM3.5 transformer. It splits contiguous transformer/DiffusionBlock layer ranges across local or HTTP worker stages, using the actual `Block` implementation and MoE FFNs from the checkpoint config.

Plan layer ranges:

```bash
python distributed_infer/agillm35_distributed_infer.py plan \
  --agillm35-path ./agillm35.py \
  --ckpt /path/to/master.pt \
  --dblock-blocks 8
```

Start a worker for one layer range:

```bash
AGILLM35_INFER_TOKEN='change-me' python distributed_infer/agillm35_distributed_infer.py worker \
  --agillm35-path ./agillm35.py \
  --ckpt /path/to/master.pt \
  --start-layer 0 \
  --end-layer 12 \
  --host 0.0.0.0 \
  --port 9100
```

Run the coordinator:

```bash
AGILLM35_INFER_TOKEN='change-me' python distributed_infer/agillm35_distributed_infer.py infer \
  --agillm35-path ./agillm35.py \
  --ckpt /path/to/master.pt \
  --prompt "Hello" \
  --max-new 32 \
  --cache-mode kv \
  --stage https://worker-a.example:9100,0,12 \
  --stage local:12:24
```

Network tensor payloads use a small raw tensor wire format rather than unpickling remote worker responses. Use TLS plus a bearer token for workers exposed beyond localhost. `--cache-mode kv` is the default and keeps per-session KV state on each worker after the prompt prefill, so decode steps send only the new hidden token through the pipeline. `--cache-mode full` is kept for comparison/debugging. SAT/NAT distributed decoding is a later phase.

## Defaults

- tokenizer: `deepseek-ai/DeepSeek-V3.2`
- preset: `large` (`d=1024`, `layers=24`, `heads=16`, `rank=128`)
- compatibility mode: `--agillm3_compat`
- NAT head/objective: disabled for AGILLM3 checkpoint compatibility
- DiffusionBlocks: available with `--dblock`

## Commands

```bash
python agillm35.py --help
python agillm35.py status --ckpt /path/to/pretrain_step00051081.pt
python agillm35.py infer --ckpt /path/to/pretrain_step00051081.pt --prompt "Hello"
```

## Example

```bash
python agillm35.py train \
  --agillm3_compat \
  --preset large \
  --resume /path/to/pretrain_step00051081.pt \
  --block 512 \
  --batch_size 1 \
  --source HuggingFaceFW/fineweb-edu \
  --save_dir ckpts \
  --dblock \
  --dblock_blocks 8 \
  --nat_every 0 \
  --dblock_nat_weight 0
```

## Notes

This repository contains code only, not AGILLM3 checkpoint weights.

DiffusionBlock logs report raw CE-style `loss` plus the actual EDM-weighted training objective as `weighted`. The weighted value is the optimization target; the raw value is the sanity-check number to compare with ordinary AR/SAT loss.

The Linux smoke test compiles the single file and completes a one-step synthetic training save. The full AGILLM3.5 continuation run is managed separately by the disaggregated Hetzner worker setup.
