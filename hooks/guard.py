#!/usr/bin/env python3
"""PreToolUse guard: deterministic safety rails.
Blocks: force-push, push to main/master, destructive rm, and any edit to the
intentpipe plugin itself (self-modification must go through /intentpipe:retro proposals).
Exempt: dev sessions — when the session cwd is inside the plugin root, the
plugin is the thing being developed, not used, so edits are allowed.
Exit 2 = block (stderr goes to the agent). Exit 0 = allow.
"""
import json
import os
import re
import sys

BASH_DENY = [
    (r"git\s+push\b.*(\s--force\b|\s-f\b|\+\S+:)", "force-push is forbidden"),
    # main/master must be the ref being pushed — a whole argument, or the right
    # half of a `HEAD:main` refspec. `\b(main|master)\b` also fired on
    # `feat/master-fix` and, worse, on a `gh pr create --base master` chained
    # after a perfectly good task-branch push.
    (r"git\s+push\b.*(\s|:)(refs/heads/)?(main|master)(\s|:|$)", "pushing to the default branch is forbidden; work on the task branch, task.sh merges"),
    (r"rm\s+(-\w*[rf]\w*\s+)+(/|~|\$HOME)(\s|$)", "destructive rm on / or ~ is forbidden"),
    (r"git\s+checkout\s+.*--\s+\.", "wholesale checkout-discard is forbidden; revert specific files"),
    (r"rm\s+(-\S+\s+)*\S*\bupdates/?['\"]?(\s|$)", "deleting the updates/ folder is forbidden; remove only the note files you planned — the folder and its README stay"),
    (r"rm\s+(-\S+\s+)*\S*\bupdates/\*", "wildcard rm in updates/ is forbidden (it takes README.md with it); remove planned note files by name"),
]

# One command line is usually several commands. Scanning it as one string lets a
# later command incriminate an earlier one — `git push origin task/x && gh pr
# create --base master` is a legal push and a legal PR, but `git push.*master`
# reads straight across the `&&` and blocks it. Match per segment instead, so a
# pattern only ever sees the command it is about. This cannot hide a real
# offender: splitting only ever puts MORE boundaries around it.
SEPARATORS = re.compile(r"&&|\|\||[;\n|]")


def segments(cmd: str):
    return [s for s in SEPARATORS.split(cmd) if s.strip()]


def deny(reason: str) -> None:
    print(f"BLOCKED by intentpipe guard: {reason}", file=sys.stderr)
    sys.exit(2)

def main() -> None:
    data = json.load(sys.stdin)
    tool = data.get("tool_name", "")
    tin = data.get("tool_input", {})

    if tool == "Bash":
        for seg in segments(tin.get("command", "")):
            for pattern, reason in BASH_DENY:
                if re.search(pattern, seg):
                    deny(reason)

    if tool in ("Write", "Edit", "NotebookEdit"):
        plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT", "")
        if plugin_root:
            root = os.path.realpath(plugin_root)
            cwd = os.path.realpath(data.get("cwd") or os.getcwd())
            dev_session = cwd == root or cwd.startswith(root + os.sep)
            path = os.path.realpath(tin.get("file_path", ""))
            if not dev_session and path.startswith(root + os.sep):
                deny("the intentpipe plugin is read-only inside projects; use /intentpipe:retro to propose changes")

    sys.exit(0)

if __name__ == "__main__":
    main()
