#!/usr/bin/env python3
"""Compatibility shim for the renamed AGILLM4.1 mainline runtime.

Use `agillm41.py` for new commands. This file remains importable/executable so
existing AGILLM3.5 worker paths and checkpoint tooling keep working.
"""
from pathlib import Path
import importlib.util
import sys


_TARGET = Path(__file__).with_name("agillm41.py")
_SPEC = importlib.util.spec_from_file_location("agillm41_runtime", _TARGET)
if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError(f"cannot import AGILLM4.1 runtime from {_TARGET}")
_MODULE = importlib.util.module_from_spec(_SPEC)
sys.modules.setdefault("agillm41_runtime", _MODULE)
_SPEC.loader.exec_module(_MODULE)
globals().update(
    {
        key: value
        for key, value in vars(_MODULE).items()
        if key not in {"__name__", "__file__", "__package__", "__loader__", "__spec__"}
    }
)


if __name__ == "__main__":
    raise SystemExit(_MODULE.main())
