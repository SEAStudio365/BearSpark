#!/usr/bin/env python3
"""Builds ChiaKey-Source/DataTables/rare-readings.txt from Unicode's Unihan.

The lexicon holds few characters past CJK Extension A, so a rare character
such as 𢦏 (U+2298F, zāi) cannot be typed by its reading. This table gives each
ideograph from Extension B on that the lexicon lacks its Unihan kMandarin
readings in Bopomofo; with "Show rare characters from Extension B on" turned
on, they follow the lexicon's own candidates for that reading.

kMandarin is in Hanyu Pinyin with tone marks. Where it gives two readings the
first is the one preferred in mainland China and the second the one preferred
in Taiwan, so the second comes first here.

Source: https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip
(c) 1991-2025 Unicode, Inc., under the Unicode License v3
(https://www.unicode.org/license.txt).

  Scripts/generate-rare-readings.py --unihan path/to/Unihan_Readings.txt \\
      --lexicon path/to/ChiaKeySource.db
  Scripts/generate-rare-readings.py --unihan ... --lexicon ... --check

--check converts the kMandarin readings of characters the lexicon already
has and reports how often the result is one of the lexicon's own readings for
that character, to vet the Pinyin conversion; it writes nothing.

Output, one reading per line:  <bopomofo>\\t<character> <character> ...
"""

import argparse
import sqlite3
import sys
import unicodedata
from pathlib import Path

OUTPUT = (Path(__file__).resolve().parent.parent / "ChiaKey-Source" /
          "DataTables" / "rare-readings.txt")

# CJK Unified Ideographs from Extension B on (the compatibility supplement,
# 2F800-2FA1F, is left out: those are variants, not characters of their own).
RARE_BLOCKS = [
    (0x20000, 0x2A6DF),  # B
    (0x2A700, 0x2EE5F),  # C, D, E, F, I
    (0x30000, 0x323AF),  # G, H
]

INITIALS = {
    "b": "ㄅ", "p": "ㄆ", "m": "ㄇ", "f": "ㄈ", "d": "ㄉ", "t": "ㄊ",
    "n": "ㄋ", "l": "ㄌ", "g": "ㄍ", "k": "ㄎ", "h": "ㄏ", "j": "ㄐ",
    "q": "ㄑ", "x": "ㄒ", "zh": "ㄓ", "ch": "ㄔ", "sh": "ㄕ", "r": "ㄖ",
    "z": "ㄗ", "c": "ㄘ", "s": "ㄙ",
}
FINALS = {
    "a": "ㄚ", "o": "ㄛ", "e": "ㄜ", "ê": "ㄝ", "ai": "ㄞ", "ei": "ㄟ",
    "ao": "ㄠ", "ou": "ㄡ", "an": "ㄢ", "en": "ㄣ", "ang": "ㄤ", "eng": "ㄥ",
    "er": "ㄦ", "ong": "ㄨㄥ",
    "i": "ㄧ", "ia": "ㄧㄚ", "io": "ㄧㄛ", "ie": "ㄧㄝ", "iai": "ㄧㄞ",
    "iao": "ㄧㄠ", "iu": "ㄧㄡ", "ian": "ㄧㄢ", "in": "ㄧㄣ", "iang": "ㄧㄤ",
    "ing": "ㄧㄥ", "iong": "ㄩㄥ",
    "u": "ㄨ", "ua": "ㄨㄚ", "uo": "ㄨㄛ", "uai": "ㄨㄞ", "ui": "ㄨㄟ",
    "uan": "ㄨㄢ", "un": "ㄨㄣ", "uang": "ㄨㄤ", "ueng": "ㄨㄥ",
    "ü": "ㄩ", "üe": "ㄩㄝ", "üan": "ㄩㄢ", "ün": "ㄩㄣ",
}
# Syllables without an initial spell their medial with y or w.
ZERO_INITIAL = {
    "yi": "i", "ya": "ia", "yo": "io", "ye": "ie", "yai": "iai", "yao": "iao",
    "you": "iu", "yan": "ian", "yin": "in", "yang": "iang", "ying": "ing",
    "yong": "iong", "yu": "ü", "yue": "üe", "yuan": "üan", "yun": "ün",
    "wu": "u", "wa": "ua", "wo": "uo", "wai": "uai", "wei": "ui", "wan": "uan",
    "wen": "un", "wang": "uang", "weng": "ueng",
}
TONE_MARKS = {"̄": 1, "́": 2, "̌": 3, "̀": 4}
TONE_SUFFIX = {1: "", 2: "ˊ", 3: "ˇ", 4: "ˋ", 5: "˙"}


def to_bopomofo(pinyin):
    """zāi to ㄗㄞ; None for what is not one Mandarin syllable (hm, ng, ...)."""
    tone = 5
    letters = []
    for ch in unicodedata.normalize("NFD", pinyin.lower()):
        if ch in TONE_MARKS:
            tone = TONE_MARKS[ch]
        elif ch == "̈":  # the umlaut of ü, recomposed below
            letters.append("̈")
        else:
            letters.append(ch)
    syllable = unicodedata.normalize("NFC", "".join(letters))
    if not syllable.isalpha():
        return None

    initial = ""
    for candidate in ("zh", "ch", "sh"):
        if syllable.startswith(candidate):
            initial = candidate
            break
    if not initial and syllable[0] in INITIALS:
        initial = syllable[0]
    final = syllable[len(initial):]

    if not initial:
        final = ZERO_INITIAL.get(syllable, syllable)
    elif initial in ("j", "q", "x") and final.startswith("u"):
        final = "ü" + final[1:]  # ju is jü
    if initial in ("zh", "ch", "sh", "r", "z", "c", "s") and final == "i":
        final = ""  # zhi, ci: the initial alone

    if final and final not in FINALS:
        return None
    if not initial and not final:
        return None
    return INITIALS.get(initial, "") + FINALS.get(final, "") + TONE_SUFFIX[tone]


# The lexicon keys a reading by its absolute order (Mandarin.h), two
# characters; these mirror BopomofoSyllable's components to check against it.
CONSONANTS = "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ"
MIDDLES = "ㄧㄨㄩ"
VOWELS = "ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ"
TONES = {"ˊ": 1, "ˇ": 2, "ˋ": 3, "˙": 4}


def absolute_order_string(bopomofo):
    consonant = middle = vowel = tone = 0
    for ch in bopomofo:
        if ch in CONSONANTS:
            consonant = CONSONANTS.index(ch) + 1
        elif ch in MIDDLES:
            middle = MIDDLES.index(ch) + 1
        elif ch in VOWELS:
            vowel = VOWELS.index(ch) + 1
        elif ch in TONES:
            tone = TONES[ch]
    order = consonant + middle * 22 + vowel * 22 * 4 + tone * 22 * 4 * 14
    return chr(48 + order % 79) + chr(48 + order // 79)


def is_rare(ch):
    code = ord(ch)
    return any(lo <= code <= hi for lo, hi in RARE_BLOCKS)


def unihan_mandarin(path):
    """Each character's kMandarin readings, the Taiwan one first."""
    readings = {}
    with open(path, encoding="utf-8") as stream:
        for line in stream:
            if line.startswith("#") or "\tkMandarin\t" not in line:
                continue
            code, _, value = line.rstrip("\n").split("\t")
            ch = chr(int(code[2:], 16))
            readings[ch] = list(reversed(value.split()))
    return readings


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--unihan", required=True,
                        help="Unihan_Readings.txt from Unihan.zip")
    parser.add_argument("--lexicon", required=True,
                        help="ChiaKeySource.db; its characters are left out")
    parser.add_argument("--check", action="store_true",
                        help="vet the conversion against the lexicon instead")
    parser.add_argument("--output", default=str(OUTPUT))
    args = parser.parse_args()

    mandarin = unihan_mandarin(args.unihan)
    db = sqlite3.connect(f"file:{args.lexicon}?mode=ro", uri=True)
    known = {row[0] for row in db.execute(
        "SELECT DISTINCT current FROM unigrams")}

    if args.check:
        lexicon_readings = {}
        for key, value in db.execute(
                "SELECT key, value FROM 'Mandarin-bpmf-cin'"):
            lexicon_readings.setdefault(value, set()).add(key)
        checked = matched = unconverted = 0
        misses = []
        for ch, values in mandarin.items():
            if ch not in lexicon_readings:
                continue
            bopomofo = to_bopomofo(values[0])
            if bopomofo is None:
                unconverted += 1
                continue
            checked += 1
            if absolute_order_string(bopomofo) in lexicon_readings[ch]:
                matched += 1
            elif len(misses) < 25:
                misses.append(f"{ch} {values[0]} -> {bopomofo}")
        print(f"checked {checked}, matched {matched} "
              f"({matched * 100 / max(checked, 1):.1f}%), "
              f"not one syllable {unconverted}")
        print("\n".join(misses))
        return

    table = {}
    skipped = []
    for ch, values in sorted(mandarin.items(), key=lambda item: ord(item[0])):
        if not is_rare(ch) or ch in known:
            continue
        for value in values:
            bopomofo = to_bopomofo(value)
            if bopomofo is None:
                skipped.append(f"{ch} {value}")
                continue
            if ch not in table.setdefault(bopomofo, []):
                table[bopomofo].append(ch)

    characters = {ch for chars in table.values() for ch in chars}
    with open(args.output, "w", encoding="utf-8") as out:
        out.write("# Rare characters (CJK Extension B on) by reading, for those the\n")
        out.write("# lexicon lacks. Generated by Scripts/generate-rare-readings.py from\n")
        out.write("# Unihan kMandarin, (c) 1991-2025 Unicode, Inc., under the Unicode\n")
        out.write("# License v3: https://www.unicode.org/license.txt\n")
        out.write("# Format: <bopomofo>\\t<character> <character> ...\n")
        for bopomofo in sorted(table):
            out.write(f"{bopomofo}\t{' '.join(table[bopomofo])}\n")
    print(f"{len(characters)} characters under {len(table)} readings -> "
          f"{args.output}", file=sys.stderr)
    if skipped:
        print(f"skipped {len(skipped)} readings that are not one syllable: "
              f"{', '.join(skipped[:10])}", file=sys.stderr)


if __name__ == "__main__":
    main()
