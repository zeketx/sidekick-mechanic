# Highlight viewer

The highlight viewer is a full-bleed card over chat. The mark is a precise outline of the part, or of a group of parts. A bounding box is never the highlight. Unsure is a dashed outline (internal flag). Not-found has no outline. Reference puts the outline on a labeled stand-in photo.

## Sub-features

- `highlight-confident` is a solid outline on the user photo.
- `highlight-unsure` is a dashed outline, Yes / Not this, and the internal-only banner.
- `highlight-not-found` has no outline and a diagram chip `FAKE-DOC-2JZ · p. 999`.
- `highlight-reference` shows the user snap untraced plus a traced stand-in with outline.
- `highlight-close` dismisses via plain-text Close.

## How to get to it (user POV)

- Launch `-screen highlight-confident|highlight-unsure|highlight-not-found|highlight-reference`.
- From chat, open the answer-card photo.
- From the job sheet, open the photo thumb (`jobSheet.photo`).
- From scan log, choose a cell (`scanLog.cell.scan-log-0`).

## Driving it with verify-sidekick

Preconditions:

- Doctor is green on a Mac.
- `-demoPhoto hilux` unless named otherwise (`supra`, `hrymx`, `flickr`).
- Unsure: `-screen highlight-unsure` also sets the internal flag. Do not omit the screen key and expect dashed ink.

- **Confident.** `.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens --screens highlight-confident`. Identifiers `highlightViewer`, `highlightViewer.photo`, `highlightViewer.close`. Close is plain text. Outline follows the part. Fail if the mark is a rectangle.
- **Unsure.** `--screens highlight-unsure`. Banner `highlightViewer.banner`. Prompt `highlightViewer.unsurePrompt`. Buttons `demo.confirm.yes` and `demo.confirm.notThis`. Stroke is dashed.
- **Not found.** `--screens highlight-not-found`. No outline. Chip `highlightViewer.diagram`. Footer copy includes Not in this photo.
- **Reference.** `--screens highlight-reference`. Banner `Reference, not your truck.` User photo banner `No outline on your photo (not traced yet)`. Outline is on the second photo.
- **Close.** Tap `highlightViewer.close`. Chat or the sheet behind is visible again.
- **Proof.** Side-by-sides against `features/figma/highlight-confident.png` (and unsure, not-found, reference). Fill the outline rule. Background `#F4F4F4`. Status bar visible.

## Gotchas

- v1 product flag `unsureHighlight` is off. Without `-screen highlight-unsure`, an unsure source resolves to reference (or not-found). The helper always passes `-screen highlight-unsure` for that shot.
- Styles stay outline, saturate, circle, and dim the rest. This card uses outline. Do not screenshot saturate as the v1 proof.
- Demo photos 404 does not block the card; a gray placeholder still shows. Note it in the checklist if the Figma shows a real bay.
- Retake hint copy includes `Photo angles are TBD`. That is the product string, not a missing screenshot.
