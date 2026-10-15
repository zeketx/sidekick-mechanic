"""Live POST /chat scoring. Fixtures are fake. No secrets in output."""

from __future__ import annotations

import json
from collections.abc import Callable
from pathlib import Path
from typing import Any

import httpx
import pytest

from eval.__main__ import main
from eval.harness import run_harness
from eval.report import render_job_summary
from eval.runner import HttpBackendRunner, RunnerError
from general_advice import ADVICE_HONESTY
from safety import SAFETY_NOTE

FAKE_DATE = "2026-10-01"
SECRET = "sk-SECRET"
ANSWER = {
    "kind": "answer",
    "text": "See the fixture page.",
    "citations": [
        {"doc_id": "FAKE-DOC", "page": 999, "snippet": "FAKE-SPEC"},
    ],
}
REFUSAL = {
    "kind": "refusal",
    "text": "Not in the fixture.",
    "reason": "not_found_in_manual",
}


def _golden(path: Path) -> Path:
    rows = [
        {
            "id": "fake-hit",
            "question": "Where is FAKE-PART?",
            "answerable": True,
            "expected": [{"doc_id": "FAKE-DOC", "page": 999}],
        },
        {
            "id": "fake-refuse",
            "question": "What is the FAKE-CONNECTOR pinout?",
            "answerable": False,
            "expected": [],
        },
    ]
    destination = path / "golden.jsonl"
    destination.write_text(
        "".join(json.dumps(row) + "\n" for row in rows),
        encoding="utf-8",
    )
    return destination


def _reply_for(body: bytes) -> dict[str, Any]:
    payload = json.loads(body)
    question = payload["messages"][0]["text"]
    if "FAKE-PART" in question:
        return ANSWER
    return REFUSAL


def test_runner_scores_chat_and_drops_url_secrets() -> None:
    seen: list[httpx.URL] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url)
        return httpx.Response(200, json=_reply_for(request.content))

    client = httpx.Client(transport=httpx.MockTransport(handler))
    runner = HttpBackendRunner(
        f"https://user:{SECRET}@127.0.0.1:8001/chat?api_key={SECRET}#frag",
        client=client,
    )

    output = runner.run("Where is FAKE-PART?")

    assert output.answer == ANSWER
    assert output.retrieval is None
    assert len(seen) == 1
    assert str(seen[0]) == "https://127.0.0.1:8001/chat"
    assert SECRET not in str(seen[0])
    client.close()


def test_error_text_omits_the_response_body() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        del request
        return httpx.Response(500, text=f"token {SECRET}")

    client = httpx.Client(transport=httpx.MockTransport(handler))
    runner = HttpBackendRunner("http://127.0.0.1:8001", client=client)

    with pytest.raises(RunnerError) as exc:
        runner.run("Where is FAKE-PART?")

    assert str(exc.value) == "POST /chat returned 500"
    assert SECRET not in str(exc.value)
    client.close()


def test_transport_failure_omits_the_client_message() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        del request
        raise httpx.ConnectError(f"dial {SECRET}")

    client = httpx.Client(transport=httpx.MockTransport(handler))
    runner = HttpBackendRunner("http://127.0.0.1:8001", client=client)

    with pytest.raises(RunnerError) as exc:
        runner.run("Where is FAKE-PART?")

    assert str(exc.value) == "POST /chat failed"
    assert SECRET not in str(exc.value)
    client.close()


def test_non_object_body_is_a_fixed_error() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        del request
        return httpx.Response(200, text=SECRET)

    client = httpx.Client(transport=httpx.MockTransport(handler))
    runner = HttpBackendRunner("http://127.0.0.1:8001", client=client)

    with pytest.raises(RunnerError) as exc:
        runner.run("Where is FAKE-PART?")

    assert str(exc.value) == "POST /chat returned a non-object body"
    assert SECRET not in str(exc.value)
    client.close()


def test_bad_scheme_error_does_not_echo_the_url() -> None:
    with pytest.raises(RunnerError) as exc:
        HttpBackendRunner(f"file:///tmp/{SECRET}")

    assert str(exc.value) == "backend URL must be http or https"
    assert SECRET not in str(exc.value)


def test_redirect_is_not_followed(monkeypatch: pytest.MonkeyPatch) -> None:
    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(str(request.url))
        return httpx.Response(302, headers={"location": f"http://127.0.0.1/{SECRET}"})

    _patch_client(monkeypatch, handler)
    runner = HttpBackendRunner("http://127.0.0.1:8001")
    try:
        with pytest.raises(RunnerError) as exc:
            runner.run("Where is FAKE-PART?")
    finally:
        runner.close()

    assert seen == ["http://127.0.0.1:8001/chat"]
    assert str(exc.value) == "POST /chat returned 302"
    assert SECRET not in str(exc.value)


def test_runner_scores_advice_and_recall_from_the_debug_header(
    tmp_path: Path,
) -> None:
    advice = {
        "kind": "general_advice",
        "honesty": ADVICE_HONESTY,
        "safety": SAFETY_NOTE,
        "steps": ["FAKE-STEP: look at the fixture."],
        "garage": {"source": "none"},
        "related": [
            {"doc_id": "FAKE-DOC", "page": 999, "snippet": "FAKE-SPEC"},
        ],
    }

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["x-sidekick-eval"] == "retrieval"
        question = json.loads(request.content)["messages"][0]["text"]
        if "FAKE-PART" in question:
            body: dict[str, Any] = ANSWER
            header = "FAKE-DOC:999"
        else:
            body = advice
            header = "-"
        return httpx.Response(
            200,
            json=body,
            headers={"X-Sidekick-Retrieval": header},
        )

    client = httpx.Client(transport=httpx.MockTransport(handler))
    runner = HttpBackendRunner("http://127.0.0.1:8001", client=client)
    payload = run_harness(
        _golden(tmp_path),
        runner=runner,
        output_dir=tmp_path,
        date=FAKE_DATE,
    )
    written = (tmp_path / f"{FAKE_DATE}.json").read_text(encoding="utf-8")
    client.close()

    assert payload["metrics"]["citation_accuracy"] == 1.0
    assert payload["metrics"]["refusal_correctness"] == 1.0
    assert payload["metrics"]["recall_at_5"] == 1.0
    assert payload["cases"][1]["refusal_correct"] is True
    assert "FAKE-PAGE-TEXT" not in written
    assert SECRET not in written


def test_bad_retrieval_header_is_not_echoed() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        del request
        return httpx.Response(
            200,
            json=ANSWER,
            headers={"X-Sidekick-Retrieval": SECRET},
        )

    client = httpx.Client(transport=httpx.MockTransport(handler))
    runner = HttpBackendRunner("http://127.0.0.1:8001", client=client)

    with pytest.raises(RunnerError) as exc:
        runner.run("Where is FAKE-PART?")

    assert str(exc.value) == "retrieval header is not pages"
    assert SECRET not in str(exc.value)
    client.close()


def test_harness_results_score_chat_and_omit_the_url(tmp_path: Path) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_reply_for(request.content))

    client = httpx.Client(transport=httpx.MockTransport(handler))
    runner = HttpBackendRunner(
        f"http://user:{SECRET}@127.0.0.1:8001",
        client=client,
    )
    path = _golden(tmp_path)
    payload = run_harness(path, runner=runner, output_dir=tmp_path, date=FAKE_DATE)
    written = (tmp_path / f"{FAKE_DATE}.json").read_text(encoding="utf-8")
    summary = render_job_summary(payload)
    client.close()

    assert payload["runner"] == "http_backend"
    assert payload["metrics"]["citation_accuracy"] == 1.0
    assert payload["metrics"]["refusal_correctness"] == 1.0
    assert payload["metrics"]["recall_at_5"] is None
    assert all(case["retrieval_available"] is False for case in payload["cases"])
    assert SECRET not in written
    assert "127.0.0.1" not in written
    assert "Citation and refusal scores come from POST /chat." in summary
    assert "Recall@5 was not measured." in summary
    assert "Smoke test" not in summary


def test_cli_backend_scores_chat_and_hides_secrets(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    seen: list[httpx.URL] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url)
        return httpx.Response(200, json=_reply_for(request.content))

    _patch_client(monkeypatch, handler)
    path = _golden(tmp_path)
    code = main(
        [
            "--golden",
            str(path),
            "--output-dir",
            str(tmp_path),
            "--date",
            FAKE_DATE,
            "--backend",
            f"http://user:{SECRET}@127.0.0.1:8001/chat?api_key={SECRET}#x",
        ]
    )
    captured = capsys.readouterr()
    written = (tmp_path / f"{FAKE_DATE}.json").read_text(encoding="utf-8")

    assert code == 0
    assert json.loads(written)["runner"] == "http_backend"
    assert json.loads(written)["metrics"]["citation_accuracy"] == 1.0
    assert json.loads(written)["metrics"]["refusal_correctness"] == 1.0
    assert json.loads(written)["metrics"]["recall_at_5"] is None
    assert SECRET not in written
    assert "127.0.0.1" not in written
    assert SECRET not in captured.out
    assert SECRET not in captured.err
    assert "Citation and refusal scores come from POST /chat." in captured.out
    assert len(seen) == 2
    assert {str(url) for url in seen} == {"http://127.0.0.1:8001/chat"}


def _patch_client(
    monkeypatch: pytest.MonkeyPatch,
    handler: Callable[[httpx.Request], httpx.Response],
) -> None:
    original = httpx.Client

    def factory(*args: Any, **kwargs: Any) -> httpx.Client:
        assert kwargs["trust_env"] is False
        assert kwargs["follow_redirects"] is False
        kwargs["transport"] = httpx.MockTransport(handler)
        return original(*args, **kwargs)

    monkeypatch.setattr("eval.runner.httpx.Client", factory)
