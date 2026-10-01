"""Answer-producer seam. #15 replaces the fixture stub with a cloud LLM."""

from __future__ import annotations

from typing import Any, Protocol

from chat_models import Conversation
from contract import load_answer_fixture

DEFAULT_FIXTURE = "plain.json"


class AnswerProducer(Protocol):
    def produce(self, conversation: Conversation) -> dict[str, Any]:
        """Return an answer payload that must match answer.schema.json."""


class FixtureAnswerProducer:
    """Returns a committed contract fixture. Does not call a model."""

    def __init__(self, fixture_name: str = DEFAULT_FIXTURE) -> None:
        self.fixture_name = fixture_name

    def produce(self, conversation: Conversation) -> dict[str, Any]:
        # Stub ignores the prompt until the #15 adapter exists.
        del conversation
        return load_answer_fixture(self.fixture_name)
