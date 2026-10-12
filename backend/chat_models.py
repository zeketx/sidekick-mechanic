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


class Conversation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    messages: list[Message] = Field(min_length=1)
    demo: DemoRequest | None = None

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
