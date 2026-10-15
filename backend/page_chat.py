"""Answer the newest user turn about one manual page.

The server loads the page text. That string is the spec guard's only evidence
and the only source a citation may copy. Garage notes may be mentioned. They
are not a manual page. The client never sends page text. A page answer never
carries a highlight.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from chat_models import Conversation, PageRef, garage_prompt_block
from go_deeper import excerpt_around_snippet
from llm import ChatTurn, LLMClient, LLMError, log_llm_failure
from plug_check import check_plug, render_verdict
from producer import UNAVAILABLE_ANSWER

PAGE_TEXT_HEADER = "Manual page text:\n"
SNIPPET_LIMIT = 300

PAGE_EXPLAIN_INSTRUCTIONS = (
    "You are Sidekick Mechanic. You are explaining one repair manual page to "
    "someone who has never worked on an engine. "
    "Say what the page is for and what each step tells them to do, in everyday "
    "words, and why the step matters. "
    "When you name a tool, say what it is, what it looks like, and what it does. "
    "When you use a shop word, explain it in the same sentence. "
    "Use only the page text below for facts about the truck. Do not add a torque, "
    "a pin number, a wire color, or a part number that the page text does not print. "
    "If the page text does not answer the question, say so. "
    "If the page does not name one connector, say that. Do not pick one. "
    "Write plain sentences. No JSON."
)

PAGE_UNREADABLE_REFUSAL: dict[str, Any] = {
    "kind": "refusal",
    "text": "I can't read the text on this page, so I can't explain it.",
    "reason": "not_found_in_manual",
}


def answer_about_page(
    conversation: Conversation,
    page: PageRef,
    page_text: str | None,
    *,
    llm: LLMClient,
    vision: LLMClient | None,
    page_image: Callable[[], bytes | None],
) -> dict[str, Any]:
    """A plug photo turn gets the plug verdict. Any other page turn gets the plain explanation.

    ``page_image`` is only called for a plug photo, so an explain turn does not rasterize.
    """
    last = conversation.last_user_message
    question = last.text if last is not None else ""
    text = (page_text or "").strip()
    citations = _page_citation(page, text, question)

    if last is not None and last.photo is not None:
        verdict = check_plug(
            last.photo.data, page_png=page_image(), page_text=text, vision=vision
        )
        return {"kind": "answer", "text": render_verdict(verdict), "citations": citations}

    if not text:
        return dict(PAGE_UNREADABLE_REFUSAL)
    reply = _explain(conversation, text, llm)
    if reply is None:
        return dict(UNAVAILABLE_ANSWER)
    return {"kind": "answer", "text": reply, "citations": citations}


def _explain(conversation: Conversation, page_text: str, llm: LLMClient) -> str | None:
    parts = [PAGE_EXPLAIN_INSTRUCTIONS]
    block = garage_prompt_block(conversation.garage)
    if block:
        parts.append(block)
    parts.append(f"{PAGE_TEXT_HEADER}{page_text}")
    system = "\n\n".join(parts)
    turns = [ChatTurn(role="system", content=system)]
    turns.extend(ChatTurn(role=m.role, content=m.text) for m in conversation.messages)
    try:
        result = llm.complete(turns)
    except LLMError as exc:
        log_llm_failure(exc)
        return None
    reply = result.text.strip()
    if not reply or reply.startswith(("{", "[", "```")):
        return None
    return reply


def _page_citation(page: PageRef, page_text: str, question: str) -> list[dict[str, Any]]:
    """One citation, its snippet copied from the page text. None for a page with no text."""
    if not page_text:
        return []
    snippet = excerpt_around_snippet(page_text, question) or _head(page_text)
    return [{"doc_id": page.doc_id, "page": page.page, "snippet": snippet}]


def _head(page_text: str) -> str:
    flat = " ".join(page_text.split())
    if len(flat) <= SNIPPET_LIMIT:
        return flat
    return flat[:SNIPPET_LIMIT].rsplit(" ", 1)[0] + "…"
