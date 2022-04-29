#!/usr/bin/env python3

from __future__ import annotations
import json
from pathlib import Path
import os
import shlex
from subprocess import CompletedProcess
import sys
from typing import Any, Mapping

from utils.path_utils import traverse_up_until_file, norm_path
from utils.subproc_utils import subproc


do_shim: bool = False
do_complete: bool = False


def fatal(*args: Any, **kwargs: Any) -> None:
    if not do_complete:
        print(*args, file=sys.stderr, **kwargs)
    sys.exit(-1)


def parse_rel_target(
    s: str, *,
    cwd: Path,
    repo_root: Path,
) -> tuple[Path, str]:
    assert ":" in s
    path_str, target_name = s.split(":", 1)
    if path_str.startswith("//"):
        abs_path = repo_root / path_str[2:]
    else:
        path = Path(path_str)
        abs_path = path if path.is_absolute() else cwd / path
    abs_path = norm_path(abs_path)
    if not abs_path.is_relative_to(repo_root):
        fatal(f"{abs_path} is not in repo {repo_root}")
    repo_rel_path = abs_path.relative_to(repo_root)
    return repo_rel_path, target_name


def rewrite_arg(
    arg_str: str, *,
    cwd: Path,
    repo_root: Path,
) -> str:
    out_parts: list[str] = []

    if arg_str.startswith("-") and "=" in arg_str:
        opt_str, arg_str = arg_str.split("=", 1)
        out_parts.append(f"{opt_str}=")

    if ":" in arg_str:
        repo_rel_path, arg_str = parse_rel_target(
            arg_str,
            cwd=cwd,
            repo_root=repo_root,
        )
        out_parts.append(f"{repo_rel_path}:")

    out_parts.append(arg_str)

    return "".join(out_parts)


class PantsCtx:
    def __init__(self, *, do_complete: bool) -> None:
        self._do_complete = do_complete
        self._cwd = Path.cwd()
        self._pants_bin_name = os.environ.get("PANTS_BIN_NAME", "pants")
        pants_bin_path = traverse_up_until_file(self._cwd, self._pants_bin_name)
        if pants_bin_path is None:
            fatal("error: cannot find pants binary")
        assert pants_bin_path is not None
        self._pants_bin_path = pants_bin_path
        self._repo_root = self._pants_bin_path.parent

    def pants(self, *args: str) -> CompletedProcess[str]:
        return subproc(self._repo_root, (str(self._pants_bin_path), *args))




def main() -> None:

    # get prog name
    prog_path = Path(sys.argv[0])
    prog_name = prog_path.name

    global do_shim, do_complete
    if prog_name == "p":
        do_shim = True
    elif prog_name == "p_complete":
        do_complete = True
    else:
        fatal("unknown name", prog_name)

    # init: find cwd, pants bin, and repo root
    cwd = Path.cwd()
    pants_bin_name = os.environ.get("PANTS_BIN_NAME", "pants")
    pants_bin_path = traverse_up_until_file(cwd, pants_bin_name)
    if pants_bin_path is None:
        fatal("error: cannot find pants binary")
    assert pants_bin_path is not None
    repo_root = pants_bin_path.parent

    def pants(*args: str) -> CompletedProcess[str]:
        return subproc(repo_root, (str(pants_bin_path), *args))

    if do_shim:
        pants_args = tuple(
            rewrite_arg(arg_str, cwd=cwd, repo_root=repo_root)
            for arg_str in sys.argv[1:]
        )
        print(str(pants_bin_path), *pants_args)
        sys.stdout.flush()
        os.chdir(str(repo_root))
        os.execl(str(pants_bin_name), pants_bin_name, *pants_args)

    if do_complete:
        comp_line = os.environ["COMP_LINE"]
        comp_point = int(os.environ["COMP_POINT"])
        comp_line_to_point = comp_line[:comp_point]

        comp_words = shlex.split(comp_line)
        comp_words_to_point = shlex.split(comp_line_to_point)
        assert comp_words_to_point

        # n_words = len(comp_words)
        n_words_to_point = len(comp_words_to_point)
        last_word_to_point = comp_words_to_point[-1]
        last_full_word_to_point = comp_words[n_words_to_point - 1]

        # point_is_at_or_past_last_word = n_words_to_point == n_words
        point_is_in_middle_of_word = last_word_to_point != last_full_word_to_point
        point_is_exactly_at_end_of_word = comp_line_to_point.endswith(last_full_word_to_point)
        point_is_past_end_of_word = (
            not point_is_in_middle_of_word
            and not point_is_exactly_at_end_of_word
        )

        help_all_proc = pants("help-all")
        if help_all_proc.returncode != 0:
            fatal("help-all returned rc", help_all_proc.returncode)
        help_all_json = json.loads(help_all_proc.stdout)
        # help_all_json = json.loads(open("/tmp/x").read())
        name_to_goal_info: Mapping[str, Any] = help_all_json["name_to_goal_info"]
        assert isinstance(name_to_goal_info, Mapping)

        goal: str | None = None
        available_goals = set(name_to_goal_info.keys())
        for arg_str in comp_words:
            if goal is None and arg_str in available_goals:
                goal = arg_str

        # complete goal?
        if goal is None:
            if point_is_past_end_of_word:
                print("\n".join(available_goals))
                sys.exit(0)
            if point_is_exactly_at_end_of_word:
                print("\n".join(g for g in available_goals if g.startswith(last_word_to_point)))
                sys.exit(0)

        # complete target name?
        if point_is_exactly_at_end_of_word and ":" in last_word_to_point:
            repo_rel_path, target_name = parse_rel_target(
                last_word_to_point,
                cwd=cwd,
                repo_root=repo_root,
            )
            if not (repo_root / repo_rel_path / "BUILD").is_file():
                fatal(f"no BUILD in {repo_root / repo_rel_path}")
            peek_proc = pants("peek", f"{repo_rel_path}:")
            if peek_proc.returncode != 0:
                fatal("peek returned rc", peek_proc.returncode)
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
            print("\n".join(
                target_addr.split(":", 1)[1]
                for target_addr in completion_targets
            ))
            sys.exit(0)


if __name__ == "__main__":
    main()
