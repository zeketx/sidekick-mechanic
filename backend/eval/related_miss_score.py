from __future__ import annotations

import json
import statistics
from dataclasses import dataclass

from chat_models import Conversation, Message
from general_advice import advise_on_miss
from llm import FakeLLMClient

_RUNS = 5
_STEP = "FAKE-STEP: check the fixture relay."
_OIL = (
    "FAKE-HEADING: AUTOMATIC TRANSMISSION FAKE-AT-OIL-COOLER union nuts. "
    "Do not spend time turning them. Check the union before you look again."
)
_FAN = "FAKE-HEADING: COOLING FAN FAKE-FAN-RELAY wiring."
_MOTOR = "FAKE-HEADING: the fixture motor can stumble on the bench."
_RADIATOR = "FAKE-HEADING: radiator leaking coolant at the driveway."
_LATE_FAN = (
    "FAKE-HEADING: AUTOMATIC TRANSMISSION FAKE-AT-OIL-COOLER union nuts. "
    + ("FAKE-PAD " * 40)
    + "fan"
)
_SPEED_AT = "FAKE-HEADING: A/T vehicle speed sensor circuit."
_SPEED_BRAKE = "FAKE-HEADING: brake speed sensor on the fixture axle."
_SPEED_REAR = "FAKE-HEADING: rear brake speed sensor resistance."
_SHAKE = (
    "FAKE-HEADING: the truck shakes at highway speed when a wheel is out of balance."
)
_SHAKE_BENCH = "FAKE-HEADING: truck shakes at highway speed on the fixture bench."
_KNOCK_SENSOR = "FAKE-HEADING: knock sensor circuit inspection."
_KNOCK = "FAKE-HEADING: the engine knocks when you accelerate under load."
_SPEED_ONLY = "FAKE-HEADING: vehicle speed sensor."
_BRAKE_FLUID = "FAKE-HEADING: brake fluid level on the fixture."
_SQUEAL = "FAKE-HEADING: the brakes squeal at low speed on the fixture."
_SQUEAL_SHORT = "FAKE-HEADING: the brakes squeal."
_PAD = "FAKE-HEADING: brake pad."
_SHIM = "FAKE-HEADING: anti-squeal shim."
_ALIGN = "FAKE-HEADING: steering wheel alignment specification."
_VIBRATE = "FAKE-HEADING: the steering wheel vibrates on the freeway."


@dataclass(frozen=True)
class LabeledPage:
    doc_id: str
    page: int
    text: str
    on_topic: bool


@dataclass(frozen=True)
class MissCase:
    case_id: str
    question: str
    pages: tuple[LabeledPage, ...]
    shared_word_miss: bool


@dataclass(frozen=True)
class _Hit:
    doc_id: str
    page: int
    text: str


def _page(doc_id: str, text: str, *, on_topic: bool, page: int = 999) -> LabeledPage:
    return LabeledPage(doc_id=doc_id, page=page, text=text, on_topic=on_topic)


def cases() -> tuple[MissCase, ...]:
    return (
        MissCase(
            "fan_oil_only",
            "My automatic fan is not turning on at start time",
            (_page("FAKE-DOC", _OIL, on_topic=False),),
            shared_word_miss=False,
        ),
        MissCase(
            "fan_keeps_the_fan_page",
            "My automatic fan is not turning on at start time",
            (
                _page("FAKE-DOC", _OIL, on_topic=False),
                _page("FAKE-DOC-FAN", _FAN, on_topic=True),
            ),
            shared_word_miss=False,
        ),
        MissCase(
            "motor_keeps_the_motor_page",
            "Why does the fixture motor stumble?",
            (
                _page("FAKE-DOC", _OIL, on_topic=False),
                _page("FAKE-DOC-MOTOR", _MOTOR, on_topic=True),
            ),
            shared_word_miss=False,
        ),
        MissCase(
            "radiator_keeps_the_page_without_onto",
            "The radiator is leaking coolant onto the driveway",
            (
                _page("FAKE-DOC", _OIL, on_topic=False),
                _page("FAKE-DOC-RADIATOR", _RADIATOR, on_topic=True),
            ),
            shared_word_miss=False,
        ),
        MissCase(
            "fan_past_the_prefix",
            "My automatic fan is not turning on at start time",
            (_page("FAKE-DOC", _LATE_FAN, on_topic=False),),
            shared_word_miss=False,
        ),
        MissCase(
            "highway_symptom_page_alone",
            "My truck shakes at highway speed",
            (_page("FAKE-DOC-SHAKE", _SHAKE, on_topic=True),),
            shared_word_miss=False,
        ),
        MissCase(
            "highway_speed_sensors_only",
            "My truck shakes at highway speed",
            (
                _page("FAKE-DOC-AT-SPEED", _SPEED_AT, on_topic=False),
                _page("FAKE-DOC-BRAKE-SPEED", _SPEED_BRAKE, on_topic=False),
                _page("FAKE-DOC-REAR-SPEED", _SPEED_REAR, on_topic=False),
            ),
            shared_word_miss=True,
        ),
        MissCase(
            "highway_keeps_the_shake_page",
            "My truck shakes at highway speed",
            (
                _page("FAKE-DOC-AT-SPEED", _SPEED_AT, on_topic=False),
                _page("FAKE-DOC-BRAKE-SPEED", _SPEED_BRAKE, on_topic=False),
                _page("FAKE-DOC-REAR-SPEED", _SPEED_REAR, on_topic=False),
                _page("FAKE-DOC-SHAKE", _SHAKE, on_topic=True),
            ),
            shared_word_miss=True,
        ),
        MissCase(
            "highway_two_shake_pages",
            "My truck shakes at highway speed",
            (
                _page("FAKE-DOC-AT-SPEED", _SPEED_AT, on_topic=False),
                _page("FAKE-DOC-SHAKE", _SHAKE, on_topic=True),
                _page("FAKE-DOC-SHAKE-BENCH", _SHAKE_BENCH, on_topic=True),
            ),
            shared_word_miss=True,
        ),
        MissCase(
            "knock_sensor_is_not_the_knock",
            "The engine knocks when I accelerate",
            (
                _page("FAKE-DOC-KNOCK-SENSOR", _KNOCK_SENSOR, on_topic=False),
                _page("FAKE-DOC-KNOCK", _KNOCK, on_topic=True),
            ),
            shared_word_miss=True,
        ),
        MissCase(
            "squeal_is_not_a_speed_or_fluid_page",
            "My brakes squeal at low speed",
            (
                _page("FAKE-DOC-SPEED", _SPEED_ONLY, on_topic=False),
                _page("FAKE-DOC-FLUID", _BRAKE_FLUID, on_topic=False),
                _page("FAKE-DOC-SQUEAL", _SQUEAL, on_topic=True),
            ),
            shared_word_miss=True,
        ),
        MissCase(
            "vibration_is_not_alignment",
            "The steering wheel vibrates on the freeway",
            (
                _page("FAKE-DOC-ALIGN", _ALIGN, on_topic=False),
                _page("FAKE-DOC-VIBRATE", _VIBRATE, on_topic=True),
            ),
            shared_word_miss=True,
        ),
        MissCase(
            "alignment_alone_is_not_vibration",
            "The steering wheel vibrates on the freeway",
            (_page("FAKE-DOC-ALIGN", _ALIGN, on_topic=False),),
            shared_word_miss=True,
        ),
        MissCase(
            "short_squeal_page_is_the_symptom",
            "My brakes squeal at low speed",
            (_page("FAKE-DOC-SQUEAL-SHORT", _SQUEAL_SHORT, on_topic=True),),
            shared_word_miss=True,
        ),
        MissCase(
            "squeal_drops_speed_sensor_and_alignment",
            "My brakes squeal at low speed",
            (
                _page("FAKE-DOC-SPEED", _SPEED_ONLY, on_topic=False),
                _page("FAKE-DOC-ALIGN", _ALIGN, on_topic=False),
                _page("FAKE-DOC-SQUEAL-SHORT", _SQUEAL_SHORT, on_topic=True),
            ),
            shared_word_miss=True,
        ),
        MissCase(
            "squeal_keeps_the_pad_and_the_shim",
            "Brakes squeal at low speed",
            (
                _page("FAKE-DOC-PAD", _PAD, on_topic=True),
                _page("FAKE-DOC-SHIM", _SHIM, on_topic=True),
                _page("FAKE-DOC-SPEED", _SPEED_ONLY, on_topic=False),
            ),
            shared_word_miss=True,
        ),
        MissCase(
            "highway_shake_drops_the_speed_sensors",
            "My truck shakes at highway speed",
            (
                _page("FAKE-DOC-AT-SPEED", _SPEED_AT, on_topic=False),
                _page("FAKE-DOC-BRAKE-SPEED", _SPEED_BRAKE, on_topic=False),
                _page("FAKE-DOC-REAR-SPEED", _SPEED_REAR, on_topic=False),
            ),
            shared_word_miss=True,
        ),
    )


@dataclass(frozen=True)
class Score:
    related_errors: int
    off_topic_shown: int
    on_topic_missed: int
    order_errors: int
    pages_judged: int
    shared_word_miss_errors: int
    other_errors: int
    lines: tuple[str, ...]


def score_once() -> Score:
    off_topic_shown = 0
    on_topic_missed = 0
    order_errors = 0
    pages_judged = 0
    shared_word_miss_errors = 0
    other_errors = 0
    lines: list[str] = []
    for case in cases():
        shown, missed, order = _case_errors(case)
        case_errors = shown + missed + order
        off_topic_shown += shown
        on_topic_missed += missed
        order_errors += order
        pages_judged += len(case.pages)
        if case.shared_word_miss:
            shared_word_miss_errors += case_errors
        else:
            other_errors += case_errors
        lines.append(
            f"case {case.case_id} shared_word_miss {case.shared_word_miss} "
            f"off_shown {shown} missed {missed} order {order}"
        )
    return Score(
        related_errors=off_topic_shown + on_topic_missed + order_errors,
        off_topic_shown=off_topic_shown,
        on_topic_missed=on_topic_missed,
        order_errors=order_errors,
        pages_judged=pages_judged,
        shared_word_miss_errors=shared_word_miss_errors,
        other_errors=other_errors,
        lines=tuple(lines),
    )


def _case_errors(case: MissCase) -> tuple[int, int, int]:
    payload = advise_on_miss(
        FakeLLMClient(text=json.dumps({"steps": [_STEP]})),
        Conversation(messages=[Message(role="user", text=case.question)]),
        tuple(_Hit(page.doc_id, page.page, page.text) for page in case.pages),
    )
    if payload is None:
        return (len(case.pages), len(case.pages), 0)
    returned = [
        (item["doc_id"], item["page"])
        for item in payload["related"]
        if isinstance(item, dict)
    ]
    on_topic = [(page.doc_id, page.page) for page in case.pages if page.on_topic]
    off_topic = {(page.doc_id, page.page) for page in case.pages if not page.on_topic}
    on_set = set(on_topic)
    shown = sum(1 for key in returned if key in off_topic or key not in on_set)
    missed = sum(1 for key in on_topic if key not in returned)
    actual_on = [key for key in returned if key in on_set]
    order = 1 if set(actual_on) == on_set and actual_on != on_topic else 0
    return (shown, missed, order)


def main() -> None:
    scores = [score_once() for _ in range(_RUNS)]
    errors = [score.related_errors for score in scores]
    shown = [score.off_topic_shown for score in scores]
    missed = [score.on_topic_missed for score in scores]
    first = scores[0]
    print(f"runs {_RUNS}")
    print(f"related_errors_median {statistics.median(errors)}")
    print(f"related_errors_min {min(errors)}")
    print(f"related_errors_max {max(errors)}")
    print(f"off_topic_shown_median {statistics.median(shown)}")
    print(f"on_topic_missed_median {statistics.median(missed)}")
    print(f"order_errors {first.order_errors}")
    print(f"pages_judged {first.pages_judged}")
    print(f"cases {len(cases())}")
    print(f"shared_word_miss_errors {first.shared_word_miss_errors}")
    print(f"other_errors {first.other_errors}")
    for line in first.lines:
        print(line)


if __name__ == "__main__":
    main()
