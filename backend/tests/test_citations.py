from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app import create_app
from chat_models import Conversation, GarageContext, GarageNoteContext, Message
from general_advice import ADVICE_HONESTY, ADVICE_STEPS_HEADER
from llm import FAKE_GROUNDED_TEXT, ChatTurn, FakeLLMClient, LLMError
from part_resolver import BayMapView, BayPartView
from producer import (
    WIRING_NOT_INGESTED_REFUSAL,
    LlmAnswerProducer,
    _IndexRetriever,
)
from retrieval import Chunk, build_index, snippet_matches_page
from safety import SAFETY_NOTE

_DOC = "FAKE-DOC-2JZ"
_PAGE = 999
_SNIPPET = "FAKE-SNIPPET: no real spec."
_FAKE_PART_PAGE = "FAKE-PAGE: the fake part."
_QUESTION = "Where is the fake part?"
_ANSWER = "The fake page names the fixture part."
_UNAVAILABLE = {
    "kind": "error",
    "text": "The mechanic is unavailable right now. Try again in a moment.",
    "reason": "provider_unavailable",
}
_FAKE_STEP = "FAKE-STEP: check the fixture connection before the fixture motor."


class _Hit:
    def __init__(self, doc_id: str, page: int, text: str) -> None:
        self.doc_id = doc_id
        self.page = page
        self.text = text


class _Retriever:
    def __init__(self, hits: tuple[_Hit, ...]) -> None:
        self._hits = hits
        self.queries: list[str] = []

    def search(self, query: str, k: int = 5) -> tuple[_Hit, ...]:
        self.queries.append(query)
        return self._hits


def _conversation(text: str = _QUESTION) -> Conversation:
    return Conversation(messages=[Message(role="user", text=text)])


def _completion(text: str, citations: list[dict[str, Any]]) -> str:
    return json.dumps({"text": text, "citations": citations})


def _advice(
    related: list[dict[str, Any]] | None = None,
    steps: list[str] | None = None,
) -> dict[str, Any]:
    return {
        "kind": "general_advice",
        "honesty": ADVICE_HONESTY,
        "safety": SAFETY_NOTE,
        "steps": [_FAKE_STEP] if steps is None else steps,
        "garage": {"source": "none"},
        "related": [] if related is None else related,
    }


def _grounded_call(fake: FakeLLMClient) -> list[ChatTurn]:
    for call in fake.calls:
        if any("Retrieved pages:" in turn.content for turn in call):
            return call
    raise AssertionError("no grounded call")


def _cited(
    snippet: str = _SNIPPET,
    *,
    page: int = _PAGE,
    doc_id: str = _DOC,
) -> dict[str, Any]:
    return {"doc_id": doc_id, "page": page, "snippet": snippet}


def _producer(
    completion: str,
    hits: tuple[_Hit, ...],
    *,
    error: Exception | None = None,
) -> tuple[LlmAnswerProducer, FakeLLMClient, _Retriever]:
    fake = FakeLLMClient(text=completion, error=error)
    retriever = _Retriever(hits)
    return LlmAnswerProducer(fake, retriever=retriever), fake, retriever


def test_cited_answer_keeps_retrieved_snippet() -> None:
    producer, fake, retriever = _producer(
        _completion(_ANSWER, [_cited()]),
        (_Hit(_DOC, _PAGE, _SNIPPET),),
    )

    payload = producer.produce(_conversation())

    assert payload == {
        "kind": "answer",
        "text": _ANSWER,
        "citations": [_cited()],
    }
    assert retriever.queries == [_QUESTION]
    system = _grounded_call(fake)[0]
    assert system.role == "system"
    assert "Do not invent torque" in system.content
    assert "If you do not know, say so." not in system.content
    assert "do not invent tokens" in system.content.lower()
    assert '"page" (integer)' in system.content
    assert "Retrieved pages:" in system.content
    assert _SNIPPET in system.content
    assert "citations" in system.content
    assert "doc_id" in system.content
    assert "snippet" in system.content
    assert '"score"' not in system.content
    assert '"rank"' not in system.content
    assert "N·m" not in system.content
    assert _grounded_call(fake)[1] == ChatTurn(role="user", content=_QUESTION)


def test_cited_answer_keeps_pages_when_garage_notes_are_present() -> None:
    producer, fake, retriever = _producer(
        _completion(_ANSWER, [_cited()]),
        (_Hit(_DOC, _PAGE, _SNIPPET),),
    )
    conversation = Conversation(
        messages=[Message(role="user", text=_QUESTION)],
        garage=GarageContext(
            notes=[GarageNoteContext(name="Wiring harness", note="already replaced")]
        ),
    )

    payload = producer.produce(conversation)

    assert payload == {
        "kind": "answer",
        "text": _ANSWER,
        "citations": [_cited()],
    }
    assert retriever.queries == [_QUESTION]
    system = _grounded_call(fake)[0].content
    assert "already replaced" in system
    assert "Retrieved pages:" in system
    pages = system.split("Retrieved pages:\n", 1)[1]
    assert _SNIPPET in pages
    assert "already replaced" not in pages


def test_mixed_citations_keep_only_retrieved_page() -> None:
    producer, _, _ = _producer(
        _completion(
            _ANSWER,
            [_cited(page=998), _cited()],
        ),
        (_Hit(_DOC, _PAGE, _SNIPPET),),
    )

    payload = producer.produce(_conversation())

    assert payload == {
        "kind": "answer",
        "text": _ANSWER,
        "citations": [_cited()],
    }


def test_whitespace_normalized_snippet_is_kept() -> None:
    page_text = "FAKE-SNIPPET:\nno   real spec."
    producer, _, _ = _producer(
        _completion(_ANSWER, [_cited("FAKE-SNIPPET: no real spec.")]),
        (_Hit(_DOC, _PAGE, page_text),),
    )

    payload = producer.produce(_conversation())

    assert payload["kind"] == "answer"
    assert payload["citations"][0]["snippet"] == page_text
    assert snippet_matches_page("FAKE-SNIPPET: no real spec.", page_text)


def test_rearranged_snippet_is_replaced_with_the_page() -> None:
    page_text = "spec. FAKE-SNIPPET: no real"
    producer, _, _ = _producer(
        _completion(_ANSWER, [_cited("FAKE-SNIPPET: no real spec.")]),
        (_Hit(_DOC, _PAGE, page_text),),
    )

    payload = producer.produce(_conversation())

    assert payload["kind"] == "answer"
    assert payload["text"] == _ANSWER
    chip = payload["citations"][0]["snippet"]
    assert chip in page_text
    assert chip != "FAKE-SNIPPET: no real spec."


def test_invented_snippet_keeps_the_retrieved_page() -> None:
    producer, _, _ = _producer(
        _completion(_ANSWER, [_cited("FAKE-SNIPPET: invented and not on the page.")]),
        (_Hit(_DOC, _PAGE, _SNIPPET),),
    )

    payload = producer.produce(_conversation())

    assert payload == {
        "kind": "answer",
        "text": _ANSWER,
        "citations": [_cited()],
    }
    assert "invented" not in payload["citations"][0]["snippet"]


def test_unretrieved_page_logs_citation_mismatch(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.WARNING, logger="sidekick.llm")
    producer, _, _ = _producer(
        _completion(_ANSWER, [_cited(page=998)]),
        (_Hit(_DOC, _PAGE, _SNIPPET),),
    )

    payload = producer.produce(_conversation())

    assert payload == _UNAVAILABLE
    assert "kind=parse" in caplog.text
    assert "detail=citation_mismatch" in caplog.text
    assert "FAKE-SNIPPET" not in caplog.text


def test_empty_search_returns_general_advice() -> None:
    fake = FakeLLMClient()
    producer = LlmAnswerProducer(fake, retriever=_Retriever(()))

    payload = producer.produce(_conversation())

    assert payload == _advice()
    assert len(fake.calls) == 1
    system = fake.calls[0][0].content
    assert ADVICE_STEPS_HEADER in system
    assert "Retrieved pages:" not in system
    assert _SNIPPET not in system


def test_empty_citations_array_discards_model_text_and_uses_hits() -> None:
    grounded = json.dumps({"text": "nope", "citations": []})
    steps = json.dumps(
        {
            "steps": [_FAKE_STEP],
            "related": [{"doc_id": "MODEL-PICKED", "page": 1, "snippet": "not a hit"}],
        }
    )
    fake = FakeLLMClient(script=(grounded, steps))
    producer = LlmAnswerProducer(
        fake, retriever=_Retriever((_Hit(_DOC, _PAGE, _FAKE_PART_PAGE),))
    )

    payload = producer.produce(_conversation())

    assert payload == _advice(
        related=[{"doc_id": _DOC, "page": _PAGE, "snippet": _FAKE_PART_PAGE}]
    )
    assert "nope" not in json.dumps(payload)
    assert "MODEL-PICKED" not in json.dumps(payload)
    advice_calls = [
        call
        for call in fake.calls
        if any(ADVICE_STEPS_HEADER in turn.content for turn in call)
    ]
    assert advice_calls
    advice = advice_calls[0][0].content
    assert ADVICE_STEPS_HEADER in advice
    assert "Retrieved pages:" not in advice
    assert _FAKE_PART_PAGE not in advice
    assert _FAKE_PART_PAGE in _grounded_call(fake)[0].content


def test_prose_completion_is_unavailable() -> None:
    producer, _, _ = _producer(
        "This prose is not a JSON object.",
        (_Hit(_DOC, _PAGE, _SNIPPET),),
    )

    payload = producer.produce(_conversation())

    assert payload == _UNAVAILABLE


def test_prose_completion_logs_parse_rejection(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.WARNING, logger="sidekick.llm")
    producer, _, _ = _producer(
        "This prose is not a JSON object.",
        (_Hit(_DOC, _PAGE, _SNIPPET),),
    )

    payload = producer.produce(_conversation())

    assert payload == _UNAVAILABLE
    assert "kind=parse" in caplog.text
    assert "detail=grounded_json" in caplog.text
    assert "This prose" not in caplog.text


def test_llm_error_with_hits_is_unavailable() -> None:
    producer, _, _ = _producer(
        _ANSWER,
        (_Hit(_DOC, _PAGE, _SNIPPET),),
        error=LLMError("boom"),
    )

    payload = producer.produce(_conversation())

    assert payload == _UNAVAILABLE


def test_long_snippet_is_capped_on_whitespace() -> None:
    page_text = "FAKE-WORD " * 40
    stored = ("FAKE-WORD " * 27) + "FAKE-WORD"
    producer, _, _ = _producer(
        _completion(_ANSWER, [_cited(page_text)]),
        (_Hit(_DOC, _PAGE, page_text),),
    )

    payload = producer.produce(_conversation())

    assert payload == {
        "kind": "answer",
        "text": _ANSWER,
        "citations": [_cited(stored)],
    }
    assert stored in page_text
    assert len(stored) <= 280
    assert stored.endswith("FAKE-WORD")


def test_no_retriever_wraps_prose_with_empty_citations() -> None:
    prose = "Fixture prose with no manual page."
    payload = LlmAnswerProducer(FakeLLMClient(text=prose)).produce(_conversation())

    assert payload == {"kind": "answer", "text": prose, "citations": []}


def test_chat_keeps_a_spec_that_is_in_the_retrieved_page() -> None:
    page_text = "FAKE-CHUNK: torque is 999 N·m."
    answer = "Torque is 999 Nm."
    snippet = "torque is 999 N·m."
    producer, _, _ = _producer(
        _completion(answer, [_cited(snippet)]),
        (_Hit(_DOC, _PAGE, page_text),),
    )

    response = TestClient(create_app(producer=producer)).post(
        "/chat",
        json={"messages": [{"role": "user", "text": _QUESTION}]},
    )

    assert response.status_code == 200
    assert response.json() == {
        "kind": "answer",
        "text": answer,
        "citations": [_cited(snippet)],
    }


def test_chat_returns_cited_answer_and_refusal_without_safety_note() -> None:
    cited_producer, _, _ = _producer(
        _completion(_ANSWER, [_cited()]),
        (_Hit(_DOC, _PAGE, _SNIPPET),),
    )
    cited = TestClient(create_app(producer=cited_producer)).post(
        "/chat",
        json={"messages": [{"role": "user", "text": _QUESTION}]},
    )

    assert cited.status_code == 200
    assert cited.json() == {
        "kind": "answer",
        "text": _ANSWER,
        "citations": [_cited()],
    }

    miss = FakeLLMClient()
    miss_producer = LlmAnswerProducer(miss, retriever=_Retriever(()))
    refused = TestClient(create_app(producer=miss_producer)).post(
        "/chat",
        json={"messages": [{"role": "user", "text": _QUESTION}]},
    )

    assert refused.status_code == 200
    body = refused.json()
    assert body == _advice()
    assert "text" not in body


def test_markdown_fence_json_is_a_cited_answer() -> None:
    fenced = "```json\n" + _completion(_ANSWER, [_cited()]) + "\n```"
    producer, _, _ = _producer(fenced, (_Hit(_DOC, _PAGE, _SNIPPET),))

    payload = producer.produce(_conversation())

    assert payload == {
        "kind": "answer",
        "text": _ANSWER,
        "citations": [_cited()],
    }


def test_ill_typed_citations_are_unavailable() -> None:
    producer, _, _ = _producer(
        json.dumps(
            {
                "text": "nope",
                "citations": [{"doc_id": " ", "page": True, "snippet": " "}],
            }
        ),
        (_Hit(_DOC, _PAGE, _SNIPPET),),
    )

    payload = producer.produce(_conversation())

    assert payload == _UNAVAILABLE
    assert "nope" not in json.dumps(payload)


def test_blank_text_with_empty_citations_is_general_advice() -> None:
    fake = FakeLLMClient(
        script=(
            json.dumps({"text": "", "citations": []}),
            json.dumps({"steps": [_FAKE_STEP]}),
        )
    )
    producer = LlmAnswerProducer(
        fake, retriever=_Retriever((_Hit(_DOC, _PAGE, _FAKE_PART_PAGE),))
    )

    payload = producer.produce(_conversation())

    assert payload == _advice(
        related=[{"doc_id": _DOC, "page": _PAGE, "snippet": _FAKE_PART_PAGE}]
    )


def test_case_changed_snippet_is_kept() -> None:
    producer, _, _ = _producer(
        _completion(_ANSWER, [_cited("fake-snippet: no real spec.")]),
        (_Hit(_DOC, _PAGE, _SNIPPET),),
    )

    payload = producer.produce(_conversation())

    assert payload == {
        "kind": "answer",
        "text": _ANSWER,
        "citations": [_cited(_SNIPPET)],
    }


def test_split_number_is_not_stored_as_the_model_wrote_it() -> None:
    page_text = "Step 1. 8 Nm bolts on the fixture. FAKE-SPEC"
    producer, _, _ = _producer(
        _completion(_ANSWER, [_cited("1.8 Nm")]),
        (_Hit(_DOC, _PAGE, page_text),),
    )

    payload = producer.produce(_conversation())

    assert payload["kind"] == "answer"
    chip = payload["citations"][0]["snippet"]
    assert "1.8" not in chip
    assert not any(token.isdigit() for token in chip.split())


def test_repaired_page_still_refuses_a_number_the_page_lacks() -> None:
    page_text = "FAKE-SNIPPET: no real spec."
    producer, _, _ = _producer(
        _completion(
            "Torque is 999 Nm.",
            [_cited("FAKE-SNIPPET: invented and not on the page.")],
        ),
        (_Hit(_DOC, _PAGE, page_text),),
    )

    response = TestClient(create_app(producer=producer)).post(
        "/chat",
        json={"messages": [{"role": "user", "text": _QUESTION}]},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["kind"] == "refusal"
    assert body["reason"] == "not_found_in_manual"
    assert "999" in body["text"]


def test_long_snippet_cuts_back_from_a_mid_word_boundary() -> None:
    page_text = ("FAKE-WORD " * 27) + "EXTRA-TAIL-LONG"
    stored = ("FAKE-WORD " * 26) + "FAKE-WORD"
    producer, _, _ = _producer(
        _completion(_ANSWER, [_cited(page_text)]),
        (_Hit(_DOC, _PAGE, page_text),),
    )

    payload = producer.produce(_conversation())

    assert payload == {
        "kind": "answer",
        "text": _ANSWER,
        "citations": [_cited(stored)],
    }
    assert len(stored) == 269
    assert not stored.endswith("EXTRA-TAIL")


def test_search_includes_earlier_user_messages() -> None:
    producer, _, retriever = _producer(
        _completion(_ANSWER, [_cited()]),
        (_Hit(_DOC, _PAGE, _SNIPPET),),
    )
    conversation = Conversation(
        messages=[
            Message(role="user", text="earlier fake question"),
            Message(role="assistant", text="earlier reply"),
            Message(role="user", text=_QUESTION),
        ]
    )

    payload = producer.produce(conversation)

    assert retriever.queries == [f"earlier fake question {_QUESTION}"]
    assert "earlier reply" not in retriever.queries[0]
    assert payload == {
        "kind": "answer",
        "text": _ANSWER,
        "citations": [_cited()],
    }


def test_guard_checks_only_pages_that_survived_as_citations() -> None:
    spec_page = "FAKE-SPEC torque is 999 N·m."
    other_page = "FAKE-CHUNK: no number here."
    cited_other = _cited(other_page, page=998, doc_id="FAKE-OTHER")
    producer, _, _ = _producer(
        _completion("Torque is 999 Nm.", [cited_other]),
        (_Hit(_DOC, _PAGE, spec_page), _Hit("FAKE-OTHER", 998, other_page)),
    )
    conversation = _conversation("What is the FAKE-SPEC torque?")
    payload = producer.produce(conversation)
    response = TestClient(create_app(producer=producer)).post(
        "/chat",
        json={"messages": [{"role": "user", "text": "What is the FAKE-SPEC torque?"}]},
    )

    assert payload["citations"] == [cited_other]
    assert producer.cited_chunk_texts(conversation, payload) == (other_page,)
    assert response.status_code == 200
    body = response.json()
    assert body["kind"] == "refusal"
    assert "999 Nm" in body["text"]

    spec_page_with_tail = "FAKE-HEAD. FAKE-SPEC torque is 999 N·m."
    short_snippet = "FAKE-HEAD."
    kept_producer, _, _ = _producer(
        _completion("Torque is 999 Nm.", [_cited(short_snippet)]),
        (
            _Hit(_DOC, _PAGE, spec_page_with_tail),
            _Hit("FAKE-OTHER", 998, other_page),
        ),
    )
    kept_conversation = _conversation("What is the FAKE-SPEC torque?")
    kept_payload = kept_producer.produce(kept_conversation)
    kept = TestClient(create_app(producer=kept_producer)).post(
        "/chat",
        json={"messages": [{"role": "user", "text": "What is the FAKE-SPEC torque?"}]},
    )
    assert kept_payload["citations"] == [_cited(short_snippet)]
    assert "999" not in short_snippet
    assert kept_producer.cited_chunk_texts(kept_conversation, kept_payload) == (
        spec_page_with_tail,
    )
    assert kept.status_code == 200
    assert kept.json()["kind"] == "answer"
    assert kept.json()["text"] == "Torque is 999 Nm."


def test_newline_in_page_text_round_trips_through_the_prompt() -> None:
    page_text = "FAKE-LINE\nFAKE-SNIPPET: no real spec."
    producer, fake, _ = _producer(
        _completion(_ANSWER, [_cited(page_text)]),
        (_Hit(_DOC, _PAGE, page_text),),
    )

    payload = producer.produce(_conversation())

    rendered = _grounded_call(fake)[0].content.split("Retrieved pages:\n", 1)[1]
    decoded = json.loads(rendered)
    assert decoded == [{"doc_id": _DOC, "page": _PAGE, "text": page_text}]
    assert payload == {
        "kind": "answer",
        "text": _ANSWER,
        "citations": [_cited(page_text)],
    }


def test_missing_index_file_returns_general_advice(tmp_path: Path) -> None:
    fake = FakeLLMClient()
    producer = LlmAnswerProducer(
        fake, retriever=_IndexRetriever(tmp_path / "missing.sqlite")
    )

    payload = producer.produce(_conversation())

    assert payload == _advice()
    assert len(fake.calls) == 1
    assert "Retrieved pages:" not in fake.calls[0][0].content


def test_missing_index_with_a_bay_map_does_not_select_a_part(tmp_path: Path) -> None:
    fake = FakeLLMClient()
    bay_map = BayMapView(parts=(BayPartView(part_id="fake-part", regions=()),))
    producer = LlmAnswerProducer(
        fake,
        bay_map=bay_map,
        retriever=_IndexRetriever(tmp_path / "missing.sqlite"),
    )

    payload = producer.produce(_conversation())

    assert payload == _advice()
    assert "highlight" not in payload
    assert len(fake.calls) == 1

    empty = FakeLLMClient()
    empty_producer = LlmAnswerProducer(
        empty,
        bay_map=bay_map,
        retriever=_Retriever(()),
    )
    empty_payload = empty_producer.produce(_conversation())

    assert empty_payload == _advice()
    assert len(empty.calls) == 1


def test_corrupt_index_file_is_unavailable(tmp_path: Path) -> None:
    index_path = tmp_path / "index.sqlite"
    index_path.write_text("not a database", encoding="utf-8")
    fake = FakeLLMClient(text=_completion(_ANSWER, [_cited()]))
    producer = LlmAnswerProducer(fake, retriever=_IndexRetriever(index_path))

    payload = producer.produce(_conversation())

    assert payload == _UNAVAILABLE
    assert fake.calls == []


def test_fake_client_cited_answer_survives_provenance_filter() -> None:
    alpha = "FAKE-ALPHA page text."
    beta = "FAKE-BETA page text."
    fake = FakeLLMClient()
    producer = LlmAnswerProducer(
        fake,
        retriever=_Retriever(
            (
                _Hit("FAKE-DOC-2JZ", 999, alpha),
                _Hit("FAKE-DOC-LJ78", 999, beta),
            )
        ),
    )

    response = TestClient(create_app(producer=producer)).post(
        "/chat",
        json={"messages": [{"role": "user", "text": _QUESTION}]},
    )

    assert response.status_code == 200
    body = response.json()
    assert body == {
        "kind": "answer",
        "text": FAKE_GROUNDED_TEXT,
        "citations": [
            {"doc_id": "FAKE-DOC-2JZ", "page": 999, "snippet": alpha},
            {"doc_id": "FAKE-DOC-LJ78", "page": 999, "snippet": beta},
        ],
    }
    assert body["citations"][0]["snippet"] in alpha
    assert body["citations"][1]["snippet"] in beta


def test_fake_client_returns_general_advice_when_retrieval_is_empty() -> None:
    fake = FakeLLMClient()
    producer = LlmAnswerProducer(fake, retriever=_Retriever(()))

    response = TestClient(create_app(producer=producer)).post(
        "/chat",
        json={"messages": [{"role": "user", "text": _QUESTION}]},
    )

    assert response.status_code == 200
    assert response.json() == _advice()
    assert len(fake.calls) == 1


def test_keyless_chat_cites_an_indexed_fake_page(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    page_text = "FAKE-PAGE-TEXT\nwith no real spec."
    index_path = tmp_path / "index.sqlite"
    build_index(
        (Chunk(doc_id="FAKE-DOC-2JZ", page=999, text=page_text),),
        index_path,
    )
    monkeypatch.setattr("producer._index_path", lambda: index_path)
    monkeypatch.delenv("SIDEKICK_LLM_API_KEY", raising=False)

    response = TestClient(create_app()).post(
        "/chat",
        json={"messages": [{"role": "user", "text": "FAKE-PAGE-TEXT"}]},
    )

    assert response.status_code == 200
    body = response.json()
    assert body == {
        "kind": "answer",
        "text": FAKE_GROUNDED_TEXT,
        "citations": [
            {"doc_id": "FAKE-DOC-2JZ", "page": 999, "snippet": page_text},
        ],
    }
    assert body["citations"][0]["snippet"] in page_text


def test_keyless_chat_gives_general_advice_when_the_index_has_no_hits(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger="sidekick.llm")
    index_path = tmp_path / "index.sqlite"
    build_index(
        (
            Chunk(
                doc_id="FAKE-DOC-2JZ",
                page=999,
                text="FAKE-PAGE-TEXT with no real spec.",
            ),
        ),
        index_path,
    )
    monkeypatch.setattr("producer._index_path", lambda: index_path)
    monkeypatch.delenv("SIDEKICK_LLM_API_KEY", raising=False)

    response = TestClient(create_app()).post(
        "/chat",
        json={"messages": [{"role": "user", "text": "not-a-manual-term-zzzz"}]},
    )

    assert response.status_code == 200
    assert response.json() == _advice()
    assert "llm request" not in caplog.text


def test_keyless_chat_cites_the_indexed_manual_id(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    page_text = "FAKE-PAGE-TEXT with no real spec."
    index_path = tmp_path / "index.sqlite"
    build_index(
        (Chunk(doc_id="2jz-ge-rm", page=1, text=page_text),),
        index_path,
    )
    monkeypatch.setattr("producer._index_path", lambda: index_path)
    monkeypatch.delenv("SIDEKICK_LLM_API_KEY", raising=False)

    response = TestClient(create_app()).post(
        "/chat",
        json={"messages": [{"role": "user", "text": "FAKE-PAGE-TEXT"}]},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["citations"] == [
        {"doc_id": "2jz-ge-rm", "page": 1, "snippet": page_text},
    ]
    assert "FAKE-DOC" not in response.text


def test_wiring_miss_says_the_manual_is_not_ingested(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    index_path = tmp_path / "index.sqlite"
    build_index(
        (
            Chunk(
                doc_id="2jz-ge-rm",
                page=1,
                text="FAKE-PAGE-TEXT with no real spec.",
            ),
        ),
        index_path,
    )
    monkeypatch.setattr("producer._index_path", lambda: index_path)
    monkeypatch.delenv("SIDEKICK_LLM_API_KEY", raising=False)

    response = TestClient(create_app()).post(
        "/chat",
        json={"messages": [{"role": "user", "text": "where is the wiring harness"}]},
    )

    assert response.status_code == 200
    assert response.json() == WIRING_NOT_INGESTED_REFUSAL
    assert "LJ78" not in response.text
    assert "FAKE-DOC" not in response.text


def test_wiring_hit_still_cites_the_retrieved_manual(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    page_text = "FAKE-PAGE-TEXT wiring note with no real spec."
    index_path = tmp_path / "index.sqlite"
    build_index(
        (Chunk(doc_id="2jz-ge-rm", page=1, text=page_text),),
        index_path,
    )
    monkeypatch.setattr("producer._index_path", lambda: index_path)
    monkeypatch.delenv("SIDEKICK_LLM_API_KEY", raising=False)

    response = TestClient(create_app()).post(
        "/chat",
        json={"messages": [{"role": "user", "text": "wiring note"}]},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["citations"] == [
        {"doc_id": "2jz-ge-rm", "page": 1, "snippet": page_text},
    ]
    assert body["kind"] == "answer"


def test_engine_wiring_cites_is300_and_drops_other_docs(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    is300_text = "FAKE-PAGE-TEXT 25A EFI injector B-R wire."
    other_text = "FAKE-PAGE-TEXT injector procedure with no wiring."
    index_path = tmp_path / "index.sqlite"
    build_index(
        (
            Chunk(doc_id="2jz-ge-rm", page=1, text=other_text),
            Chunk(doc_id="is300-engine-wiring", page=2, text=is300_text),
        ),
        index_path,
    )
    monkeypatch.setattr("producer._index_path", lambda: index_path)
    monkeypatch.delenv("SIDEKICK_LLM_API_KEY", raising=False)

    response = TestClient(create_app()).post(
        "/chat",
        json={
            "messages": [
                {
                    "role": "user",
                    "text": "What fuse and wire color feed the 2JZ injectors?",
                }
            ]
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["kind"] == "answer"
    assert body["citations"] == [
        {"doc_id": "is300-engine-wiring", "page": 2, "snippet": is300_text},
    ]
    assert "2jz-ge-rm" not in response.text


def test_lj78_chassis_wiring_ignores_is300_hits(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    index_path = tmp_path / "index.sqlite"
    build_index(
        (
            Chunk(
                doc_id="is300-engine-wiring",
                page=1,
                text="FAKE-PAGE-TEXT 25A EFI RELAY fuse.",
            ),
        ),
        index_path,
    )
    monkeypatch.setattr("producer._index_path", lambda: index_path)
    monkeypatch.delenv("SIDEKICK_LLM_API_KEY", raising=False)

    response = TestClient(create_app()).post(
        "/chat",
        json={
            "messages": [
                {
                    "role": "user",
                    "text": "Which fuse feeds the LJ78 glow plug relay?",
                }
            ]
        },
    )

    assert response.status_code == 200
    assert response.json() == WIRING_NOT_INGESTED_REFUSAL
    assert "is300-engine-wiring" not in response.text
    assert "LJ78" not in response.text


def test_engine_wiring_miss_is_general_advice(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    index_path = tmp_path / "index.sqlite"
    build_index(
        (
            Chunk(
                doc_id="2jz-ge-rm",
                page=1,
                text="FAKE-PAGE-TEXT with no real spec.",
            ),
        ),
        index_path,
    )
    monkeypatch.setattr("producer._index_path", lambda: index_path)
    monkeypatch.delenv("SIDEKICK_LLM_API_KEY", raising=False)

    response = TestClient(create_app()).post(
        "/chat",
        json={
            "messages": [
                {
                    "role": "user",
                    "text": "Which ECM pins go to the ignition coils?",
                }
            ]
        },
    )

    assert response.status_code == 200
    assert response.json() == _advice()


def test_wiring_miss_is_general_advice_when_the_row_is_not_blocked(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    index_path = tmp_path / "index.sqlite"
    build_index(
        (
            Chunk(
                doc_id="2jz-ge-rm",
                page=1,
                text="FAKE-PAGE-TEXT with no real spec.",
            ),
        ),
        index_path,
    )
    monkeypatch.setattr("producer._index_path", lambda: index_path)
    monkeypatch.setattr("producer._wiring_manual_blocked", lambda: False)
    monkeypatch.delenv("SIDEKICK_LLM_API_KEY", raising=False)

    response = TestClient(create_app()).post(
        "/chat",
        json={"messages": [{"role": "user", "text": "where is the wiring harness"}]},
    )

    assert response.status_code == 200
    assert response.json() == _advice()


def test_index_retriever_cites_a_fake_chunk(tmp_path: Path) -> None:
    index_path = tmp_path / "index.sqlite"
    build_index(
        (Chunk(doc_id=_DOC, page=_PAGE, text=_SNIPPET),),
        index_path,
    )
    fake = FakeLLMClient(text=_completion(_ANSWER, [_cited()]))
    producer = LlmAnswerProducer(fake, retriever=_IndexRetriever(index_path))

    payload = producer.produce(_conversation("FAKE-SNIPPET"))

    assert payload == {
        "kind": "answer",
        "text": _ANSWER,
        "citations": [_cited()],
    }


def test_shared_word_is_not_answer_support() -> None:
    page = (
        "Vibration method. Wiggle the connector to find an intermittent "
        "electrical fault. FAKE-SPEC"
    )
    fake = FakeLLMClient()
    producer = LlmAnswerProducer(fake, retriever=_Retriever((_Hit(_DOC, 27, page),)))

    payload = producer.produce(_conversation("My truck shakes at highway speed"))

    assert payload["kind"] == "general_advice"
    assert payload["related"] == []
    assert all(
        "Retrieved pages:" not in turn.content for call in fake.calls for turn in call
    )


def test_squeal_cites_the_pad_page_and_not_a_different_job() -> None:
    pad = "FAKE-HEADING: front brake pad and anti-squeal shim."
    other = (
        "Vibration method. Wiggle the connector to find an intermittent "
        "electrical fault. FAKE-SPEC"
    )
    fake = FakeLLMClient()
    producer = LlmAnswerProducer(
        fake,
        retriever=_Retriever((_Hit(_DOC, 999, other), _Hit(_DOC, 1000, pad))),
    )

    payload = producer.produce(_conversation("The brakes squeal"))

    assert payload["kind"] == "answer"
    assert [item["page"] for item in payload["citations"]] == [1000]
    assert all(
        "Related page check:" not in turn.content
        for call in fake.calls
        for turn in call
    )


def test_a_cause_of_a_different_fault_is_not_the_answer() -> None:
    fan = "FAKE-HEADING: radiator fan does not spin."
    aside = (
        "DTC P9999 FAKE engine overcooling.\n"
        "Possible cause: abnormal radiator fan operation."
    )
    fake = FakeLLMClient()
    producer = LlmAnswerProducer(
        fake,
        retriever=_Retriever((_Hit(_DOC, 299, aside), _Hit(_DOC, 1000, fan))),
    )

    payload = producer.produce(_conversation("The radiator fan is not spinning"))

    assert payload["kind"] == "answer"
    assert [item["page"] for item in payload["citations"]] == [1000]
    assert all(
        "Related page check:" not in turn.content
        for call in fake.calls
        for turn in call
    )


def test_only_a_passing_cause_is_general_advice() -> None:
    aside = (
        "DTC P9999 FAKE engine overcooling.\n"
        "Possible cause: abnormal radiator fan operation."
    )
    fake = FakeLLMClient()
    producer = LlmAnswerProducer(
        fake, retriever=_Retriever((_Hit(_DOC, 299, aside),))
    )

    payload = producer.produce(_conversation("The radiator fan is not spinning"))

    assert payload["kind"] == "general_advice"
    assert payload["related"] == []
    assert all(
        "Retrieved pages:" not in turn.content for call in fake.calls for turn in call
    )


def test_undecided_pages_are_judged_together() -> None:
    first = (
        "FAKE-HEADING: inspection procedure.\nThe radiator fan relay is open."
    )
    second = (
        "FAKE-HEADING: inspection procedure.\nThe radiator fan relay is closed."
    )
    fake = FakeLLMClient()
    producer = LlmAnswerProducer(
        fake,
        retriever=_Retriever((_Hit(_DOC, 1, first), _Hit(_DOC, 2, second))),
    )

    payload = producer.produce(_conversation("The radiator fan is not spinning"))

    relevance = [
        call
        for call in fake.calls
        if any("Related page check:" in turn.content for turn in call)
    ]
    assert len(relevance) == 1
    assert payload["kind"] == "answer"
    assert [item["page"] for item in payload["citations"]] == [1, 2]


def test_citation_drops_a_page_that_lacks_the_stated_measurement() -> None:
    spec = "FAKE-SPEC torque is 999 N·m."
    neighbor = "FAKE-SPEC torque procedure for the fixture. No number here."
    producer, _, _ = _producer(
        _completion(
            "Torque is 999 Nm.",
            [_cited(spec), _cited(neighbor, page=1000)],
        ),
        (_Hit(_DOC, _PAGE, spec), _Hit(_DOC, 1000, neighbor)),
    )

    payload = producer.produce(_conversation("What is the FAKE-SPEC torque?"))

    assert payload["kind"] == "answer"
    assert [item["page"] for item in payload["citations"]] == [_PAGE]
