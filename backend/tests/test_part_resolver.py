"""Part resolver: closed-list selection, unmapped parts, largest region."""

from __future__ import annotations

from typing import Any

import pytest

from chat_models import Conversation, Message
from contract import validate_answer
from llm import ChatTurn, FakeLLMClient, LLMError, LLMResult
from part_resolver import (
    NOT_MAPPED_SENTENCE,
    SELECTION_SYSTEM,
    BayMapView,
    BayPartView,
    PartRegionView,
    ResolutionKind,
    SelectionKind,
    largest_confirmed_region,
    parse_selection,
    resolve_answer,
    resolve_part,
    selection_messages,
)
from producer import LlmAnswerProducer, SYSTEM_PROMPT


def _region(
    photo: str,
    angle: str,
    area: int,
    *,
    confirmed: bool = True,
) -> PartRegionView:
    return PartRegionView(
        bay_photo_id=photo,
        angle_id=angle,
        area_px=area,
        confirmed=confirmed,
    )


def _intake_map() -> BayMapView:
    return BayMapView(
        parts=(
            BayPartView(
                part_id="fake-part-intake",
                regions=(
                    _region("fake-bay-photo-aaa", "fake-angle-close", 10),
                    _region("fake-bay-photo-wide", "fake-angle-wide", 80),
                    _region(
                        "fake-bay-photo-huge", "fake-angle-huge", 500, confirmed=False
                    ),
                ),
            ),
            BayPartView(
                part_id="fake-part-unmapped",
                regions=(
                    _region(
                        "fake-bay-photo-orphan",
                        "fake-angle-orphan",
                        400,
                        confirmed=False,
                    ),
                ),
            ),
            BayPartView(part_id="fake-part-other", regions=()),
        )
    )


def _answer(
    text: str = "Check the FAKE intake on the fixture photo.",
) -> dict[str, Any]:
    return {
        "kind": "answer",
        "text": text,
        "citations": [
            {
                "doc_id": "FAKE-DOC",
                "page": 999,
                "snippet": "FAKE-SNIPPET",
            }
        ],
    }


def test_llm_selection_accepts_closed_list_id_or_null() -> None:
    bay_map = _intake_map()

    chosen = parse_selection('{"part_id": "fake-part-intake"}', bay_map)
    none = parse_selection('{"part_id": null}', bay_map)
    fenced = parse_selection(
        '```json\n{"part_id": "fake-part-other"}\n```',
        bay_map,
    )

    assert chosen.kind is SelectionKind.PART
    assert chosen.part_id == "fake-part-intake"
    assert none.kind is SelectionKind.NONE
    assert none.part_id is None
    assert fenced.kind is SelectionKind.PART
    assert fenced.part_id == "fake-part-other"


def test_prompt_lists_every_closed_id_and_null() -> None:
    bay_map = _intake_map()
    messages = selection_messages(answer_text="FAKE answer text.", bay_map=bay_map)

    assert messages[0] == ChatTurn(role="system", content=SELECTION_SYSTEM)
    assert "null" in SELECTION_SYSTEM
    user = messages[1].content
    for part_id in bay_map.part_ids():
        assert f"\n{part_id}\n" in f"\n{user}\n"
    assert "FAKE answer text." in user
    assert "N·m" not in SELECTION_SYSTEM
    assert "89661" not in user


def test_photo_is_the_angle_with_the_largest_confirmed_region() -> None:
    bay_map = _intake_map()
    resolution = resolve_part('{"part_id": "fake-part-intake"}', bay_map)
    payload = resolve_answer(_answer(), '{"part_id": "fake-part-intake"}', bay_map)

    assert resolution.kind is ResolutionKind.HIGHLIGHT
    assert resolution.part_id == "fake-part-intake"
    assert resolution.bay_photo_id == "fake-bay-photo-wide"
    assert resolution.angle_id == "fake-angle-wide"
    validate_answer(payload)
    assert payload["highlight"] == {
        "bay_photo_id": "fake-bay-photo-wide",
        "part_id": "fake-part-intake",
    }
    assert NOT_MAPPED_SENTENCE not in payload["text"]
    assert payload["citations"][0]["page"] == 999


def test_equal_area_uses_lower_photo_id() -> None:
    part = BayPartView(
        part_id="fake-part-intake",
        regions=(
            _region("fake-bay-photo-b", "fake-angle-b", 40),
            _region("fake-bay-photo-a", "fake-angle-z", 40),
        ),
    )
    region = largest_confirmed_region(part)

    assert region is not None
    assert region.bay_photo_id == "fake-bay-photo-a"
    assert region.angle_id == "fake-angle-z"


def test_unknown_part_has_no_highlight_and_says_not_mapped() -> None:
    original = _answer()
    payload = resolve_answer(
        original, '{"part_id": "fake-part-missing"}', _intake_map()
    )

    validate_answer(payload)
    assert "highlight" not in payload
    assert payload["text"] == f"{original['text']} {NOT_MAPPED_SENTENCE}"
    assert original["text"] == "Check the FAKE intake on the fixture photo."
    assert resolve_part('{"part_id": "fake-part-missing"}', _intake_map()).kind is (
        ResolutionKind.NOT_MAPPED
    )


def test_unmapped_part_has_no_highlight_and_says_not_mapped() -> None:
    payload = resolve_answer(
        _answer(), '{"part_id": "fake-part-unmapped"}', _intake_map()
    )

    validate_answer(payload)
    assert "highlight" not in payload
    assert payload["text"].endswith(NOT_MAPPED_SENTENCE)
    assert resolve_part('{"part_id": "fake-part-other"}', _intake_map()).kind is (
        ResolutionKind.NOT_MAPPED
    )


def test_unmapped_sentence_is_not_repeated() -> None:
    text = f"Already noted. {NOT_MAPPED_SENTENCE}"
    payload = resolve_answer(
        _answer(text), '{"part_id": "fake-part-other"}', _intake_map()
    )

    assert payload["text"].count(NOT_MAPPED_SENTENCE) == 1


def test_ambiguous_parts_leave_no_highlight() -> None:
    bay_map = _intake_map()
    original = _answer()
    cases = (
        '{"part_id": ["fake-part-intake", "fake-part-other"]}',
        "fake-part-intake or fake-part-other",
        '{"part_id": "fake-part-intake", "alt": "fake-part-other"}',
    )

    for raw in cases:
        resolution = resolve_part(raw, bay_map)
        payload = resolve_answer(original, raw, bay_map)
        assert resolution.kind is ResolutionKind.AMBIGUOUS
        assert resolution.part_id is None
        validate_answer(payload)
        assert "highlight" not in payload
        assert payload["text"] == original["text"]
        assert NOT_MAPPED_SENTENCE not in payload["text"]


def test_explicit_null_drops_any_highlight() -> None:
    original = _answer()
    original["highlight"] = {
        "bay_photo_id": "fake-bay-photo-aaa",
        "part_id": "fake-part-intake",
    }
    payload = resolve_answer(original, '{"part_id": null}', _intake_map())

    validate_answer(payload)
    assert "highlight" not in payload
    assert payload["text"] == "Check the FAKE intake on the fixture photo."
    assert original["highlight"]["part_id"] == "fake-part-intake"
    assert resolve_part('{"part_id": null}', _intake_map()).kind is ResolutionKind.NONE


def test_refusal_never_gains_a_highlight() -> None:
    refusal = {
        "kind": "refusal",
        "text": "Not found in the manual.",
        "reason": "not_found_in_manual",
        "highlight": {
            "bay_photo_id": "fake-bay-photo-wide",
            "part_id": "fake-part-intake",
        },
    }
    payload = resolve_answer(refusal, '{"part_id": "fake-part-intake"}', _intake_map())

    validate_answer(payload)
    assert payload == {
        "kind": "refusal",
        "text": "Not found in the manual.",
        "reason": "not_found_in_manual",
    }


def test_zero_area_confirmed_region_is_unmapped() -> None:
    bay_map = BayMapView(
        parts=(
            BayPartView(
                part_id="fake-part-intake",
                regions=(_region("fake-bay-photo-flat", "fake-angle-flat", 0),),
            ),
        )
    )
    payload = resolve_answer(_answer(), '{"part_id": "fake-part-intake"}', bay_map)

    assert "highlight" not in payload
    assert payload["text"].endswith(NOT_MAPPED_SENTENCE)


def test_view_rejects_duplicate_and_empty_ids() -> None:
    with pytest.raises(ValueError, match="duplicate part_id"):
        BayMapView(
            parts=(
                BayPartView(part_id="fake-part-intake", regions=()),
                BayPartView(part_id="fake-part-intake", regions=()),
            )
        )
    with pytest.raises(ValueError, match="part_id"):
        BayPartView(part_id=" fake-part-intake", regions=())
    with pytest.raises(ValueError, match="area_px"):
        _region("fake-bay-photo-a", "fake-angle-a", -1)
    with pytest.raises(ValueError, match="area_px"):
        PartRegionView(
            bay_photo_id="fake-bay-photo-a",
            angle_id="fake-angle-a",
            area_px=True,  # type: ignore[arg-type]
            confirmed=True,
        )


class _ScriptedLLM:
    def __init__(self, results: list[LLMResult | Exception]) -> None:
        self._results = list(results)
        self.calls: list[list[ChatTurn]] = []

    def complete(self, messages: list[ChatTurn]) -> LLMResult:
        self.calls.append(list(messages))
        item = self._results.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


def _result(text: str) -> LLMResult:
    return LLMResult(text=text, model="fake", usage=None)


def test_producer_without_a_map_does_not_select_a_part() -> None:
    fake = FakeLLMClient(text="FAKE reply with no specs.")
    payload = LlmAnswerProducer(fake, bay_map=BayMapView(parts=())).produce(
        Conversation(messages=[Message(role="user", text="Where is the FAKE intake?")])
    )

    validate_answer(payload)
    assert len(fake.calls) == 1
    assert "highlight" not in payload
    assert NOT_MAPPED_SENTENCE not in payload["text"]


def test_producer_asks_the_model_for_a_closed_list_id() -> None:
    client = _ScriptedLLM(
        [
            _result("Check the FAKE intake on the fixture photo."),
            _result('{"part_id": "fake-part-intake"}'),
        ]
    )
    payload = LlmAnswerProducer(client, bay_map=_intake_map()).produce(
        Conversation(messages=[Message(role="user", text="Where is the FAKE intake?")])
    )

    validate_answer(payload)
    assert payload["highlight"]["part_id"] == "fake-part-intake"
    assert payload["highlight"]["bay_photo_id"] == "fake-bay-photo-wide"
    assert client.calls[0][0].content == SYSTEM_PROMPT
    assert "fake-part-unmapped" in client.calls[1][1].content
    assert "fake-part-intake" in client.calls[1][1].content


def test_producer_selection_failure_omits_highlight(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level("WARNING")
    client = _ScriptedLLM(
        [
            _result("Check the FAKE intake on the fixture photo."),
            LLMError("selection timed out"),
        ]
    )
    payload = LlmAnswerProducer(client, bay_map=_intake_map()).produce(
        Conversation(messages=[Message(role="user", text="Where is the FAKE intake?")])
    )

    validate_answer(payload)
    assert "highlight" not in payload
    assert NOT_MAPPED_SENTENCE not in payload["text"]
    assert "part selection failed" in caplog.text


def test_stripped_part_id_still_matches_the_closed_list() -> None:
    chosen = parse_selection('{"part_id": " fake-part-intake "}', _intake_map())

    assert chosen.kind is SelectionKind.PART
    assert chosen.part_id == "fake-part-intake"
