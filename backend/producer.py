"""Answer-producer seam. #15 replaces the fixture stub with a cloud LLM.

The spec guard does not read citation snippets. A producer that has
retrieved page text should also implement CitedChunkSource so POST /chat
can pass those strings to spec_guard.guard_answer.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any, Protocol, runtime_checkable

from chat_models import Conversation
from contract import load_answer_fixture

DEFAULT_FIXTURE = "plain.json"


class AnswerProducer(Protocol):
    def produce(self, conversation: Conversation) -> dict[str, Any]:
        """Return an answer payload that must match answer.schema.json."""


@runtime_checkable
class CitedChunkSource(Protocol):
    """Page text the spec guard may treat as evidence."""

    def cited_chunk_texts(self, conversation: Conversation) -> Sequence[str]:
        """Chunk texts retrieved for this conversation, one string per chunk."""


class FixtureAnswerProducer:
    """Returns a committed contract fixture. Does not call a model."""

    def __init__(self, fixture_name: str = DEFAULT_FIXTURE) -> None:
        self.fixture_name = fixture_name

    def produce(self, conversation: Conversation) -> dict[str, Any]:
        # Stub ignores the prompt until the #15 adapter exists.
        del conversation
        return load_answer_fixture(self.fixture_name)
