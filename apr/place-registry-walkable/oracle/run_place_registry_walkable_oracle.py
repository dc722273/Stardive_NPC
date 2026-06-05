#!/usr/bin/env python3
"""Run the frozen place-registry-walkable Godot oracle.

The wrapper treats the Godot script as successful only when it prints the
explicit PASS marker. Godot compile errors, script errors, or failed assertions
therefore become oracle failures instead of infrastructure success.
"""

from __future__ import annotations

import subprocess
import sys
import traceback
from pathlib import Path


PASS_MARKER = "PLACE_REGISTRY_WALKABLE_ORACLE: PASS"


def main() -> int:
    repo_root = Path(__file__).resolve().parents[3]
    godot_ps1 = repo_root / "tools" / "godot" / "godot.ps1"
    oracle_script = "apr/place-registry-walkable/oracle/place_registry_walkable_oracle.gd"

    cmd = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(godot_ps1),
        "--headless",
        "--script",
        oracle_script,
    ]
    proc = subprocess.run(cmd, cwd=repo_root, capture_output=True, text=True, timeout=120)
    output = (proc.stdout or "") + (proc.stderr or "")
    print(output, end="")

    assert PASS_MARKER in output, (
        "place-registry-walkable oracle did not print PASS marker. "
        f"Godot exit={proc.returncode}\n--- output ---\n{output[-6000:]}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(exc, file=sys.stderr)
        raise SystemExit(1)
    except Exception:
        traceback.print_exc()
        raise SystemExit(2)
