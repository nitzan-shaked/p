#!/usr/bin/env python3

from __future__ import annotations
from pathlib import Path
import subprocess
from subprocess import CompletedProcess
from typing import Sequence


def subproc(
    cwd: Path,
    cmd: Sequence[str],
) -> CompletedProcess[str]:
    args = list(cmd)
    retval = subprocess.run(
        args,
        cwd=cwd,
        capture_output=True,
        text=True,
    )
    return retval
