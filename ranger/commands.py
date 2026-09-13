# Ranger custom commands for dots (fzf helpers).
from __future__ import absolute_import, division, unicode_literals

import os
import subprocess

from ranger.api.commands import Command


class fzf_select(Command):
    """:fzf_select — find a file with fd+fzf and select it."""

    def execute(self):
        cmd = (
            "fd --type f --hidden --follow --exclude .git 2>/dev/null "
            "| fzf --height=40%"
        )
        try:
            path = subprocess.check_output(
                ["bash", "-lc", cmd], universal_newlines=True
            ).strip()
        except (subprocess.CalledProcessError, OSError):
            return
        if path:
            self.fm.select_file(path)


class fzf_content(Command):
    """:fzf_content — ripgrep + fzf jump to a matching file."""

    def execute(self):
        cmd = (
            "rg --line-number --no-heading --color=always . 2>/dev/null "
            "| fzf --ansi --delimiter=: "
            "--preview 'bat --style=numbers --color=always --highlight-line {2} {1} 2>/dev/null || true' "
            "| cut -d: -f1"
        )
        try:
            path = subprocess.check_output(
                ["bash", "-lc", cmd], universal_newlines=True
            ).strip()
        except (subprocess.CalledProcessError, OSError):
            return
        if path and os.path.exists(path):
            self.fm.select_file(path)
