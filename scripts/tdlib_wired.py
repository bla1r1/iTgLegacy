#!/usr/bin/env python3
"""tdlib_wired.py - split named td_api functions into reachable and bare.

`tdlib_coverage.sh` counts every td_api name that appears as a string literal
in src/. That number includes names written into a method no screen ever
calls: the method exists, a test may even drive it, and the app still cannot
reach it. This helper walks the Objective-C method blocks, finds which ones
name a td_api function, and asks whether the rest of src calls that method.

A function counts as wired when at least one of its literals sits outside a
method block, or inside a method block with a call site elsewhere in src.
Tests are deliberately not part of the count: a test that drives a dead
method is exactly the false confidence this split is meant to expose.

    python3 scripts/tdlib_wired.py --wired
    python3 scripts/tdlib_wired.py --bare
    python3 scripts/tdlib_wired.py --counts   # "wired bare"
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TL = ROOT / "tdlib" / "td" / "td" / "generate" / "scheme" / "td_api.tl"


def td_api_functions():
    """Function names from the ---functions--- half of td_api.tl."""
    names = set()
    in_functions = False
    for line in TL.read_text().splitlines():
        if line.startswith("---functions---"):
            in_functions = True
            continue
        if not in_functions:
            continue
        match = re.match(r"^([a-z][A-Za-z0-9_]*) ", line)
        if match:
            names.add(match.group(1))
    return names


def source_files():
    return list((ROOT / "src").rglob("*.m")) + list((ROOT / "src").rglob("*.mm"))


def strip_comments(text):
    """Remove // and /* */ comments, keeping string literals intact."""
    out = []
    i = 0
    state = None
    while i < len(text):
        char = text[i]
        if state is None:
            if char == "/" and i + 1 < len(text) and text[i + 1] == "/":
                state = "line"
                i += 2
                continue
            if char == "/" and i + 1 < len(text) and text[i + 1] == "*":
                state = "block"
                i += 2
                continue
            if char == '"':
                state = "string"
            out.append(char)
            i += 1
        elif state == "line":
            if char == "\n":
                state = None
                out.append(char)
            i += 1
        elif state == "block":
            if char == "*" and i + 1 < len(text) and text[i + 1] == "/":
                state = None
                i += 2
            else:
                i += 1
        else:
            out.append(char)
            if char == "\\" and i + 1 < len(text):
                out.append(text[i + 1])
                i += 2
                continue
            if char == '"':
                state = None
            i += 1
    return "".join(out)


def string_literals(line):
    return re.findall(r'@"([A-Za-z0-9_]+)"', line)


def brace_delta(line):
    """Net braces on a line, ignoring braces inside string or char literals."""
    depth = 0
    state = None
    i = 0
    while i < len(line):
        char = line[i]
        if state:
            if char == "\\":
                i += 2
                continue
            if char == state:
                state = None
        elif char in "\"'":
            state = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        i += 1
    return depth


def method_blocks(lines):
    """Yield (selector, start, end) for top-level Objective-C methods.

    The body ends where its braces balance, not where the next method starts:
    a plain C function between two methods would otherwise be swallowed by the
    method above it, and a call it makes would not count as a call site.
    """
    for start, line in enumerate(lines):
        match = re.match(r"^[-+] \([^)]*\)\s*([A-Za-z0-9_]+)", line)
        if not match:
            continue
        depth = 0
        opened = False
        end = start
        for end in range(start, len(lines)):
            delta = brace_delta(lines[end])
            if delta:
                opened = True
            depth += delta
            if opened and depth <= 0:
                break
        yield match.group(1), start, end + 1


def classify():
    all_functions = td_api_functions()
    files = {}
    for path in source_files():
        files[path] = strip_comments(path.read_text(errors="ignore")).splitlines()

    blocks = []
    selectors = set()
    for path, lines in files.items():
        for selector, start, end in method_blocks(lines):
            blocks.append((path, selector, start, end))
            selectors.add(selector)

    # One pass over src for every selector we care about. Doing this per method
    # is O(methods x source) and painfully slow on a phone-sized tree.
    uses = {selector: [] for selector in selectors}
    identifier = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\b")
    for path, lines in files.items():
        for index, line in enumerate(lines):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("*"):
                continue
            if re.match(r"^[-+] \(", line):
                continue
            for match in identifier.finditer(line):
                name = match.group(1)
                if name in uses:
                    uses[name].append((path, index))

    def reachable(path, selector, start, end):
        for used_path, used_index in uses[selector]:
            if used_path == path and start <= used_index < end:
                continue
            return True
        return False

    # Every literal occurrence and whether its method block can be reached
    # from somewhere else in src.
    occurrences = {name: [] for name in all_functions}  # name -> [reachable]
    covered = {}
    for path, selector, start, end in blocks:
        covered.setdefault(path, set()).update(range(start, end))
        can_reach = reachable(path, selector, start, end)
        names = set()
        for index in range(start, end):
            names.update(string_literals(files[path][index]))
        for name in names & all_functions:
            occurrences[name].append(can_reach)

    # Literals outside a method block are top-level request builders,
    # constants, or something else static: treat them as reachable.
    for path, lines in files.items():
        skip = covered.get(path, set())
        for index, line in enumerate(lines):
            if index in skip:
                continue
            for name in string_literals(line):
                if name in all_functions:
                    occurrences[name].append(True)

    wired = {name for name, places in occurrences.items() if places and any(places)}
    bare = {name for name, places in occurrences.items() if places and not any(places)}
    return wired, bare


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--wired"
    wired, bare = classify()
    if mode == "--wired":
        print("\n".join(sorted(wired)))
    elif mode == "--bare":
        print("\n".join(sorted(bare)))
    elif mode == "--counts":
        print(f"{len(wired)} {len(bare)}")
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
