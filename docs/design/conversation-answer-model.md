# Conversation and answer data model

## Problem

Chat, citations, highlights, eval, and `POST /chat` all need one answer shape. Issue #9 asked for that shape in `SidekickCore` before UI or backend logic. While this design was in progress, issue #10 merged `backend/contracts/answer.schema.json` and four fixtures. The Swift types have to decode those fixtures and still make illegal states unrepresentable.

## Usage (caller's view)

The chat screen holds a `Conversation` and appends turns:

```swift
let conversation = Conversation(id: conversationID)
    .appending(.user(userMessage))
    .appending(.assistant(AssistantMessage(id: replyID, answer: decoded)))
```

The answer card reads `AnswerCardContent`, built from `Answer`:

```swift
let card = AnswerCardContent(answer: answer)
// card.text
// card.chips[].label  — document id and page
// card.statusTitle     — "Not found in the manual", or nil when found
// card.showsHighlightSlot
```

The network client and eval decode the #10 fixtures with `JSONDecoder().decode(Answer.self, from: data)`. They do not map through a second wire type.

## Shape

`Answer` is a sum type. `found` holds text, a citations array, and an optional `HighlightRef`. `refusal` holds text and `RefusalReason`. A refusal cannot carry a citation or a highlight.

`Citation` requires `DocumentID`, `PageNumber`, and a non-empty snippet. `PageNumber` rejects 0 and negative values. Empty document, photo, and part IDs fail at construction.

`Message` is a sum type. A user turn is text only. An assistant turn is an `Answer`. `Conversation` is an identifier plus an ordered list of messages, with `appending` as the only mutation.

JSON is snake_case, documented here so #10 stays aligned:

| Swift | JSON |
| --- | --- |
| `Answer.found` | `"kind": "answer"` |
| `Answer.refusal` | `"kind": "refusal"` |
| `Citation.docID` | `doc_id` |
| `Citation.page` | `page` |
| `Citation.snippet` | `snippet` |
| `HighlightRef.bayPhotoID` | `bay_photo_id` |
| `HighlightRef.partID` | `part_id` |
| `RefusalReason.notFoundInManual` | `not_found_in_manual` |

`found` uses `"kind": "answer"` because that is the discriminator already on the wire. Validation lives in failable inits and `Codable` decode. Callers that already have a value can trust it.

Identifiers are branded so a part ID cannot be passed as a document ID. Answer text stays a `String` that is checked at the boundary, because the card and eval read it as text, not as an ID.

## Synthesis decision

Two shapes were compared.

Candidate A was a single `Answer` struct (text, citations, optional highlight, plus a status field). That matches a flat JSON object and is easy to render. It also lets a refusal compile with a highlight or a citation.

Candidate B was a sum type for `Answer` and `Message`, with branded IDs and a required page. That hides combination checks behind construction.

#10 independently shipped Candidate B on the wire (`oneOf` found vs refusal). The merged design takes Candidate B as the base and grafts Candidate A's one-object `Codable` mapping and the exact #10 keys. `AnswerContract` from #10 is removed so `Answer`, `Citation`, and `HighlightRef` are the only names.

## Tradeoffs accepted

- We accept `"kind": "answer"` for a found reply, instead of `"kind": "found"`, so the fixtures and schema do not change.
- We accept empty `citations` on a found answer so M1 chat works before retrieval. M2 can tighten that in the spec guard, not in this type.
- We accept failable inits (`Answer` cases wrap already-valid structs) instead of throwing inits at every construction site.
- We accept no timestamps on `Message`. The first chat screen does not need them, and adding them later does not break the answer contract.

## Alternatives considered

- **One struct with optional fields.** Callers would check `status`, `citations.isEmpty`, and `highlight == nil` on every render. A refusal with a highlight would compile. Rejected because the card and eval should not re-learn those rules.
- **Require at least one citation on every found answer.** That matches M2 grounded answers and would reject the #10 `plain.json` fixture. Rejected until retrieval exists.
- **camelCase JSON.** Idiomatic for Swift `Codable` defaults. Rejected because the schema, ROADMAP citation example (`doc_id`, `page`, `snippet`), and #10 fixtures are snake_case.
- **Keep `AnswerContract` and typealias it.** That leaves two public names for one payload. Rejected now that #9 owns the domain model.

## Open questions and risks

- Should `POST /chat` send this `Conversation` JSON as the request body, or a slimmer `{ "messages": [...] }`? #14 can decide without changing `Answer`.
- Will there be refusal reasons besides `not_found_in_manual`? The type can grow cases. The schema would need a matching change.
- Should decode fail on unknown JSON keys the way the schema's `additionalProperties: false` does? Swift `Codable` ignores extras today. The Python tests own that check.

## Answer card

The chat screen holds a `ChatViewModel` over `Conversation`. Assistant turns render `AnswerCardContent` (chip labels, refusal status, highlight-slot visibility) in `AnswerCardView`. The image slot is a placeholder until the highlight engine has a bay photo.
