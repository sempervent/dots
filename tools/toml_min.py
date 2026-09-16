#!/usr/bin/env python3
"""Minimal TOML subset parser for DOTS bootstrap configs (Python 3.6+).

Supports the subset DOTS emits: comments, [table], [[aot]], strings, bools,
ints, and arrays (including multi-line string arrays). Not a full TOML 1.0
implementation — deliberately narrow so bootstrap never needs tomllib/3.11.
"""
from __future__ import print_function

import json
import re
import sys


def _parse_string(s, i):
    if i >= len(s) or s[i] != '"':
        raise ValueError("expected string at %d" % i)
    i += 1
    out = []
    while i < len(s):
        c = s[i]
        if c == '"':
            return "".join(out), i + 1
        if c == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            mapping = {'"': '"', "\\": "\\", "n": "\n", "t": "\t", "r": "\r"}
            out.append(mapping.get(nxt, nxt))
            i += 2
            continue
        out.append(c)
        i += 1
    raise ValueError("unterminated string")


def _skip_ws_nl(s, i):
    while i < len(s) and s[i] in " \t\r\n":
        i += 1
    return i


def _skip_comment(s, i):
    if i < len(s) and s[i] == "#":
        while i < len(s) and s[i] not in "\r\n":
            i += 1
    return i


def _parse_value(s, i):
    i = _skip_ws_nl(s, i)
    i = _skip_comment(s, i)
    i = _skip_ws_nl(s, i)
    if i >= len(s):
        raise ValueError("unexpected EOF in value")
    if s[i] == '"':
        return _parse_string(s, i)
    if s.startswith("true", i) and (i + 4 >= len(s) or not (s[i + 4].isalnum() or s[i + 4] == "_")):
        return True, i + 4
    if s.startswith("false", i) and (i + 5 >= len(s) or not (s[i + 5].isalnum() or s[i + 5] == "_")):
        return False, i + 5
    if s[i] == "[":
        return _parse_array(s, i)
    m = re.match(r"-?\d+", s[i:])
    if m:
        return int(m.group(0)), i + len(m.group(0))
    raise ValueError("unsupported value near: %r" % (s[i : i + 40],))


def _parse_array(s, i):
    assert s[i] == "["
    i += 1
    items = []
    while True:
        i = _skip_ws_nl(s, i)
        i = _skip_comment(s, i)
        i = _skip_ws_nl(s, i)
        if i < len(s) and s[i] == "]":
            return items, i + 1
        if i < len(s) and s[i] == ",":
            i += 1
            continue
        val, i = _parse_value(s, i)
        items.append(val)
        i = _skip_ws_nl(s, i)
        i = _skip_comment(s, i)
        i = _skip_ws_nl(s, i)
        if i < len(s) and s[i] == ",":
            i += 1
            continue
        if i < len(s) and s[i] == "]":
            return items, i + 1
        raise ValueError("expected ',' or ']' near: %r" % (s[i : i + 40],))


def _strip_inline_comment(rest):
    in_str = False
    for j, ch in enumerate(rest):
        if ch == '"' and (j == 0 or rest[j - 1] != "\\"):
            in_str = not in_str
        elif ch == "#" and not in_str:
            return rest[:j].rstrip()
    return rest.rstrip()


def loads(text):
    root = {}
    current = root
    # Join physical lines into logical lines, keeping multi-line arrays intact
    # by feeding the whole text to a line-oriented state machine.
    lines = text.splitlines()
    idx = 0
    while idx < len(lines):
        raw = lines[idx]
        idx += 1
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue

        m = re.match(r"^\[\[([A-Za-z0-9_.-]+)\]\]\s*(?:#.*)?$", stripped)
        if m:
            name = m.group(1)
            if name not in root or not isinstance(root[name], list):
                root[name] = []
            current = {}
            root[name].append(current)
            continue

        m = re.match(r"^\[([A-Za-z0-9_.-]+)\]\s*(?:#.*)?$", stripped)
        if m:
            name = m.group(1)
            if name not in root or not isinstance(root[name], dict):
                root[name] = {}
            current = root[name]
            continue

        m = re.match(r"^([A-Za-z0-9_.-]+)\s*=\s*(.*)$", stripped)
        if not m:
            raise ValueError("cannot parse line: %r" % (raw,))
        key, rest = m.group(1), m.group(2)
        rest = _strip_inline_comment(rest)

        body = rest
        if body.lstrip().startswith("["):
            while body.count("[") > body.count("]"):
                if idx >= len(lines):
                    raise ValueError("unterminated array for key %s" % key)
                nxt = _strip_inline_comment(lines[idx])
                idx += 1
                body = body + "\n" + nxt

        val, _ = _parse_value(body.strip(), 0)
        current[key] = val

    return root


def main():
    if len(sys.argv) < 2:
        print("usage: toml_min.py <file>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path, "r") as fh:
        data = loads(fh.read())
    json.dump(data, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
