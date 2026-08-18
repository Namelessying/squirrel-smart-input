#!/usr/bin/env python3
"""从雾凇公开基础词库生成键位颠倒纠错表，不读取任何用户词典。"""

import argparse
from pathlib import Path


INITIALS = ("zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l",
            "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w")
FINALS = set("a o e ai ei ao ou an en ang eng er i ia ie iao iu ian in iang ing iong "
             "u ua uo uai ui uan un uang ong v ve van vn".split())


def is_syllable(code: str) -> bool:
    return code in FINALS or any(code.startswith(i) and code[len(i):] in FINALS for i in INITIALS)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("rime_ice", type=Path, help="雾凇拼音源码目录")
    parser.add_argument("output", type=Path, nargs="?", default=Path.cwd())
    args = parser.parse_args()

    sources = [args.rime_ice / "cn_dicts" / name for name in (
        "8105.dict.yaml", "base.dict.yaml", "ext.dict.yaml", "others.dict.yaml"
    )]
    entries, valid_codes = [], set()
    for source in sources:
        in_body = False
        for line in source.read_text(encoding="utf-8").splitlines():
            if line.strip() == "...":
                in_body = True
                continue
            if not in_body or not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 2:
                continue
            text, code = fields[0].strip(), fields[1].strip().lower()
            if " " in code or not code.isascii() or not code.isalpha() or not is_syllable(code):
                continue
            try:
                weight = int(float(fields[2])) if len(fields) > 2 and fields[2] else 1
            except ValueError:
                weight = 1
            entries.append((text, code, weight))
            valid_codes.add(code)

    rows = {}
    for text, code, weight in entries:
        for i in range(len(code) - 1):
            if code[i] == code[i + 1]:
                continue
            typo = code[:i] + code[i + 1] + code[i] + code[i + 2:]
            if typo in valid_codes:
                continue
            key = (text, typo)
            if key not in rows or weight > rows[key][0]:
                rows[key] = (weight, code)

    args.output.mkdir(parents=True, exist_ok=True)
    header = """# Rime dictionary
# encoding: utf-8
# Generated only from the public Rime Ice dictionaries.
---
name: typo_corrections
version: "2026-08-18"
sort: by_weight
columns:
  - text
  - code
  - weight
...
"""
    ordered = sorted(rows.items(), key=lambda item: (item[0][1], -item[1][0], item[0][0]))
    (args.output / "typo_corrections.dict.yaml").write_text(
        header + "".join(f"{text}\t{typo}\t{max(weight, 1)}\n"
                         for (text, typo), (weight, _correct) in ordered),
        encoding="utf-8",
    )
    best = {}
    for (_text, typo), (weight, correct) in rows.items():
        if typo not in best or weight > best[typo][0]:
            best[typo] = (weight, correct)
    (args.output / "typo_corrections.tsv").write_text(
        "".join(f"{typo}\t{correct}\n" for typo, (_weight, correct) in sorted(best.items())),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
