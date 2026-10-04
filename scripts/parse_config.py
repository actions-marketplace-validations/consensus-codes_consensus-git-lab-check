#!/usr/bin/env python3
"""Minimal, dependency-free parser for .consensus-lab.yml.

Supports the small YAML subset the action needs:

    key: scalar                # quoted ('...' / "...") or plain
    key: [a, "b", 'c']         # flow list
    key:                       # block list
      - a
      - "b"

Comments (# ...) and blank lines are ignored. Keys may use '-' or '_'.
Output: NUL-separated pairs  key\\0value\\0  where list items are joined
with newlines. Exit code 2 on a parse error (message on stderr).
"""
import sys

KNOWN = {
    "required-files", "min-commits", "required-branches",
    "commit-message-pattern", "forbid-files", "require-gitignore",
    "fail-on-error",
}


def strip_comment(line):
    """Remove a trailing comment that is not inside quotes."""
    quote = None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 2
                continue
            if c == quote:
                if quote == "'" and line[i + 1:i + 2] == "'":
                    i += 2
                    continue
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "#" and (i == 0 or line[i - 1] in " \t"):
            return line[:i].rstrip()
        i += 1
    return line.rstrip()


def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] == "'":
        return v[1:-1].replace("''", "'")
    if len(v) >= 2 and v[0] == v[-1] == '"':
        inner = v[1:-1]
        out, i = [], 0
        esc = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "/": "/"}
        while i < len(inner):
            c = inner[i]
            if c == "\\" and i + 1 < len(inner):
                out.append(esc.get(inner[i + 1], "\\" + inner[i + 1]))
                i += 2
                continue
            out.append(c)
            i += 1
        return "".join(out)
    return v


def split_flow(body):
    items, cur, quote = [], [], None
    for c in body:
        if quote:
            cur.append(c)
            if c == quote:
                quote = None
        elif c in "'\"":
            quote = c
            cur.append(c)
        elif c == ",":
            items.append("".join(cur))
            cur = []
        else:
            cur.append(c)
    items.append("".join(cur))
    return [unquote(x) for x in items if x.strip()]


def parse(text):
    data, order, current = {}, [], None
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = strip_comment(raw.replace("\t", "  "))
        if not line.strip() or line.strip() in ("---", "..."):
            continue
        stripped = line.lstrip()
        if stripped.startswith("- ") or stripped == "-":
            if current is None or not isinstance(data[current], list):
                raise ValueError("line %d: list item without a list key" % lineno)
            item = unquote(stripped[1:])
            if item:
                data[current].append(item)
            continue
        if line[0] in " ":
            raise ValueError("line %d: unexpected indentation" % lineno)
        if ":" not in line:
            raise ValueError("line %d: expected 'key: value'" % lineno)
        key, _, value = line.partition(":")
        key = key.strip().strip("'\"").lower().replace("_", "-")
        value = value.strip()
        if key not in order:
            order.append(key)
        current = key
        if value == "":
            data[key] = []
        elif value.startswith("[") and value.endswith("]"):
            data[key] = split_flow(value[1:-1])
        elif value in ("|", ">", "|-", ">-"):
            raise ValueError("line %d: block scalars are not supported" % lineno)
        else:
            data[key] = unquote(value)
    return data, order


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: parse_config.py FILE\n")
        return 2
    try:
        with open(sys.argv[1], encoding="utf-8") as fh:
            data, order = parse(fh.read())
    except (OSError, ValueError) as exc:
        sys.stderr.write("%s: %s\n" % (sys.argv[1], exc))
        return 2
    out = sys.stdout.buffer
    for key in order:
        if key not in KNOWN:
            sys.stderr.write("warning: unknown key '%s' ignored\n" % key)
            continue
        val = data[key]
        if isinstance(val, list):
            val = "\n".join(val)
        out.write(key.encode() + b"\0" + val.encode() + b"\0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
