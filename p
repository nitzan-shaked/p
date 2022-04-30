#!/usr/bin/env python3

from __future__ import annotations
import json
import os
from pathlib import Path
import shlex
import subprocess
from subprocess import CompletedProcess
import sys
from typing import Any, Iterable, Mapping, Sequence


###############################################################################
##
## PATH UTILS
##
###############################################################################

def norm_path(path: Path) -> Path:
    prefix_parts: list[str] = []
    parts = list(path.parts)
    if path.anchor:
        prefix_parts.append(parts.pop(0))

    norm_parts: list[str] = []
    for part in parts:
        assert part not in ("", ".")  # shouldn't happen with Path.parts
        if part == ".." and norm_parts and norm_parts[-1] != "..":
            norm_parts.pop()
        else:
            norm_parts.append(part)
    if path.root:  # remove leading ".."'s
        while norm_parts and norm_parts[0] == "..":
            norm_parts.pop(0)
    return Path(*prefix_parts, *norm_parts)


def traverse_up_until_file(
    from_path: Path,
    until_filename: str,
    stop_at: Path | None = None,
) -> Path | None:
    if stop_at is not None:
        if not stop_at.exists():
            raise ValueError(f"path {stop_at} does not exist")
        if not stop_at.is_dir():
            raise ValueError(f"path {stop_at} must be a directory")

    curr_path = from_path
    while True:
        maybe_path = curr_path / until_filename
        if maybe_path.is_file():
            return maybe_path
        if stop_at is not None and curr_path == stop_at:
            return None
        if curr_path.parent == curr_path:
            return None
        curr_path = curr_path.parent  # pragma: no cover


###############################################################################
##
## COMPLETION UTILS
##
###############################################################################

class CompCtx:
    def __init__(self) -> None:
        self._comp_line = os.environ["COMP_LINE"]
        self._comp_point = int(os.environ["COMP_POINT"])
        self._comp_line_to_point = self._comp_line[:self._comp_point]

        self._comp_words = shlex.split(self._comp_line)
        self._comp_words_to_point = shlex.split(self._comp_line_to_point)
        assert self._comp_words_to_point

        self._n_words = len(self._comp_words)
        self._n_words_to_point = len(self._comp_words_to_point)
        self._last_word_to_point = self._comp_words_to_point[-1]
        self._last_full_word_to_point = self._comp_words[self._n_words_to_point - 1]

        self._point_is_at_or_past_last_word = self._n_words_to_point == self._n_words
        self._point_is_in_middle_of_word = (
            self._last_word_to_point != self._last_full_word_to_point
        )
        self._point_is_exactly_at_end_of_word = self._comp_line_to_point.endswith(
            self._last_full_word_to_point
        )
        self._point_is_past_end_of_word = (
            not self._point_is_in_middle_of_word
            and not self._point_is_exactly_at_end_of_word
        )

    @property
    def comp_words(self) -> Sequence[str]:
        return self._comp_words

    @property
    def last_word_to_point(self) -> str:
        return self._last_word_to_point

    @property
    def point_is_past_end_of_word(self) -> bool:
        return self._point_is_past_end_of_word

    @property
    def point_is_exactly_at_end_of_word(self) -> bool:
        return self._point_is_exactly_at_end_of_word


###############################################################################
##
## PANTS
##
###############################################################################

class PantsCtx:
    def __init__(self, *, do_complete: bool) -> None:
        self._do_complete = do_complete
        self._cwd = Path.cwd()
        self._pants_bin_name = os.environ.get("PANTS_BIN_NAME", "pants")
        pants_bin_path = traverse_up_until_file(self._cwd, self._pants_bin_name)
        if pants_bin_path is None:
            self.fatal("error: cannot find pants binary")
        assert pants_bin_path is not None
        self._pants_bin_path = pants_bin_path
        self._repo_root = self._pants_bin_path.parent

    @property
    def pants_bin_name(self) -> str:
        return self._pants_bin_name

    @property
    def cwd(self) -> Path:
        return self._cwd

    @property
    def pants_bin_path(self) -> Path:
        return self._pants_bin_path

    @property
    def repo_root(self) -> Path:
        return self._repo_root

    def parse_rel_target(self, s: str) -> tuple[Path, str]:
        assert ":" in s
        path_str, target_name = s.split(":", 1)
        if path_str.startswith("//"):
            abs_path = self._repo_root / path_str[2:]
        else:
            path = Path(path_str)
            abs_path = path if path.is_absolute() else self._cwd / path
        abs_path = norm_path(abs_path)
        if not abs_path.is_relative_to(self._repo_root):
            self.fatal(f"{abs_path} is not in repo {self._repo_root}")
        repo_rel_path = abs_path.relative_to(self._repo_root)
        return repo_rel_path, target_name

    def pants(self, *args: str) -> CompletedProcess[str]:
        return subprocess.run(
            [str(self._pants_bin_path)] + list(args),
            cwd=self._repo_root,
            capture_output=True,
            text=True,
        )

    def fatal(self, *args: Any, **kwargs: Any) -> None:
        if not self._do_complete:
            print(*args, file=sys.stderr, **kwargs)
        sys.exit(-1)


###############################################################################
##
## MAIN
##
###############################################################################

COMPLETE_GOAL = True


def shim_rewrite_arg(arg_str: str, ctx: PantsCtx) -> str:
    out_parts: list[str] = []

    if arg_str.startswith("-") and "=" in arg_str:
        opt_str, arg_str = arg_str.split("=", 1)
        out_parts.append(f"{opt_str}=")

    if ":" in arg_str:
        repo_rel_path, arg_str = ctx.parse_rel_target(arg_str)
        out_parts.append(f"{repo_rel_path}:")

    out_parts.append(arg_str)
    return "".join(out_parts)


def output_completions(strs: Iterable[str]) -> None:
    print("\n".join(strs))
    sys.exit(0)


def main() -> None:

    do_complete = "COMP_LINE" in os.environ and "COMP_POINT" in os.environ
    pants = PantsCtx(do_complete=do_complete)

    if not do_complete:
        pants_args = tuple(
            shim_rewrite_arg(arg_str, pants)
            for arg_str in sys.argv[1:]
        )
        print(str(pants.pants_bin_path), *pants_args)
        sys.stdout.flush()
        os.chdir(str(pants.repo_root))
        os.execl(pants.pants_bin_name, pants.pants_bin_name, *pants_args)

    comp = CompCtx()

    if COMPLETE_GOAL:
        help_all_proc = pants.pants("help-all")
        if help_all_proc.returncode != 0:
            pants.fatal("help-all returned rc", help_all_proc.returncode)
        help_all_json = json.loads(help_all_proc.stdout)
        name_to_goal_info: Mapping[str, Any] = help_all_json["name_to_goal_info"]
        assert isinstance(name_to_goal_info, Mapping)

        goal: str | None = None
        available_goals = set(name_to_goal_info.keys())
        for arg_str in comp.comp_words:
            if goal is None and arg_str in available_goals:
                goal = arg_str

        # complete goal?
        if goal is None and comp.point_is_past_end_of_word:
            output_completions(available_goals)

        if (
            goal is None
            and comp.point_is_exactly_at_end_of_word
            and not comp.last_word_to_point.startswith(("-", "/", "."))
            and ":" not in comp.last_word_to_point
            and "/" not in comp.last_word_to_point
        ):
            output_completions(
                g
                for g in available_goals
                if g.startswith(comp.last_word_to_point)
            )

    # complete target name?
    if comp.point_is_exactly_at_end_of_word and ":" in comp.last_word_to_point:
        repo_rel_path, target_name = pants.parse_rel_target(comp.last_word_to_point)
        if not (pants.repo_root / repo_rel_path / "BUILD").is_file():
            pants.fatal(f"no BUILD in {pants.repo_root / repo_rel_path}")
        peek_proc = pants.pants("peek", f"{repo_rel_path}:")
        if peek_proc.returncode != 0:
            pants.fatal("peek returned rc", peek_proc.returncode)
        peek_json = json.loads(peek_proc.stdout)
        peek_targets = tuple(
            (str(j["address"]), str(j["target_type"]))
            for j in peek_json
        )
        desired_prefix = f"{repo_rel_path}:{target_name}"
        completion_targets = (
            target_addr
            for target_addr, _ in peek_targets
            if target_addr.startswith(desired_prefix)
        )
        output_completions(
            target_addr.split(":", 1)[1]
            for target_addr in completion_targets
        )


if __name__ == "__main__":
    main()
