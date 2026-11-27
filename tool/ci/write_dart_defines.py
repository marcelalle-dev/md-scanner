"""Writes the --dart-define-from-file JSON used by CI builds.

Only variables that are actually set are written, so that a missing repository
variable keeps the in-code default (Google test ad units, AI assistant off)
instead of overriding it with an empty string.

Usage: python3 tool/ci/write_dart_defines.py <output.json>
"""

import json
import os
import sys

KEYS = (
    "AI_BACKEND_URL",
    "PURCHASE_VERIFICATION_URL",
    "ADMOB_BANNER_UNIT_ID",
    "ADMOB_INTERSTITIAL_UNIT_ID",
    "ADMOB_REWARDED_UNIT_ID",
)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 64
    defines = {key: os.environ[key] for key in KEYS if os.environ.get(key)}
    with open(sys.argv[1], "w", encoding="utf-8") as output:
        json.dump(defines, output, indent=2, sort_keys=True)
    print(f"dart defines written: {', '.join(sorted(defines)) or 'none (defaults)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
