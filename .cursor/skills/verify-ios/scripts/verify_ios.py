#!/usr/bin/env python3
"""Drive the Sidekick Mechanic iOS app on the owner's Mac.

On Linux this records the unmet Xcode precondition and exits 2. It does not
claim the UI was verified.

    python3 .cursor/skills/verify-ios/scripts/verify_ios.py run
"""

from __future__ import annotations

import argparse
import json
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[4]
SKILL = Path(__file__).resolve().parents[1]
PROJECT = REPO / "app" / "SidekickMechanic.xcodeproj"
UI_TEST = SKILL / "ui-tests" / "ChatSendUITests.swift"
EVIDENCE = SKILL / "evidence" / "latest"
RUN_DIR = SKILL / "run"
STATE_PATH = RUN_DIR / "state.json"
POINTER = Path("/tmp/sidekick-verify-ios/evidence-path")
SCHEME = "SidekickMechanic"
TEST_CLASS = "SidekickMechanicUITests/ChatSendUITests"
SHOTS = {
    "chat": ("chat-composer.png", "chat-answer.png"),
    "answer-card": ("answer-card.png", "answer-card-refusal.png"),
    "mock-mode": ("mock-highlight.png",),
}
METHODS = {
    "chat": "testChatSendShowsPlainFixture",
    "answer-card": "testAnswerCardShowsCitationChip",
    "mock-mode": "testMockModeShowsHighlightSlot",
    "refusal": "testAnswerCardShowsRefusal",
}


class OwnerOnly(RuntimeError):
    def __init__(self, reasons: list[str], attempted: list[list[str]]) -> None:
        super().__init__("; ".join(reasons))
        self.reasons = reasons
        self.attempted = attempted


class VerificationError(RuntimeError):
    pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify the Sidekick iOS app.")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser(
        "run", help="Boot a simulator, run the UI test class, save screenshots."
    )
    sub.add_parser(
        "doctor", help="Check Xcode, the project, and the simulator toolchain."
    )
    drive = sub.add_parser("drive", help="Run one UI test method.")
    drive.add_argument("feature", choices=tuple(METHODS))
    sub.add_parser("cleanup", help="Shut down a simulator this skill booted.")
    args = parser.parse_args(argv)
    try:
        if args.command == "run":
            command_run()
        elif args.command == "doctor":
            command_doctor()
        elif args.command == "drive":
            command_drive(args.feature)
        elif args.command == "cleanup":
            command_cleanup()
    except OwnerOnly as exc:
        write_owner_only(exc)
        print(f"verify-ios: owner-only. {exc}", file=sys.stderr)
        return 2
    except VerificationError as exc:
        print(f"verify-ios: {exc}", file=sys.stderr)
        return 1
    return 0


def command_run() -> None:
    prepare_evidence()
    try:
        doctor()
        udid, booted_by_us = boot_simulator()
        save_state(udid, booted_by_us)
        run_tests(None)
        missing = [
            name
            for names in SHOTS.values()
            for name in names
            if not (EVIDENCE / name).is_file()
        ]
        if missing:
            raise VerificationError(f"UI test finished without screenshots: {missing}")
    finally:
        command_cleanup()
    missing_after = [
        name
        for names in SHOTS.values()
        for name in names
        if not (EVIDENCE / name).is_file()
    ]
    if missing_after:
        raise VerificationError(f"cleanup removed screenshots: {missing_after}")
    print(f"verify-ios: evidence kept at {EVIDENCE}")


def command_doctor() -> None:
    report = doctor()
    write_json(EVIDENCE / "doctor.json", report)
    print(json.dumps(report, indent=2))


def command_drive(feature: str) -> None:
    prepare_evidence()
    try:
        doctor()
        udid, booted_by_us = boot_simulator()
        save_state(udid, booted_by_us)
        run_tests(METHODS[feature])
        for name in shots_for(feature):
            if not (EVIDENCE / name).is_file():
                raise VerificationError(f"missing screenshot {name}")
    finally:
        command_cleanup()


def command_cleanup() -> None:
    state = load_state()
    if state is not None and state.get("booted_by_us") and shutil.which("xcrun"):
        subprocess.run(
            ["xcrun", "simctl", "shutdown", state["udid"]],
            check=False,
            capture_output=True,
            text=True,
        )
    if STATE_PATH.exists():
        STATE_PATH.unlink()
    if POINTER.exists():
        POINTER.unlink()


def doctor() -> dict[str, Any]:
    reasons: list[str] = []
    attempted: list[list[str]] = []
    if platform.system() != "Darwin":
        reasons.append(f"platform is {platform.system()}, not Darwin")
    xcodebuild = shutil.which("xcodebuild")
    xcrun = shutil.which("xcrun")
    if xcodebuild is None:
        reasons.append("xcodebuild is not installed")
        attempted.append(["xcodebuild", "-version"])
    if xcrun is None:
        reasons.append("xcrun simctl is not installed")
        attempted.append(["xcrun", "simctl", "list", "devices", "available"])
    if not PROJECT.is_dir():
        reasons.append(
            "app/SidekickMechanic.xcodeproj does not exist. "
            "The owner creates that project and points its root view at ChatScreen."
        )
    if not UI_TEST.is_file():
        reasons.append(f"missing UI test source {UI_TEST}")
    if reasons:
        raise OwnerOnly(reasons, attempted)
    assert xcodebuild is not None
    assert xcrun is not None
    version = run_command([xcodebuild, "-version"])
    listing = run_command(["xcodebuild", "-list", "-project", str(PROJECT)])
    if f"    {SCHEME}" not in listing.stdout and SCHEME not in listing.stdout.split():
        raise OwnerOnly(
            [f"xcodebuild -list does not show scheme {SCHEME}"],
            [["xcodebuild", "-list", "-project", str(PROJECT)]],
        )
    return {
        "ok": True,
        "xcodebuild": version.stdout.strip(),
        "project": str(PROJECT.relative_to(REPO)),
        "scheme": SCHEME,
        "ui_test": str(UI_TEST.relative_to(REPO)),
    }


def boot_simulator() -> tuple[str, bool]:
    listing = run_command(["xcrun", "simctl", "list", "devices", "available", "-j"])
    try:
        payload = json.loads(listing.stdout)
    except json.JSONDecodeError as exc:
        raise VerificationError("simctl list did not return JSON") from exc
    device = pick_iphone(payload)
    udid = str(device["udid"])
    state = str(device.get("state", ""))
    booted_by_us = state != "Booted"
    if booted_by_us:
        run_command(["xcrun", "simctl", "boot", udid])
        run_command(["xcrun", "simctl", "bootstatus", udid, "-b"])
    return udid, booted_by_us


def pick_iphone(payload: dict[str, Any]) -> dict[str, Any]:
    devices = payload.get("devices")
    if not isinstance(devices, dict):
        raise VerificationError("simctl JSON has no devices object")
    candidates: list[dict[str, Any]] = []
    for runtime, entries in devices.items():
        if "iOS" not in str(runtime) or not isinstance(entries, list):
            continue
        for device in entries:
            if not isinstance(device, dict):
                continue
            if device.get("isAvailable") is False:
                continue
            name = str(device.get("name", ""))
            if "iPhone" in name and device.get("udid"):
                candidates.append(device)
    if not candidates:
        raise OwnerOnly(
            ["no available iPhone simulator"],
            [["xcrun", "simctl", "list", "devices", "available"]],
        )

    def rank(device: dict[str, Any]) -> tuple[int, str]:
        name = str(device.get("name", ""))
        if name.startswith("iPhone 16"):
            return (0, name)
        return (1, name)

    return min(candidates, key=rank)


def run_tests(method: str | None) -> None:
    only = TEST_CLASS if method is None else f"{TEST_CLASS}/{method}"
    POINTER.parent.mkdir(parents=True, exist_ok=True)
    POINTER.write_text(str(EVIDENCE.resolve()) + "\n", encoding="utf-8")
    result_bundle = EVIDENCE / "ChatSendUITests.xcresult"
    if result_bundle.exists():
        shutil.rmtree(result_bundle)
    state = load_state()
    if state is None:
        raise VerificationError("no simulator is recorded")
    command = [
        "xcodebuild",
        "test",
        "-project",
        str(PROJECT),
        "-scheme",
        SCHEME,
        "-destination",
        f"platform=iOS Simulator,id={state['udid']}",
        "-only-testing:" + only,
        "-resultBundlePath",
        str(result_bundle),
    ]
    proc = subprocess.run(
        command, cwd=REPO, capture_output=True, text=True, check=False
    )
    (EVIDENCE / "xcodebuild.txt").write_text(
        proc.stdout + proc.stderr, encoding="utf-8"
    )
    if proc.returncode != 0:
        raise VerificationError(
            "xcodebuild test failed. See evidence/latest/xcodebuild.txt"
        )


def shots_for(feature: str) -> tuple[str, ...]:
    if feature == "refusal":
        return ("answer-card-refusal.png",)
    return SHOTS[feature]


def prepare_evidence() -> None:
    if EVIDENCE.exists():
        shutil.rmtree(EVIDENCE)
    EVIDENCE.mkdir(parents=True)


def write_owner_only(exc: OwnerOnly) -> None:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    write_json(
        EVIDENCE / "owner-only.json",
        {
            "feature_id": "chat",
            "entry_point": "xcodebuild test",
            "result": "owner-only",
            "platform": platform.system().lower(),
            "unmet_preconditions": exc.reasons,
            "attempted": exc.attempted,
            "owner_command": "python3 .cursor/skills/verify-ios/scripts/verify_ios.py run",
            "ui_test_source": str(UI_TEST.relative_to(REPO)),
            "expected_screenshots": [
                name for names in SHOTS.values() for name in names
            ],
        },
    )


def save_state(udid: str, booted_by_us: bool) -> None:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    write_json(STATE_PATH, {"udid": udid, "booted_by_us": booted_by_us})


def load_state() -> dict[str, Any] | None:
    if not STATE_PATH.is_file():
        return None
    payload = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise VerificationError("simulator state file is not an object")
    return payload


def run_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    try:
        proc = subprocess.run(
            command, cwd=REPO, capture_output=True, text=True, check=False
        )
    except FileNotFoundError as exc:
        raise OwnerOnly([str(exc)], [command]) from exc
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip()
        raise VerificationError(f"{' '.join(command)} failed: {detail}")
    return proc


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
