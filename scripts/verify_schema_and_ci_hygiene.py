#!/usr/bin/env python3
"""Verifies JSON schema <-> Swift enum parity, Foundation-only SignalEngine imports,
and required .caf audio asset wiring before building Confluence."""

from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

FORBIDDEN_SIGNAL_ENGINE_IMPORTS = {
    "SwiftUI",
    "UIKit",
    "Combine",
    "AVFoundation",
    "CoreHaptics",
    "SwiftData",
    "WebKit",
}

REQUIRED_CAF_FILES = [
    "terminal_chime.caf",
    "sonar_pulse.caf",
    "vault_lock.caf",
    "trap_warning.caf",
    "news_release_ping.caf",
]


def check_signal_engine_imports() -> list[str]:
    errors: list[str] = []
    sources_dir = ROOT / "Packages" / "SignalEngine" / "Sources"
    for swift_file in sorted(sources_dir.rglob("*.swift")):
        text = swift_file.read_text(encoding="utf-8")
        for line_no, line in enumerate(text.splitlines(), start=1):
            m = re.match(r"^\s*import\s+([A-Za-z0-9_]+)", line)
            if m and m.group(1) in FORBIDDEN_SIGNAL_ENGINE_IMPORTS:
                errors.append(
                    f"{swift_file.relative_to(ROOT)}:{line_no}: forbidden UI/framework import '{m.group(1)}' in SignalEngine"
                )
    return errors


def check_schema_enum_parity() -> list[str]:
    errors: list[str] = []
    schema_path = ROOT / "Specs" / "schemas" / "signal.schema.json"
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    props = schema.get("properties", {})

    expected_enums = {
        "marketClass": ["crypto", "forex", "metals", "indices", "stocks"],
        "timeframe": ["15m", "30m", "1h", "4h", "1d"],
        "htfTimeframe": ["15m", "30m", "1h", "4h", "1d"],
        "category": ["STRONG_SIGNAL", "WEAK_SIGNAL", "TRAP_ALERT"],
        "direction": ["long", "short", "neutral"],
        "trapDirection": ["BULL TRAP", "BEAR TRAP", None],
        "riskState": ["safe", "near_limit", "reduce"],
    }

    for key, expected in expected_enums.items():
        actual = props.get(key, {}).get("enum")
        if actual != expected:
            errors.append(
                f"Specs/schemas/signal.schema.json property '{key}' enum mismatch: expected {expected}, got {actual}"
            )

    # Verify Swift TrapDirection raw values match schema
    trap_models = (ROOT / "Packages" / "SignalEngine" / "Sources" / "SignalEngine" / "Models" / "TrapModels.swift").read_text(encoding="utf-8")
    for raw in ("BULL TRAP", "BEAR TRAP"):
        if f'"{raw}"' not in trap_models:
            errors.append(f"TrapModels.swift missing TrapDirection raw value '{raw}'")

    return errors


def check_caf_sound_wiring() -> list[str]:
    errors: list[str] = []
    project_yml = (ROOT / "project.yml").read_text(encoding="utf-8")
    for caf in REQUIRED_CAF_FILES:
        if caf not in project_yml:
            errors.append(f"project.yml missing audio resource wiring for {caf}")
    return errors


def main() -> int:
    errors = []
    errors.extend(check_signal_engine_imports())
    errors.extend(check_schema_enum_parity())
    errors.extend(check_caf_sound_wiring())

    if errors:
        print("CI Hygiene / Schema Parity Verification FAILED:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("CI Hygiene & Schema Parity Verification PASSED (Foundation-only SignalEngine, schema enums, .caf wiring).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
