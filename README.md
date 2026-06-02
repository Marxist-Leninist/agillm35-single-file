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
