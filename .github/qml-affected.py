#!/usr/bin/env python3
"""The QML files a pull request's qmllint run must cover.

  python3 .github/qml-affected.py BASE_SHA

Prints, one per line and sorted, every tracked .qml outside tests/ that
changed between BASE_SHA and HEAD, plus every such .qml that depends on a
changed .qml, .js/.mjs or qmldir, transitively: through an implicit
same-directory type, a directory import ('import "dir"') of a type it names,
a qmldir entry, or a JavaScript import. A deleted or renamed file still
selects the files that used it. Prints nothing when no QML is affected.

Exits non-zero on any error; the qmllint job then lints every file. Only the
standard library and git are needed.
"""

import os
import re
import subprocess
import sys

QML_IMPORT = re.compile(r'^\s*\.?import\s+"([^"]+)"', re.M)
ES_IMPORT = re.compile(r"""(?:\bfrom\s+|\bimport\s*\(?\s*|\brequire\s*\(\s*)["'](\.{1,2}/[^"']+)["']""")
TYPE_IDENT = re.compile(r"\b[A-Z][A-Za-z0-9_]*\b")
QMLDIR_ENTRY = re.compile(r"^\s*(?:singleton\s+)?([A-Z][A-Za-z0-9_]*)\s+(?:\d+\.\d+\s+)?(\S+\.(?:qml|js|mjs))\s*$", re.M)


def git(*args):
    return subprocess.run(["git", "-c", "core.quotepath=off", *args], check=True,
                          capture_output=True, text=True).stdout


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def main(base):
    tracked = [p for p in git("ls-files", "-z").split("\0") if p]
    qml = [p for p in tracked if p.endswith(".qml")]
    imports, idents, qmldirs = {}, {}, {}
    for p in tracked:
        d = os.path.dirname(p)
        if os.path.basename(p) == "qmldir":
            qmldirs[d] = {t: os.path.normpath(os.path.join(d, f)) for t, f in QMLDIR_ENTRY.findall(read(p))}
        elif p.endswith((".qml", ".js", ".mjs")):
            text = read(p)
            targets = QML_IMPORT.findall(text) + (ES_IMPORT.findall(text) if not p.endswith(".qml") else [])
            imports[p] = {os.path.normpath(os.path.join(d, t)) for t in targets if "://" not in t}
            idents[p] = set(TYPE_IDENT.findall(text)) if p.endswith(".qml") else set()

    def type_users(directory, type_name):
        return {g for g in qml if type_name in idents[g]
                and (os.path.dirname(g) == directory or directory in imports[g])}

    def dependents(path):
        d, name = os.path.split(path)
        out = set()
        if name == "qmldir":
            out |= {g for g in qml if os.path.dirname(g) == d or d in imports[g]}
        if name.endswith(".qml") and name[:1].isupper():
            out |= type_users(d, name[:-4])
        if name.endswith((".js", ".mjs")):
            out |= {g for g, imps in imports.items() if path in imps}
        for qd, types in qmldirs.items():
            for t, target in types.items():
                if target == path:
                    out |= type_users(qd, t)
        out.discard(path)
        return out

    changed = [p for p in git("diff", "--name-only", "--no-renames", "-z", base, "HEAD").split("\0") if p]
    seen, todo = set(), [p for p in changed
                         if p.endswith((".qml", ".js", ".mjs")) or os.path.basename(p) == "qmldir"]
    while todo:
        p = todo.pop()
        if p not in seen:
            seen.add(p)
            todo.extend(dependents(p) - seen)
    for p in sorted(f for f in seen if f in idents and f.endswith(".qml") and not f.startswith("tests/")):
        print("./" + p)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
