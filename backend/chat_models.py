"""Request types for POST /chat. The response shape is answer.schema.json."""

from __future__ import annotations

from typing import Literal

from pydantic import Base64Bytes, BaseModel, ConfigDict, Field, field_validator, model_validator

PLUG_PHOTO_MAX_BYTES = 3_000_000
_JPEG_SIGNATURE = b"\xff\xd8\xff"


class PageRef(BaseModel):
    """Which manual page a user turn is about. Identity only: the server loads the text."""

    model_config = ConfigDict(extra="forbid")

    doc_id: str = Field(min_length=1, max_length=128, pattern=r"^[A-Za-z0-9._-]+$")
    page: int = Field(ge=1, strict=True)


class PlugPhoto(BaseModel):
    """The owner's photo of a plug, base64 JPEG, downscaled on the phone."""

    model_config = ConfigDict(extra="forbid")

    media_type: Literal["image/jpeg"]
    data: Base64Bytes = Field(repr=False)

    @field_validator("data")
    @classmethod
    def _small_jpeg(cls, value: bytes) -> bytes:
        if len(value) > PLUG_PHOTO_MAX_BYTES:
            raise ValueError("photo is too large")
        if not value.startswith(_JPEG_SIGNATURE):
            raise ValueError("photo is not a JPEG")
        return value


class Message(BaseModel):
    model_config = ConfigDict(extra="forbid")

    role: Literal["user", "assistant"]
    text: str = Field(min_length=1)
    page: PageRef | None = None
    photo: PlugPhoto | None = None

    @model_validator(mode="after")
    def _attachments_ride_user_page_turns(self) -> Message:
        if self.role != "user" and (self.page is not None or self.photo is not None):
            raise ValueError("only a user turn can carry a page or a photo")
        if self.photo is not None and self.page is None:
            raise ValueError("a plug photo needs a page")
        return self


class DemoRequest(BaseModel):
    """Optional demo-mode context. Omit on the normal path."""

    model_config = ConfigDict(extra="forbid")

    photo_id: str = Field(min_length=1)


# Keep the garage prompt short. Long notes are cut. Extras are dropped.
MAX_GARAGE_FACTS = 24
MAX_GARAGE_NOTES = 16
MAX_GARAGE_TODOS = 16
MAX_GARAGE_FIELD_CHARS = 180
MAX_GARAGE_PROMPT_CHARS = 1800

GARAGE_PROMPT_HEADER = "Owner garage notes (saved on the phone; not a manual page):"
GARAGE_PROMPT_FOOTER = (
    "You may mention these notes when they help (for example, that a harness "
    "is already replaced). They are not evidence for torque values, pinouts, "
    "wire colors, or other specs. Do not cite them as a manual page."
)


class GarageFactContext(BaseModel):
    model_config = ConfigDict(extra="forbid")

    label: str = Field(min_length=1)
    value: str = Field(min_length=1)


class GarageNoteContext(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1)
    note: str = ""


class GarageTodoContext(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1)


class GarageContext(BaseModel):
    """Compact garage summary from the phone. Omit when there is nothing to send."""

    model_config = ConfigDict(extra="forbid")

    facts: list[GarageFactContext] = Field(default_factory=list)
    notes: list[GarageNoteContext] = Field(default_factory=list)
    open_todos: list[GarageTodoContext] = Field(default_factory=list)


class Conversation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    messages: list[Message] = Field(min_length=1)
    demo: DemoRequest | None = None
    garage: GarageContext | None = None

    @model_validator(mode="after")
    def _photo_last_and_page_without_demo(self) -> Conversation:
        if any(message.photo is not None for message in self.messages[:-1]):
            raise ValueError("only the last message can carry a photo")
        if self.demo is not None and self.page is not None:
            raise ValueError("a page turn does not take a demo photo")
        return self

    @property
    def last_user_message(self) -> Message | None:
        return next((m for m in reversed(self.messages) if m.role == "user"), None)

    @property
    def page(self) -> PageRef | None:
        """The page the newest user turn is about. None takes the general path."""
        last = self.last_user_message
        return last.page if last is not None else None


def _trim_field(text: str, limit: int = MAX_GARAGE_FIELD_CHARS) -> str:
    cleaned = " ".join(text.split())
    if len(cleaned) <= limit:
        return cleaned
    if limit <= 1:
        return cleaned[:limit]
    return cleaned[: limit - 1].rstrip() + "…"


def garage_prompt_block(garage: GarageContext | None) -> str:
    """Plain-language garage notes for the system prompt, or empty if none."""

    if garage is None:
        return ""

    lines: list[str] = []
    facts = [
        fact
        for fact in garage.facts[:MAX_GARAGE_FACTS]
        if fact.label.strip() and fact.value.strip()
    ]
    if facts:
        lines.append("Facts:")
        for fact in facts:
            lines.append(f"- {_trim_field(fact.label)}: {_trim_field(fact.value)}")

    notes = [note for note in garage.notes[:MAX_GARAGE_NOTES] if note.name.strip()]
    if notes:
        lines.append("Notes:")
        for note in notes:
            name = _trim_field(note.name)
            detail = _trim_field(note.note)
            lines.append(f"- {name}: {detail}" if detail else f"- {name}")

    todos = [
        todo for todo in garage.open_todos[:MAX_GARAGE_TODOS] if todo.title.strip()
    ]
    if todos:
        lines.append("Open to-dos:")
        for todo in todos:
            lines.append(f"- {_trim_field(todo.title)}")

    if not lines:
        return ""

    rendered = "\n".join([GARAGE_PROMPT_HEADER, *lines, "", GARAGE_PROMPT_FOOTER])
    if len(rendered) <= MAX_GARAGE_PROMPT_CHARS:
        return rendered
    cutoff = MAX_GARAGE_PROMPT_CHARS - 1
    return rendered[:cutoff].rstrip() + "…"
