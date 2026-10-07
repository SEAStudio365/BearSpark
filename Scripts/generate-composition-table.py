#!/usr/bin/env python3
"""Builds ChiaKey-Source/DataTables/han-compositions.txt from BabelStone IDS.

Typing the parts of a character in writing order and opening the candidate
window offers the character: 水水水 → 淼, 木木木 → 森, 日月 → 明.

Each character's Ideographic Description Sequence is split into its parts,
and every part that is itself described is optionally split further, so 森
(⿱木林, 林 = ⿰木木) is reachable as both 木林 and 木木木. Only sequences of two
to four typable characters (the main CJK block and Extension A) are kept, and
only for characters in those blocks.

Source: https://babelstone.co.uk/CJK/IDS.TXT by Andrew West, who places the
data and its format at everyone's free use without permission or attribution.
Run this again to pick up a newer IDS release; the build needs no network.

Output, one sequence per line:  <parts>\t<character> <character> ...
With --lexicon, characters the lexicon uses most come first; otherwise those
reached by splitting fewer times, then the main CJK block before Extension A. Unambiguous side forms (釒, 氵, 亻 …) count as the
full character, since only that can be typed.
"""

import argparse
import re
import sqlite3
import sys
import urllib.request
from itertools import product
from pathlib import Path

IDS_URL = "https://babelstone.co.uk/CJK/IDS.TXT"
MIN_PARTS, MAX_PARTS = 2, 4
IDC = {chr(c): (3 if chr(c) in "⿲⿳" else 2) for c in range(0x2FF0, 0x2FFC)}
IDC.update({"⿼": 2, "⿽": 2, "⿾": 1, "⿿": 1, "㇯": 2})

# Side forms that only ever stand for one character, so 金 typed in full still
# finds 鑫 (⿱金鍂, 鍂 = ⿰釒金). Ambiguous ones such as 阝 (阜 or 邑) stay out.
SIDE_FORMS = {
    "釒": "金", "牜": "牛", "氵": "水", "扌": "手", "亻": "人", "忄": "心",
    "犭": "犬", "礻": "示", "衤": "衣", "飠": "食", "糹": "糸", "訁": "言",
    "灬": "火", "刂": "刀",
}

OUTPUT = (Path(__file__).resolve().parent.parent / "ChiaKey-Source" /
          "DataTables" / "han-compositions.txt")


def typable(ch):
    code = ord(ch)
    return 0x4E00 <= code <= 0x9FFF or 0x3400 <= code <= 0x4DBF


def parse(ids):
    """IDS string -> list of immediate parts (each a character), or None."""
    tokens = list(ids)

    def node(i):
        ch = tokens[i]
        if ch in IDC:
            children, i = [], i + 1
            for _ in range(IDC[ch]):
                child, i = node(i)
                children.append(child)
            return ("op", ch, children), i
        return ("leaf", ch), i + 1

    try:
        tree, end = node(0)
    except IndexError:
        return None
    if end != len(tokens):
        return None

    parts = []

    def flatten(t):
        if t[0] == "leaf":
            parts.append(SIDE_FORMS.get(t[1], t[1]))
        else:
            if t[1] in "⿾⿿":  # mirrored or rotated forms: not a plain sum of parts
                raise ValueError
            for c in t[2]:
                flatten(c)

    try:
        flatten(tree)
    except ValueError:
        return None
    return parts


def character_frequencies(lexicon):
    """Highest unigram log probability of each single character."""
    best = {}
    with sqlite3.connect(lexicon) as db:
        for text, probability in db.execute(
                "SELECT current, probability FROM unigrams"):
            if isinstance(text, str) and len(text) == 1:
                best[text] = max(best.get(text, -1e9), float(probability))
    return best


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--lexicon", help="ChiaKeySource.db to rank by usage")
    args = parser.parse_args()
    frequency = character_frequencies(args.lexicon) if args.lexicon else {}

    text = urllib.request.urlopen(IDS_URL, timeout=120).read().decode("utf-8-sig")
    date = re.search(r"# File Date: (\S+)", text).group(1)
    version = re.search(r"# Unicode Version: ([\d.]+)", text).group(1)

    structure = {}  # character -> immediate parts (first IDS that parses)
    for line in text.splitlines():
        if line.startswith("#") or "\t" not in line:
            continue
        fields = line.rstrip("\r").split("\t")
        ch = fields[1]
        for raw in fields[2:]:
            ids = re.sub(r"\$.*$", "", raw).lstrip("^")
            if not ids or ids == ch:
                continue
            parts = parse(ids)
            if parts and len(parts) > 1:
                structure[ch] = parts
                break

    def spellings(ch, depth):
        """Every way to write ch as parts, with how many splits it took."""
        results = {(ch,): 0}
        if depth == 0 or ch not in structure:
            return results
        options = [spellings(p, depth - 1) for p in structure[ch]]
        for combo in product(*[list(o.items()) for o in options]):
            seq = tuple(c for part, _ in combo for c in part)
            if len(seq) > MAX_PARTS:
                continue
            splits = 1 + sum(s for _, s in combo)
            if seq not in results or splits < results[seq]:
                results[seq] = splits
        return results

    table = {}  # sequence -> {character: splits}
    for ch in structure:
        if not typable(ch):
            continue
        for seq, splits in spellings(ch, 3).items():
            if len(seq) < MIN_PARTS or not all(typable(p) for p in seq):
                continue
            table.setdefault("".join(seq), {})[ch] = splits

    lines = []
    for seq in sorted(table):
        ranked = sorted(table[seq], key=lambda c: (
            -frequency.get(c, -1e9), table[seq][c], ord(c) < 0x4E00, ord(c)))
        lines.append(seq + "\t" + " ".join(ranked))

    header = [
        "# Han characters by their parts in writing order.",
        f"# Generated by Scripts/generate-composition-table.py from BabelStone IDS "
        f"(Unicode {version}, {date})"
        + (", ranked by lexicon usage," if frequency else ","),
        "# https://babelstone.co.uk/CJK/IDS.TXT by Andrew West, free to use without",
        "# permission or attribution.",
        "# Format: <parts>\\t<character> <character> ...",
    ]
    OUTPUT.write_text("\n".join(header + lines) + "\n", encoding="utf-8")
    print(f"wrote {len(lines)} sequences to {OUTPUT}")


if __name__ == "__main__":
    sys.exit(main())
