#!/usr/bin/env python3
"""Build, boot, launch, screenshot, and compare the Sidekick Mechanic iPhone app.

Mac host. Linux stops at doctor (and an optional Figma stitcher self-test).

    .cursor/skills/verify-sidekick/scripts/verify-ios.sh doctor
    .cursor/skills/verify-sidekick/scripts/verify-ios.sh run
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[4]
SKILL = Path(__file__).resolve().parents[1]
COMPARE = Path(__file__).resolve().parent / "compare_figma.py"
PROJECT = REPO / "app" / "SidekickMechanic.xcodeproj"
ONBOARDING_FILE = REPO / "app" / "SidekickMechanic" / "OnboardingFlow.swift"
RUN_DIR = SKILL / "run"
STATE_PATH = RUN_DIR / "state.json"
POINTER = Path("/tmp/sidekick-verify-sidekick/evidence-path")
BUNDLE_ID = "com.zeketx.SidekickMechanic"
SCHEME = "SidekickMechanic"
UI_TEST_CLASS = "SidekickMechanicUITests/DriveUITests"
BACKEND_URL = "http://127.0.0.1:8000"
PREFERRED_DEVICE = "iPhone 17 Pro"
PREFERRED_XCODE = "26.0.1"
PREFERRED_IOS = "26.0"


@dataclass(frozen=True)
class ScreenSpec:
    args: tuple[str, ...]
    figma: str
    requires_onboarding: bool = False
    wait_s: float = 3.0


SCREENS: dict[str, ScreenSpec] = {
    "chat": ScreenSpec(
        args=("-sidekick.onboarding.completed", "YES"),
        figma="chat.png",
        wait_s=2.5,
    ),
    "onboarding-1": ScreenSpec(
        args=("-resetOnboarding", "-screen", "onboarding-1"),
        figma="onboarding-1.png",
        requires_onboarding=True,
    ),
    "onboarding-2": ScreenSpec(
        args=("-resetOnboarding", "-screen", "onboarding-2"),
        figma="onboarding-2.png",
        requires_onboarding=True,
    ),
    "onboarding-3": ScreenSpec(
        args=("-resetOnboarding", "-screen", "onboarding-3"),
        figma="onboarding-3.png",
        requires_onboarding=True,
    ),
    "highlight-confident": ScreenSpec(
        args=("-screen", "highlight-confident", "-demoPhoto", "hilux"),
        figma="highlight-confident.png",
        wait_s=4.0,
    ),
    "highlight-unsure": ScreenSpec(
        args=("-screen", "highlight-unsure", "-demoPhoto", "hilux"),
        figma="highlight-unsure.png",
        wait_s=4.0,
    ),
    "highlight-not-found": ScreenSpec(
        args=("-screen", "highlight-not-found", "-demoPhoto", "hilux"),
        figma="highlight-not-found.png",
        wait_s=4.0,
    ),
    "highlight-reference": ScreenSpec(
        args=("-screen", "highlight-reference", "-demoPhoto", "hilux"),
        figma="highlight-reference.png",
        wait_s=4.0,
    ),
    "job-sheet-collapsed": ScreenSpec(
        args=("-screen", "job-sheet-collapsed", "-demoPhoto", "hilux"),
        figma="job-sheet-collapsed.png",
        wait_s=4.0,
    ),
    "job-sheet-half": ScreenSpec(
        args=("-screen", "job-sheet-half", "-demoPhoto", "hilux"),
        figma="job-sheet-half.png",
        wait_s=4.0,
    ),
    "job-sheet-full": ScreenSpec(
        args=("-screen", "job-sheet-full", "-demoPhoto", "hilux"),
        figma="job-sheet-full.png",
        wait_s=4.0,
    ),
    "job-sheet-closeout": ScreenSpec(
        args=("-screen", "job-sheet-closeout", "-demoPhoto", "hilux"),
        figma="job-sheet-closeout.png",
        wait_s=4.0,
    ),
    "job-history": ScreenSpec(
        args=("-screen", "job-history"),
        figma="job-history.png",
        wait_s=3.5,
    ),
    "scan-log": ScreenSpec(
        args=("-screen", "scan-log"),
        figma="scan-log.png",
        wait_s=3.5,
    ),
}

DEFAULT_SCREENS = (
    "chat",
    "highlight-confident",
    "highlight-unsure",
    "highlight-not-found",
    "highlight-reference",
    "job-sheet-collapsed",
    "job-sheet-half",
    "job-sheet-full",
    "job-sheet-closeout",
    "job-history",
    "scan-log",
)


class OwnerOnly(RuntimeError):
    def __init__(self, reasons: list[str], attempted: list[list[str]]) -> None:
        super().__init__("; ".join(reasons))
        self.reasons = reasons
        self.attempted = attempted


class VerificationError(RuntimeError):
    pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify the Sidekick iPhone UI.")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("doctor", help="Read-only: Xcode, sim, app, backend :8000, git SHA.")
    run = sub.add_parser("run", help="Doctor, launch, screenshot, taps, compare, cleanup.")
    add_run_flags(run)
    screens = sub.add_parser("screens", help="Build, boot, launch each -screen, screenshot.")
    add_run_flags(screens)
    taps = sub.add_parser("taps", help="Run DriveUITests (Jobs row, sheet drag, scrim).")
    add_run_flags(taps)
    compare = sub.add_parser("compare", help="Stitch screenshots next to Figma refs.")
    compare.add_argument("--run-id")
    compare.add_argument("--self-test", action="store_true")
    sub.add_parser("cleanup", help="Stop only what this run started. Keeps artifacts.")
    args = parser.parse_args(argv)
    try:
        if args.command == "doctor":
            return command_doctor()
        if args.command == "run":
            return command_run(args)
        if args.command == "screens":
            return command_screens(args)
        if args.command == "taps":
            return command_taps(args)
        if args.command == "compare":
            return command_compare(args)
        if args.command == "cleanup":
            command_cleanup()
            return 0
    except OwnerOnly as exc:
        evidence = prepare_evidence(getattr(args, "run_id", None))
        write_owner_only(exc, evidence)
        print(f"verify-sidekick: owner-only. {exc}", file=sys.stderr)
        return 2
    except VerificationError as exc:
        print(f"verify-sidekick: {exc}", file=sys.stderr)
        return 1
    return 0


def add_run_flags(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--run-id")
    parser.add_argument(
        "--screens",
        help="Comma-separated screen ids. Default: v1 UI stack (no onboarding).",
    )
    parser.add_argument("--skip-taps", action="store_true")
    parser.add_argument("--skip-compare", action="store_true")
    parser.add_argument("--skip-backend", action="store_true")


def command_doctor() -> int:
    evidence = prepare_evidence(None)
    report = doctor(evidence)
    write_json(evidence / "doctor.json", report)
    print(json.dumps(report, indent=2))
    return 0 if report.get("ok") else 1


def command_run(args: argparse.Namespace) -> int:
    evidence = prepare_evidence(args.run_id)
    try:
        if platform.system() != "Darwin":
            linux_partial(evidence)
            return 2
        doctor(evidence)
        ensure_backend(args.skip_backend)
        udid, booted_by_us = boot_simulator()
        save_state(
            udid=udid,
            booted_by_us=booted_by_us,
            evidence=str(evidence),
            status_bar=True,
        )
        build_and_install(udid, evidence)
        override_status_bar(udid)
        doctor(evidence)
        capture_screens(udid, selected_screens(args.screens), evidence)
        if not args.skip_taps:
            run_ui_tests(udid, evidence)
        if not args.skip_compare:
            run_compare(evidence)
        write_manifest(evidence, "run")
    finally:
        command_cleanup()
    if not (evidence / "doctor.json").is_file() and not (evidence / "owner-only.json").is_file():
        raise VerificationError("cleanup removed evidence")
    print(f"verify-sidekick: evidence kept at {evidence}")
    return 0


def command_screens(args: argparse.Namespace) -> int:
    evidence = prepare_evidence(args.run_id)
    doctor(evidence)
    ensure_backend(args.skip_backend)
    udid, booted_by_us = boot_simulator()
    save_state(
        udid=udid,
        booted_by_us=booted_by_us,
        evidence=str(evidence),
        status_bar=True,
    )
    build_and_install(udid, evidence)
    override_status_bar(udid)
    capture_screens(udid, selected_screens(args.screens), evidence)
    write_manifest(evidence, "screens")
    print(f"verify-sidekick: screenshots at {evidence / 'screenshots'}")
    return 0


def command_taps(args: argparse.Namespace) -> int:
    evidence = prepare_evidence(args.run_id)
    doctor(evidence)
    udid, booted_by_us = boot_simulator()
    save_state(
        udid=udid,
        booted_by_us=booted_by_us,
        evidence=str(evidence),
        status_bar=True,
    )
    override_status_bar(udid)
    run_ui_tests(udid, evidence)
    write_manifest(evidence, "taps")
    return 0


def command_compare(args: argparse.Namespace) -> int:
    if args.self_test:
        dest = prepare_evidence(args.run_id or "self-test")
        proc = subprocess.run(
            [sys.executable, str(COMPARE), "--self-test", "--run-dir", str(dest)],
            cwd=REPO,
            check=False,
        )
        return proc.returncode
    evidence = evidence_dir(args.run_id)
    return run_compare(evidence)


def linux_partial(evidence: Path) -> None:
    """Doctor plus stitcher self-test. Not a live UI proof."""
    try:
        report = doctor(evidence)
    except OwnerOnly as exc:
        write_owner_only(exc, evidence)
        report = None
    else:
        write_json(evidence / "doctor.json", report)
    subprocess.run(
        [sys.executable, str(COMPARE), "--self-test", "--run-dir", str(evidence)],
        cwd=REPO,
        check=False,
    )
    write_manifest(evidence, "linux-partial")
    print(f"verify-sidekick: Linux partial evidence at {evidence}", file=sys.stderr)


def doctor(evidence: Path | None = None) -> dict[str, Any]:
    reasons: list[str] = []
    attempted: list[list[str]] = []
    git = git_identity()
    backend = probe_backend()
    report: dict[str, Any] = {
        "ok": False,
        "platform": platform.system(),
        "git": git,
        "backend": backend,
        "onboarding_in_checkout": ONBOARDING_FILE.is_file(),
        "preferred": {
            "xcode": PREFERRED_XCODE,
            "device": PREFERRED_DEVICE,
            "ios": PREFERRED_IOS,
            "bundle_id": BUNDLE_ID,
        },
    }
    if platform.system() != "Darwin":
        reasons.append(f"platform is {platform.system()}, not Darwin (no iOS Simulator)")
        attempted.append(["xcodebuild", "-version"])
    xcodebuild = shutil.which("xcodebuild")
    xcrun = shutil.which("xcrun")
    if xcodebuild is None:
        reasons.append("xcodebuild is not installed")
        attempted.append(["xcodebuild", "-version"])
    if xcrun is None:
        reasons.append("xcrun simctl is not installed")
        attempted.append(["xcrun", "simctl", "list", "devices", "available"])
    if not PROJECT.is_dir():
        reasons.append("app/SidekickMechanic.xcodeproj is missing")
    if reasons:
        raise OwnerOnly(reasons, attempted)

    assert xcodebuild is not None
    version = run_command([xcodebuild, "-version"])
    listing = run_command([xcodebuild, "-list", "-project", str(PROJECT)])
    if SCHEME not in listing.stdout:
        raise OwnerOnly(
            [f"xcodebuild -list does not show scheme {SCHEME}"],
            [["xcodebuild", "-list", "-project", str(PROJECT)]],
        )
    report["xcodebuild"] = version.stdout.strip()
    if PREFERRED_XCODE.split(".")[0] not in version.stdout:
        report["xcode_note"] = (
            f"preferred Xcode {PREFERRED_XCODE}; this machine reports:\n{version.stdout.strip()}"
        )

    sim = simulator_report()
    report["simulator"] = sim
    installed = False
    if sim.get("udid") and sim.get("state") == "Booted":
        installed = app_installed(str(sim["udid"]))
    report["app_installed"] = installed
    report["ok"] = (
        backend.get("openapi") is True
        and sim.get("state") == "Booted"
        and installed
    )
    if evidence is not None:
        write_json(evidence / "doctor.json", report)
    return report


def git_identity() -> dict[str, str]:
    branch = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=False,
    )
    sha = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=False,
    )
    return {
        "branch": branch.stdout.strip() or "unknown",
        "sha": sha.stdout.strip() or "unknown",
    }


def probe_backend() -> dict[str, Any]:
    result: dict[str, Any] = {
        "url": BACKEND_URL,
        "openapi": False,
        "demo_photos": False,
    }
    openapi = http_json(f"{BACKEND_URL}/openapi.json")
    if isinstance(openapi, dict) and openapi.get("info", {}).get("title") == "Sidekick Mechanic":
        result["openapi"] = True
        result["title"] = "Sidekick Mechanic"
    photos = http_json(f"{BACKEND_URL}/demo/photos")
    if isinstance(photos, dict) and photos.get("demo") is True:
        result["demo_photos"] = True
        result["photo_count"] = len(photos.get("photos") or [])
    elif not result["openapi"]:
        result["note"] = (
            "Nothing answered on :8000. Start from backend/: "
            "uvicorn app:app --host 127.0.0.1 --port 8000"
        )
    elif not result["demo_photos"]:
        result["note"] = (
            "GET /openapi.json is up, GET /demo/photos is not. "
            "Demo photos live on PR #92 (cursor/demo-mode-backend-27ef). "
            "Placeholders still render without it."
        )
    return result


def http_json(url: str) -> dict[str, Any] | None:
    try:
        with urllib.request.urlopen(url, timeout=2) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        return None
    return payload if isinstance(payload, dict) else None


def ensure_backend(skip: bool) -> None:
    if skip:
        return
    status = probe_backend()
    if status.get("openapi"):
        return
    if port_in_use(8000):
        raise VerificationError(
            "port 8000 is in use but is not Sidekick Mechanic (GET /openapi.json title mismatch)"
        )
    python = shutil.which("python3") or sys.executable
    log_path = Path("/tmp/sidekick-verify-sidekick/backend.log")
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log = log_path.open("w", encoding="utf-8")
    proc = subprocess.Popen(
        [python, "-m", "uvicorn", "app:app", "--host", "127.0.0.1", "--port", "8000"],
        cwd=REPO / "backend",
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        env={k: v for k, v in os.environ.items() if k != "SIDEKICK_LLM_API_KEY"},
    )
    state = load_state() or {}
    state["backend_pid"] = proc.pid
    state["backend_pgid"] = os.getpgid(proc.pid)
    save_state_payload(state)
    for _ in range(40):
        if probe_backend().get("openapi"):
            return
        if proc.poll() is not None:
            break
        time.sleep(0.25)
    raise VerificationError(
        f"uvicorn did not answer on :8000. See {log_path}"
    )


def port_in_use(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.3)
        return sock.connect_ex(("127.0.0.1", port)) == 0


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
    candidates: list[tuple[int, str, dict[str, Any]]] = []
    for runtime, entries in devices.items():
        if "iOS" not in str(runtime) or not isinstance(entries, list):
            continue
        runtime_s = str(runtime)
        for device in entries:
            if not isinstance(device, dict) or device.get("isAvailable") is False:
                continue
            name = str(device.get("name", ""))
            if "iPhone" not in name or not device.get("udid"):
                continue
            rank = 3
            if name == PREFERRED_DEVICE and PREFERRED_IOS.replace(".", "-") in runtime_s:
                rank = 0
            elif name == PREFERRED_DEVICE:
                rank = 1
            elif "iPhone 17" in name:
                rank = 2
            candidates.append((rank, name, device))
    if not candidates:
        raise OwnerOnly(
            ["no available iPhone simulator"],
            [["xcrun", "simctl", "list", "devices", "available"]],
        )
    candidates.sort(key=lambda item: (item[0], item[1]))
    return candidates[0][2]


def simulator_report() -> dict[str, Any]:
    listing = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        capture_output=True,
        text=True,
        check=False,
    )
    if listing.returncode != 0:
        return {"error": listing.stderr.strip() or listing.stdout.strip()}
    try:
        payload = json.loads(listing.stdout)
        device = pick_iphone(payload)
    except (json.JSONDecodeError, VerificationError, OwnerOnly) as exc:
        return {"error": str(exc)}
    return {
        "name": device.get("name"),
        "udid": device.get("udid"),
        "state": device.get("state"),
    }


def app_installed(udid: str) -> bool:
    proc = subprocess.run(
        ["xcrun", "simctl", "get_app_container", udid, BUNDLE_ID],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode == 0 and bool(proc.stdout.strip())


def build_and_install(udid: str, evidence: Path) -> None:
    derived = Path("/tmp/sidekick-verify-sidekick/DerivedData")
    derived.mkdir(parents=True, exist_ok=True)
    command = [
        "xcodebuild",
        "-project",
        str(PROJECT),
        "-scheme",
        SCHEME,
        "-configuration",
        "Debug",
        "-destination",
        f"platform=iOS Simulator,id={udid}",
        "-derivedDataPath",
        str(derived),
        "CODE_SIGNING_ALLOWED=NO",
        "build",
    ]
    proc = subprocess.run(command, cwd=REPO, capture_output=True, text=True, check=False)
    log = evidence / "logs"
    log.mkdir(parents=True, exist_ok=True)
    (log / "xcodebuild-build.txt").write_text(proc.stdout + proc.stderr, encoding="utf-8")
    if proc.returncode != 0:
        raise VerificationError("xcodebuild build failed. See logs/xcodebuild-build.txt")
    app = derived / "Build" / "Products" / "Debug-iphonesimulator" / "SidekickMechanic.app"
    if not app.is_dir():
        raise VerificationError(f"build finished without {app}")
    run_command(["xcrun", "simctl", "install", udid, str(app)])


def override_status_bar(udid: str) -> None:
    run_command(
        [
            "xcrun",
            "simctl",
            "status_bar",
            udid,
            "override",
            "--time",
            "9:41",
            "--dataNetwork",
            "wifi",
            "--wifiMode",
            "active",
            "--wifiBars",
            "3",
            "--cellularMode",
            "active",
            "--cellularBars",
            "4",
            "--operatorName",
            "",
            "--batteryState",
            "charged",
            "--batteryLevel",
            "100",
        ]
    )
    state = load_state() or {}
    state["status_bar"] = True
    save_state_payload(state)


def capture_screens(udid: str, names: list[str], evidence: Path) -> None:
    shots = evidence / "screenshots"
    shots.mkdir(parents=True, exist_ok=True)
    skipped: list[dict[str, str]] = []
    has_onboarding = ONBOARDING_FILE.is_file()
    for name in names:
        spec = SCREENS[name]
        if spec.requires_onboarding and not has_onboarding:
            skipped.append(
                {
                    "screen": name,
                    "reason": "OnboardingFlow.swift is not in this checkout (PR #111).",
                }
            )
            continue
        subprocess.run(
            ["xcrun", "simctl", "terminate", udid, BUNDLE_ID],
            capture_output=True,
            text=True,
            check=False,
        )
        time.sleep(0.8)
        launch = ["xcrun", "simctl", "launch", udid, BUNDLE_ID, *spec.args]
        launched = subprocess.run(launch, capture_output=True, text=True, check=False)
        if launched.returncode != 0:
            raise VerificationError(
                f"simctl launch {name} failed: {launched.stderr or launched.stdout}"
            )
        time.sleep(spec.wait_s)
        dest = shots / f"{name}.png"
        io = subprocess.run(
            ["xcrun", "simctl", "io", udid, "screenshot", str(dest)],
            capture_output=True,
            text=True,
            check=False,
        )
        if io.returncode != 0 or not dest.is_file():
            raise VerificationError(f"screenshot failed for {name}: {io.stderr or io.stdout}")
    subprocess.run(
        ["xcrun", "simctl", "terminate", udid, BUNDLE_ID],
        capture_output=True,
        text=True,
        check=False,
    )
    if skipped:
        write_json(evidence / "screenshots" / "skipped.json", {"skipped": skipped})


def run_ui_tests(udid: str, evidence: Path) -> None:
    taps = evidence / "taps"
    taps.mkdir(parents=True, exist_ok=True)
    POINTER.parent.mkdir(parents=True, exist_ok=True)
    POINTER.write_text(str(taps.resolve()) + "\n", encoding="utf-8")
    result_bundle = taps / "DriveUITests.xcresult"
    if result_bundle.exists():
        shutil.rmtree(result_bundle)
    derived = Path("/tmp/sidekick-verify-sidekick/DerivedData")
    command = [
        "xcodebuild",
        "test",
        "-project",
        str(PROJECT),
        "-scheme",
        SCHEME,
        "-destination",
        f"platform=iOS Simulator,id={udid}",
        "-derivedDataPath",
        str(derived),
        "-only-testing:" + UI_TEST_CLASS,
        "-resultBundlePath",
        str(result_bundle),
        "CODE_SIGNING_ALLOWED=NO",
    ]
    proc = subprocess.run(command, cwd=REPO, capture_output=True, text=True, check=False)
    (evidence / "logs").mkdir(parents=True, exist_ok=True)
    (evidence / "logs" / "xcodebuild-test.txt").write_text(
        proc.stdout + proc.stderr, encoding="utf-8"
    )
    if proc.returncode != 0:
        raise VerificationError(
            "xcodebuild test failed. See logs/xcodebuild-test.txt "
            "(Garage skip is XCTSkip and still exit 0)."
        )


def run_compare(evidence: Path) -> int:
    proc = subprocess.run(
        [sys.executable, str(COMPARE), "--run-dir", str(evidence)],
        cwd=REPO,
        check=False,
    )
    if proc.returncode != 0:
        raise VerificationError("compare_figma.py failed")
    return 0


def selected_screens(raw: str | None) -> list[str]:
    if not raw:
        names = list(DEFAULT_SCREENS)
    else:
        names = [item.strip() for item in raw.split(",") if item.strip()]
    unknown = [name for name in names if name not in SCREENS]
    if unknown:
        raise VerificationError(f"unknown screens: {unknown}. Known: {sorted(SCREENS)}")
    return names


def command_cleanup() -> None:
    state = load_state()
    if state is None:
        if POINTER.exists():
            POINTER.unlink()
        return
    udid = state.get("udid")
    if state.get("status_bar") and udid and shutil.which("xcrun"):
        subprocess.run(
            ["xcrun", "simctl", "status_bar", str(udid), "clear"],
            check=False,
            capture_output=True,
            text=True,
        )
    if state.get("booted_by_us") and udid and shutil.which("xcrun"):
        subprocess.run(
            ["xcrun", "simctl", "shutdown", str(udid)],
            check=False,
            capture_output=True,
            text=True,
        )
    backend_pgid = state.get("backend_pgid")
    backend_pid = state.get("backend_pid")
    if isinstance(backend_pgid, int):
        kill_group(backend_pgid)
    elif isinstance(backend_pid, int):
        kill_pid(backend_pid)
    if STATE_PATH.exists():
        STATE_PATH.unlink()
    if POINTER.exists():
        POINTER.unlink()


def kill_group(pgid: int) -> None:
    try:
        os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(20):
        try:
            os.killpg(pgid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.1)
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        return


def kill_pid(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return


def prepare_evidence(run_id: str | None) -> Path:
    run_id = run_id or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    evidence = REPO / "artifacts" / "verify" / run_id
    evidence.mkdir(parents=True, exist_ok=True)
    (evidence / "logs").mkdir(exist_ok=True)
    latest = REPO / "artifacts" / "verify" / "latest"
    if latest.is_symlink() or latest.is_file():
        latest.unlink()
    elif latest.is_dir():
        shutil.rmtree(latest)
    try:
        latest.symlink_to(run_id, target_is_directory=True)
    except OSError:
        pass
    return evidence


def evidence_dir(run_id: str | None) -> Path:
    if run_id:
        path = REPO / "artifacts" / "verify" / run_id
    else:
        path = REPO / "artifacts" / "verify" / "latest"
        if path.is_symlink():
            path = path.resolve()
    if not path.exists():
        raise VerificationError(f"no evidence directory at {path}")
    return path


def write_owner_only(exc: OwnerOnly, evidence: Path) -> None:
    write_json(
        evidence / "owner-only.json",
        {
            "feature_id": "chat",
            "entry_point": "verify-ios.sh doctor",
            "result": "owner-only",
            "platform": platform.system().lower(),
            "unmet_preconditions": exc.reasons,
            "attempted": exc.attempted,
            "git": git_identity(),
            "backend": probe_backend(),
            "owner_command": (
                ".cursor/skills/verify-sidekick/scripts/verify-ios.sh doctor && "
                ".cursor/skills/verify-sidekick/scripts/verify-ios.sh run"
            ),
            "not_a_pass": True,
        },
    )


def write_manifest(evidence: Path, command: str) -> None:
    shots = []
    shot_dir = evidence / "screenshots"
    if shot_dir.is_dir():
        shots = sorted(path.name for path in shot_dir.glob("*.png"))
    write_json(
        evidence / "manifest.json",
        {
            "command": command,
            "git": git_identity(),
            "screenshots": shots,
            "evidence": str(evidence.relative_to(REPO)),
        },
    )


def save_state(
    udid: str,
    booted_by_us: bool,
    evidence: str,
    status_bar: bool,
) -> None:
    payload = load_state() or {}
    payload.update(
        {
            "udid": udid,
            "booted_by_us": booted_by_us,
            "evidence": evidence,
            "status_bar": status_bar,
        }
    )
    save_state_payload(payload)


def save_state_payload(payload: dict[str, Any]) -> None:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    write_json(STATE_PATH, payload)


def load_state() -> dict[str, Any] | None:
    if not STATE_PATH.is_file():
        return None
    payload = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise VerificationError("state file is not an object")
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
