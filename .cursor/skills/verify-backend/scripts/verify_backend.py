#!/usr/bin/env python3
"""Drive the Sidekick Mechanic backend and save proof under evidence/latest.

From the repo root, with backend dependencies installed for this interpreter:

    python3 .cursor/skills/verify-backend/scripts/verify_backend.py run
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from jsonschema.exceptions import ValidationError

REPO = Path(__file__).resolve().parents[4]
BACKEND = REPO / "backend"
sys.path.insert(0, str(BACKEND))
from general_advice import ADVICE_HONESTY  # noqa: E402
from llm import FAKE_ADVICE_STEP  # noqa: E402
from safety import SAFETY_NOTE  # noqa: E402
SKILL = Path(__file__).resolve().parents[1]
SERVE = Path(__file__).resolve().parent / "serve.py"
RUN_DIR = SKILL / "run"
STATE_PATH = RUN_DIR / "state.json"
EVIDENCE = SKILL / "evidence" / "latest"
FIXTURES = BACKEND / "contracts" / "fixtures"
SCHEMA_PATH = BACKEND / "contracts" / "answer.schema.json"
METRICS_PATH = REPO / "docs" / "METRICS.md"
RESULTS_DIR = BACKEND / "eval" / "results"

CHAT_BODY = {"messages": [{"role": "user", "text": "Why is it hard to start?"}]}
INVALID_BODY = {"messages": []}
# No index on this server, and this request sends no garage. The product asks
# for general advice instead of inventing a cited procedure. The step is the
# fake client's stand-in. It does not name a truck.
FAKE_ANSWER = {
    "kind": "general_advice",
    "honesty": ADVICE_HONESTY,
    "safety": SAFETY_NOTE,
    "steps": [FAKE_ADVICE_STEP],
    "garage": {"source": "none"},
    "related": [],
}
UNCITED_REFUSAL = {
    "kind": "refusal",
    "text": "Not found in the cited manual text: 999 Nm.",
    "reason": "not_found_in_manual",
}
CITED_ANSWER = {
    "kind": "answer",
    "text": "Torque is 999 Nm.",
    "citations": [
        {"doc_id": "FAKE-DOC", "page": 999, "snippet": "FAKE-SNIPPET"},
    ],
}
ALLOWED_FIXTURES = (
    "plain.json",
    "refusal.json",
    "with_citations.json",
    "with_highlight.json",
)


class VerificationError(RuntimeError):
    pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify the Sidekick backend.")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser(
        "run", help="Launch, doctor, drive, swift test, make eval, clean up."
    )

    launch = sub.add_parser(
        "launch", help="Start one verification server and leave it up."
    )
    launch.add_argument(
        "--case",
        required=True,
        choices=("fake", "fixture", "uncited-spec", "cited-spec"),
    )
    launch.add_argument("--name", default=None, help="Fixture file for --case fixture.")

    sub.add_parser("doctor", help="Read-only check of the server this skill started.")

    drive = sub.add_parser("drive", help="Send /chat to the server this skill started.")
    drive.add_argument(
        "case",
        choices=("fake", "fixture", "uncited-spec", "cited-spec"),
    )

    sub.add_parser("swift-test", help="Run swift test in app/SidekickCore.")
    sub.add_parser("eval", help="Run make eval and restore product metric files.")
    sub.add_parser("cleanup", help="Stop the server this skill started.")

    args = parser.parse_args(argv)
    try:
        require_deps()
        if args.command == "run":
            command_run()
        elif args.command == "launch":
            command_launch(args.case, args.name)
        elif args.command == "doctor":
            command_doctor()
        elif args.command == "drive":
            command_drive(args.case)
        elif args.command == "swift-test":
            EVIDENCE.mkdir(parents=True, exist_ok=True)
            run_swift_test(EVIDENCE)
        elif args.command == "eval":
            EVIDENCE.mkdir(parents=True, exist_ok=True)
            run_make_eval(EVIDENCE)
        elif args.command == "cleanup":
            command_cleanup()
        else:
            raise VerificationError(f"unknown command {args.command}")
    except VerificationError as exc:
        print(f"verify-backend: {exc}", file=sys.stderr)
        return 1
    return 0


def require_deps() -> None:
    missing = []
    for name in ("fastapi", "uvicorn", "jsonschema"):
        try:
            __import__(name)
        except ImportError:
            missing.append(name)
    if missing:
        raise VerificationError(
            "missing "
            + ", ".join(missing)
            + ". Install with: python3 -m pip install -r backend/requirements.txt"
        )


def command_run() -> None:
    command_cleanup()
    if EVIDENCE.exists():
        shutil.rmtree(EVIDENCE)
    EVIDENCE.mkdir(parents=True)
    cases: tuple[tuple[str, str | None], ...] = (
        ("fake", None),
        ("fixture", "plain.json"),
        ("fixture", "refusal.json"),
        ("fixture", "with_citations.json"),
        ("fixture", "with_highlight.json"),
        ("uncited-spec", None),
        ("cited-spec", None),
    )
    try:
        for case, fixture in cases:
            run_case(case, fixture)
        run_swift_test(EVIDENCE)
        run_make_eval(EVIDENCE)
    finally:
        command_cleanup()
    expected = [
        "chat-fake.json",
        "chat-invalid.json",
        "chat-plain.json",
        "chat-refusal.json",
        "chat-citations.json",
        "chat-highlight.json",
        "chat-uncited-spec.json",
        "chat-cited-spec.json",
        "swift-test.txt",
        "eval-stdout.txt",
        "eval-results.json",
    ]
    missing = [name for name in expected if not (EVIDENCE / name).is_file()]
    if missing:
        raise VerificationError(f"cleanup removed or skipped evidence: {missing}")
    if STATE_PATH.exists():
        raise VerificationError("cleanup left the server state file in place")
    write_json(
        EVIDENCE / "manifest.json",
        {"files": sorted(p.name for p in EVIDENCE.iterdir())},
    )
    print(f"verify-backend: evidence kept at {EVIDENCE}")


def run_case(case: str, fixture: str | None) -> None:
    proc: subprocess.Popen[bytes] | None = None
    try:
        proc, port = start_server(case, fixture)
        save_state(proc, port, case, fixture)
        doctor_report(proc.pid, port, case, fixture)
        post_case(case, fixture, port)
    finally:
        if proc is not None:
            stop_process(proc)
        if STATE_PATH.exists():
            STATE_PATH.unlink()


def command_launch(case: str, fixture: str | None) -> None:
    if case == "fixture" and fixture not in ALLOWED_FIXTURES:
        raise VerificationError(f"--name must be one of {list(ALLOWED_FIXTURES)}")
    if case != "fixture" and fixture is not None:
        raise VerificationError("--name is only used with --case fixture")
    existing = load_state()
    if existing is not None and pid_alive(existing["pid"]):
        raise VerificationError(
            f"server already running as pid {existing['pid']} on port {existing['port']}. "
            "Run cleanup before launching another."
        )
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    proc, port = start_server(case, fixture)
    save_state(proc, port, case, fixture)
    print(f"verify-backend: listening on http://127.0.0.1:{port} case={case}")


def command_doctor() -> None:
    state = require_state()
    report = doctor_report(state["pid"], state["port"], state["case"], state["fixture"])
    print(json.dumps(report, indent=2))


def command_drive(case: str) -> None:
    state = require_state()
    if state["case"] != case:
        raise VerificationError(
            f"running case is {state['case']!r}, not {case!r}. Launch that case first."
        )
    doctor_report(state["pid"], state["port"], state["case"], state["fixture"])
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    post_case(case, state["fixture"], state["port"])
    print(f"verify-backend: wrote {EVIDENCE}")


def command_cleanup() -> None:
    state = load_state()
    if state is not None and pid_alive(state["pid"]):
        stop_pid(state["pid"])
    if STATE_PATH.exists():
        STATE_PATH.unlink()
    print("verify-backend: cleanup finished")


def start_server(case: str, fixture: str | None) -> tuple[subprocess.Popen[bytes], int]:
    if case == "fixture" and fixture not in ALLOWED_FIXTURES:
        raise VerificationError(f"fixture must be one of {list(ALLOWED_FIXTURES)}")
    port = free_port()
    env = os.environ.copy()
    env.pop("SIDEKICK_LLM_API_KEY", None)
    env["SIDEKICK_VERIFY_CASE"] = case
    if fixture is not None:
        env["SIDEKICK_VERIFY_FIXTURE"] = fixture
    else:
        env.pop("SIDEKICK_VERIFY_FIXTURE", None)
    label = fixture or case
    log_path = EVIDENCE / f"server-{label}.log"
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    log_file = log_path.open("w", encoding="utf-8")
    proc = subprocess.Popen(
        [sys.executable, str(SERVE), "--host", "127.0.0.1", "--port", str(port)],
        cwd=str(BACKEND),
        env=env,
        stdout=log_file,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    log_file.close()
    try:
        wait_until_ready(proc, port)
    except Exception:
        stop_process(proc)
        raise
    return proc, port


def wait_until_ready(proc: subprocess.Popen[bytes], port: int) -> None:
    deadline = time.monotonic() + 15
    last_error = "server did not open /openapi.json"
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise VerificationError(
                f"server exited {proc.returncode} before it was ready"
            )
        try:
            status, payload = request_json("GET", port, "/openapi.json", None)
        except OSError as exc:
            last_error = str(exc)
            time.sleep(0.1)
            continue
        if status == 200 and isinstance(payload, dict):
            return
        last_error = f"openapi status {status}"
        time.sleep(0.1)
    raise VerificationError(last_error)


def doctor_report(
    pid: int,
    port: int,
    case: str,
    fixture: str | None,
) -> dict[str, Any]:
    if not pid_alive(pid):
        raise VerificationError(f"pid {pid} is not running")
    command = process_cmdline(pid)
    if "serve.py" not in command:
        raise VerificationError(f"pid {pid} is not the verification server")
    owners = listener_pids(port)
    if pid not in owners:
        raise VerificationError(
            f"port {port} is not owned by pid {pid} (owners={owners})"
        )
    if api_key_set(pid):
        raise VerificationError("SIDEKICK_LLM_API_KEY is set in the server process")
    status, payload = request_json("GET", port, "/openapi.json", None)
    if status != 200 or not isinstance(payload, dict):
        raise VerificationError(f"openapi check returned {status}")
    info = payload.get("info")
    title = info.get("title") if isinstance(info, dict) else None
    if title != "Sidekick Mechanic":
        raise VerificationError(f"openapi title is {title!r}")
    paths = payload.get("paths")
    chat = paths.get("/chat") if isinstance(paths, dict) else None
    if not isinstance(chat, dict) or "post" not in chat:
        raise VerificationError("openapi is missing POST /chat")
    report = {
        "ok": True,
        "url": f"http://127.0.0.1:{port}",
        "pid": pid,
        "port_owned_by_pid": True,
        "api_key_set": False,
        "title": title,
        "has_post_chat": True,
        "case": case,
        "fixture": fixture,
        "python": sys.version.split()[0],
        "git_head": git_head(),
    }
    write_json(EVIDENCE / f"doctor-{evidence_label(case, fixture)}.json", report)
    return report


def post_case(case: str, fixture: str | None, port: int) -> None:
    if case == "fake":
        record_chat(port, "chat-fake", "chat-contract", CHAT_BODY, FAKE_ANSWER)
        status, body = request_json("POST", port, "/chat", INVALID_BODY)
        if status != 422 or not isinstance(body, dict) or "detail" not in body:
            raise VerificationError(f"invalid request returned {status}: {body!r}")
        write_json(
            EVIDENCE / "chat-invalid.json",
            {
                "feature_id": "chat-invalid",
                "entry_point": "POST /chat",
                "request": INVALID_BODY,
                "status": status,
                "response": body,
            },
        )
        return
    if case == "fixture":
        if fixture is None:
            raise VerificationError("fixture drive has no fixture name")
        expected = json.loads((FIXTURES / fixture).read_text(encoding="utf-8"))
        record_chat(
            port,
            fixture_evidence_name(fixture),
            fixture_feature_id(fixture),
            CHAT_BODY,
            expected,
        )
        if fixture == "with_citations.json":
            actual = json.loads(
                (EVIDENCE / "chat-citations.json").read_text(encoding="utf-8")
            )
            citation = actual["response"]["citations"][0]
            if citation["doc_id"] != "FAKE-DOC-2JZ" or citation["page"] != 999:
                raise VerificationError(
                    f"citation fixture lost the fake page: {citation}"
                )
        if fixture == "with_highlight.json":
            actual = json.loads(
                (EVIDENCE / "chat-highlight.json").read_text(encoding="utf-8")
            )
            highlight = actual["response"]["highlight"]
            if highlight != {
                "bay_photo_id": "fake-bay-photo-front",
                "part_id": "fake-part-intake",
            }:
                raise VerificationError(f"highlight fixture changed: {highlight}")
        return
    if case == "uncited-spec":
        record_chat(
            port,
            "chat-uncited-spec",
            "chat-spec-guard-blocks",
            CHAT_BODY,
            UNCITED_REFUSAL,
        )
        return
    if case == "cited-spec":
        record_chat(
            port, "chat-cited-spec", "chat-spec-guard-allows", CHAT_BODY, CITED_ANSWER
        )
        return
    raise VerificationError(f"unknown case {case}")


def record_chat(
    port: int,
    stem: str,
    feature_id: str,
    request_body: dict[str, Any],
    expected: dict[str, Any],
) -> None:
    status, body = request_json("POST", port, "/chat", request_body)
    schema_valid = False
    schema_error = None
    if status == 200 and isinstance(body, dict):
        try:
            validate_answer(body)
            schema_valid = True
        except ValidationError as exc:
            schema_error = str(exc)
    write_json(
        EVIDENCE / f"{stem}.json",
        {
            "feature_id": feature_id,
            "entry_point": "POST /chat",
            "request": request_body,
            "status": status,
            "response": body,
            "schema_valid": schema_valid,
            "schema_error": schema_error,
        },
    )
    if status != 200 or body != expected or not schema_valid:
        raise VerificationError(
            f"{feature_id} expected 200 {expected!r} and a valid schema, "
            f"got {status} {body!r} schema_valid={schema_valid}"
        )


def validate_answer(payload: dict[str, Any]) -> None:
    from jsonschema.validators import Draft202012Validator

    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    Draft202012Validator(schema).validate(payload)


def run_swift_test(evidence: Path) -> None:
    swift = shutil.which("swift")
    if swift is None:
        raise VerificationError(
            "swift is not on PATH. Install Swift 6, then rerun swift-test."
        )
    proc = subprocess.run(
        [swift, "test"],
        cwd=REPO / "app" / "SidekickCore",
        capture_output=True,
        text=True,
        timeout=600,
        check=False,
    )
    text = proc.stdout + proc.stderr
    (evidence / "swift-test.txt").write_text(text, encoding="utf-8")
    (evidence / "swift-test-exit.txt").write_text(
        f"{proc.returncode}\n", encoding="utf-8"
    )
    if proc.returncode != 0 or "Test Suite 'All tests' passed" not in text:
        raise VerificationError("swift test failed. See evidence/latest/swift-test.txt")


def run_make_eval(evidence: Path) -> None:
    # make eval rewrites docs/METRICS.md and backend/eval/results/. The proof
    # is the copy below. Restore the tracked bytes so a verify run does not
    # change product metrics.
    snapshot = snapshot_files([METRICS_PATH], RESULTS_DIR)
    try:
        proc = subprocess.run(
            ["make", "eval", f"PYTHON={sys.executable}"],
            cwd=REPO,
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        (evidence / "eval-stdout.txt").write_text(proc.stdout, encoding="utf-8")
        (evidence / "eval-stderr.txt").write_text(proc.stderr, encoding="utf-8")
        changed = changed_files(snapshot, RESULTS_DIR)
        if len(changed) != 1:
            raise VerificationError(
                f"make eval changed {len(changed)} result files: {changed}"
            )
        (evidence / "eval-results.json").write_bytes(changed[0].read_bytes())
        if proc.returncode != 0:
            raise VerificationError(
                "make eval failed. See evidence/latest/eval-stderr.txt"
            )
        for token in (
            "recall@5",
            "citation accuracy",
            "refusal correctness",
            "uncited-number count",
            "latency p50 (ms)",
            "latency p95 (ms)",
            "Wrote ",
        ):
            if token not in proc.stdout:
                raise VerificationError(f"make eval stdout is missing {token!r}")
        payload = json.loads(
            (evidence / "eval-results.json").read_text(encoding="utf-8")
        )
        if (
            payload.get("case_count") != 4
            or payload.get("runner") != "inprocess_chat_fake_llm"
        ):
            raise VerificationError(f"unexpected eval payload keys {sorted(payload)}")
    finally:
        restore_files(snapshot, RESULTS_DIR)


def snapshot_files(files: list[Path], directory: Path) -> dict[str, bytes | None]:
    snap: dict[str, bytes | None] = {}
    for path in files:
        snap[str(path)] = path.read_bytes() if path.is_file() else None
    if directory.is_dir():
        for child in directory.glob("*.json"):
            snap[str(child)] = child.read_bytes()
    return snap


def changed_files(snapshot: dict[str, bytes | None], directory: Path) -> list[Path]:
    changed = []
    for child in sorted(directory.glob("*.json")):
        current = child.read_bytes()
        if snapshot.get(str(child)) != current:
            changed.append(child)
    return changed


def restore_files(snapshot: dict[str, bytes | None], directory: Path) -> None:
    for key, data in snapshot.items():
        path = Path(key)
        if data is None:
            if path.is_file():
                path.unlink()
        else:
            path.write_bytes(data)
    if directory.is_dir():
        for child in directory.glob("*.json"):
            if str(child) not in snapshot:
                child.unlink()


def request_json(
    method: str,
    port: int,
    path: str,
    body: dict[str, Any] | None,
) -> tuple[int, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}",
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        try:
            parsed: Any = json.loads(raw)
        except json.JSONDecodeError:
            parsed = raw
        return exc.code, parsed


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def save_state(
    proc: subprocess.Popen[bytes],
    port: int,
    case: str,
    fixture: str | None,
) -> None:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    write_json(
        STATE_PATH,
        {"pid": proc.pid, "port": port, "case": case, "fixture": fixture},
    )


def load_state() -> dict[str, Any] | None:
    if not STATE_PATH.is_file():
        return None
    payload = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise VerificationError("server state file is not an object")
    return payload


def require_state() -> dict[str, Any]:
    state = load_state()
    if state is None:
        raise VerificationError("no verification server is recorded. Run launch first.")
    return state


def stop_process(proc: subprocess.Popen[bytes]) -> None:
    if proc.poll() is not None:
        return
    stop_pid(proc.pid)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.wait(timeout=5)


def stop_pid(pid: int) -> None:
    try:
        os.killpg(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if not pid_alive(pid):
            return
        time.sleep(0.1)
    try:
        os.killpg(pid, signal.SIGKILL)
    except ProcessLookupError:
        return


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def process_cmdline(pid: int) -> str:
    raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    return raw.replace(b"\0", b" ").decode("utf-8", errors="replace")


def api_key_set(pid: int) -> bool:
    raw = Path(f"/proc/{pid}/environ").read_bytes()
    for item in raw.split(b"\0"):
        if item.startswith(b"SIDEKICK_LLM_API_KEY="):
            return bool(item.split(b"=", 1)[1].strip())
    return False


def listener_pids(port: int) -> list[int]:
    hex_port = f"{port:04X}"
    inodes: set[str] = set()
    tcp = Path("/proc/net/tcp").read_text(encoding="utf-8")
    for line in tcp.splitlines()[1:]:
        parts = line.split()
        local = parts[1]
        state = parts[3]
        if state != "0A":
            continue
        _ip, local_port = local.split(":")
        if local_port.upper() != hex_port:
            continue
        inodes.add(parts[9])
    if not inodes:
        return []
    found: list[int] = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        fd_dir = entry / "fd"
        try:
            fds = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                found.append(int(entry.name))
                break
    return found


def git_head() -> str:
    proc = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.stdout.strip()


def evidence_label(case: str, fixture: str | None) -> str:
    if case == "fixture" and fixture is not None:
        return fixture.removesuffix(".json")
    return case


def fixture_evidence_name(fixture: str) -> str:
    return {
        "plain.json": "chat-plain",
        "refusal.json": "chat-refusal",
        "with_citations.json": "chat-citations",
        "with_highlight.json": "chat-highlight",
    }[fixture]


def fixture_feature_id(fixture: str) -> str:
    return {
        "plain.json": "chat-plain-fixture",
        "refusal.json": "chat-refusal",
        "with_citations.json": "chat-citations",
        "with_highlight.json": "chat-highlight",
    }[fixture]


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
