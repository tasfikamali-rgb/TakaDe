#!/usr/bin/env python3
"""Builds Packages/TakaDeKit/Sources/TakaDeCore/Resources/emoji-keywords.tsv.

The word -> emoji list behind group icons (docs/adr/0026-group-icons-from-names.md), from
Unicode CLDR emoji annotations: the same names and keywords the emoji keyboard searches,
in English and Bengali. Each line is "keyword<TAB>emoji". It ships with the app (no
lookups at runtime). The hand-picked list in GroupIcon.swift is checked first.

Usage: python3 scripts/update-emoji-keywords.py [path/to/cldr-annotations-full/package path/to/cldr-annotations-derived-full/package]
Without paths it downloads both packages (pinned version) from the npm registry.
"""
from __future__ import annotations

import io
import json
import sys
import tarfile
import unicodedata
import urllib.request
from pathlib import Path

VERSION = "49.0.0"
OUT = Path(__file__).resolve().parents[1] / "Packages/TakaDeKit/Sources/TakaDeCore/Resources/emoji-keywords.tsv"
LANGS = ["en", "bn"]

# Words that say nothing about what a group is for, or would give an odd icon.
STOP = set("""
and the of for with without from into onto over under in on at to by or not no yes my our your their his her its
face person people man men woman women boy girl child adult baby hand hands sign symbol mark button new old big small
light dark medium red blue green yellow orange purple brown black white pink grey gray tone skin hair other
up down left right top end back front side open closed off one two three four five six seven eight nine ten
good bad happy sad love heart smile smiling laugh cry joy fun funny cool nice ok okay thing things stuff misc group groups
day night time week month year today money cash pay paid
""".split())


NOT_FLAGS = {"jersey", "turkey", "chad", "jordan", "georgia", "guernsey", "niger", "china", "dominica", "isle of man", "man"}


def fetch(package: str) -> tarfile.TarFile:
    meta = json.load(urllib.request.urlopen(f"https://registry.npmjs.org/{package}/{VERSION}"))
    data = urllib.request.urlopen(meta["dist"]["tarball"]).read()
    return tarfile.open(fileobj=io.BytesIO(data))


def load(source, inner: str, key: str) -> dict:
    if isinstance(source, Path):
        return json.loads((source / inner).read_text(encoding="utf-8"))[key]["annotations"]
    return json.load(source.extractfile("package/" + inner))[key]["annotations"]


def skip_emoji(emoji: str) -> bool:
    cps = [ord(c) for c in emoji]
    if any(0x1F3FB <= c <= 0x1F3FF for c in cps):  # skin tones
        return True
    if any(0x1F9B0 <= c <= 0x1F9B3 for c in cps):  # hair components
        return True
    if 0x20E3 in cps:  # keycaps
        return True
    return all(c < 0x2000 for c in cps)  # ©, ®, digits


def is_flag(emoji: str) -> bool:
    cps = [ord(c) for c in emoji]
    return len(cps) == 2 and all(0x1F1E6 <= c <= 0x1F1FF for c in cps)


def norm(text: str) -> str:
    return unicodedata.normalize("NFC", text.strip().lower())


def usable(word: str) -> bool:
    if not word or word in STOP:
        return False
    if word.isascii():
        return len(word) >= 3 and all(ch.isalpha() or ch in " '-" for ch in word)
    return len(word) >= 2


def main() -> None:
    if len(sys.argv) == 3:
        full, derived = Path(sys.argv[1]), Path(sys.argv[2])
    else:
        full, derived = fetch("cldr-annotations-full"), fetch("cldr-annotations-derived-full")

    best: dict[str, tuple[tuple, str]] = {}

    def offer(word: str, emoji: str, rank: tuple) -> None:
        word = norm(word).replace("-", " ").replace("’", "'")
        if not usable(word):
            return
        if word not in best or rank < best[word][0]:
            best[word] = (rank, emoji)

    for lang in LANGS:
        base = load(full, f"annotations/{lang}/annotations.json", "annotations")
        for emoji, entry in base.items():
            if skip_emoji(emoji):
                continue
            keywords = entry.get("default", [])
            names = [norm(name) for name in entry.get("tts", [])]
            # Best first: the emoji's own name ("pizza"), then a word in its name ("beer" in
            # "beer mug"), then one of its keywords. Ties go to the shorter name, then to the
            # emoji with fewer keywords (more specific).
            words_in_name = min((len(name.split()) for name in names), default=9)
            for name in names:
                offer(name, emoji, (0, 0, len(keywords), len(emoji)))
            for word in keywords:
                inside = any(norm(word) in name.split() for name in names)
                offer(word, emoji, (1 if inside else 2, words_in_name, len(keywords), len(emoji)))
        # Flags: "flag: Japan" -> "japan" -> 🇯🇵. Country names only, so "flag" alone isn't one.
        flags = load(derived, f"annotationsDerived/{lang}/annotations.json", "annotationsDerived")
        for emoji, entry in flags.items():
            if not is_flag(emoji):
                continue
            for name in entry.get("tts", []):
                country = norm(name.split(":", 1)[-1])
                # Country names that are also everyday words or first names.
                if country in NOT_FLAGS:
                    continue
                offer(country, emoji, (-1, 0, 0, 0))

    # Kept as CLDR writes them; the app adds the colour-emoji selector where needed.
    lines = [f"{word}\t{emoji}" for word, (_, emoji) in sorted(best.items())]
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(lines)} keywords, {OUT.stat().st_size // 1024} KB -> {OUT}")


if __name__ == "__main__":
    main()
