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

The Linux smoke test compiles the single file and completes a one-step synthetic training save. The full AGILLM3.5 continuation run is managed separately by the disaggregated Hetzner worker setup.
