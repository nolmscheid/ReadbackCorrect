#!/usr/bin/env python3
"""
Build victor_airways.json for ReadBack.
Output: out/victor_airways.json — array of Victor airway numbers as strings, e.g. ["1","2",...,"500"].
"""
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent / "out"
OUT_FILE = OUT_DIR / "victor_airways.json"

# Victor airways in the US are typically V1 through V500+; the app uses these for validation.
VICTOR_NUMBERS = list(range(1, 501))


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    data = [str(n) for n in VICTOR_NUMBERS]
    with open(OUT_FILE, "w", encoding="utf-8") as f:
        import json
        json.dump(data, f, indent=0)
    print(f"Wrote {len(data)} Victor airway numbers to {OUT_FILE}")


if __name__ == "__main__":
    main()
