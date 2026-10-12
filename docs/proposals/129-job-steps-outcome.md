# Job steps and how it went

Proposal for [issue 129](https://github.com/zeketx/sidekick-mechanic/issues/129). Read this before any build. This note does not change the app.

You are the only user. Every new line on the sheet assumes you have not worked on an engine before. The sheet stays white, with rounded top corners. The chat behind it dims, and the dim gets darker as the sheet rises. This work does not add a large-text layout.

## What the sheet does today

The Cold idle sheet shows two lines under the heading "Steps 1 of 3". The first box starts checked. The second line is the fixed sentence "Next step (from the cited page)". Those two lines are copied onto every job when the first answer arrives. A later answer leaves them in place. Tapping a box does nothing.

Worked, Partly, and Didn't already save on the job. The Jobs list already shows the word you picked. The chat never asks what happened. The scan log is nine demo photos, and none of those tiles show how a job went.

The full sheet also has "What fixed it?". That box is your own note. It stays a note.

## Where the steps come from

A new job builds its list from the first answer, then stores the list on the job. A later answer does not rebuild the list, so a box you already checked stays checked.

The list holds at most three steps. Every box starts empty.

The rules, in order:

1. If the answer outlines a part, the first step is "Look at the outlined part".
2. Each page the answer cites adds a step, "Read this page", until the list is full. A second page uses the same words, with that page's chip under the line so the rows are easy to tell apart. A page that does not fit stays in the chips above the list. Those chips already open the page.
3. If the answer has no outline and no page, the only step is "Ask what to do next".

A reply that finds nothing in the manual has no steps, and the heading stays hidden.

The heading counts the boxes on the job. Zero checked out of two reads "Steps 0 of 2". One checked reads "Steps 1 of 2". The fixed heading "Steps 1 of 3" goes away.

The Cold idle demo uses these same rules. It shows an empty "Look at the outlined part" and an empty "Read this page". Expect that demo to differ from the Figma checklist. That checklist is the bug this issue describes.

A model-written checklist would be a new field on the answer the server sends. A model can invent a step the page does not support. This plan points only at an outline or a page the answer already returned. The words are fixed app copy. They contain no torque, no gap, and no part number. If you later want the model to write the lines, the stored step can hold those words with no second save format.

## How you check a step

The box and the words are two taps.

Tap the box to check it. Tap it again to clear it. The job saves at that moment. The save path for a checked box already exists. The sheet never calls it today. This build connects the tap to that path.

You can pick Worked, Partly, or Didn't before every box is checked. Stopping early is a normal end.

Tap the words to open help. That tap leaves the box as it is.

## What the words open

Each step stores one kind of help.

"Look at the outlined part" opens the highlight card the photo already opens.

"Read this page" opens the manual page for that row. The page is the one the answer cited. The step stores that page with it, so a later answer cannot aim the same row at a different page.

"Ask what to do next" lowers the sheet and puts "What should I do next?" in the typing box. Nothing sends until you tap send. You can change the words first.

A step left from an older save may have no help. Its box still toggles. Its words do nothing.

## How did it go

The half sheet and the full sheet both say "How did it go?". The label "Outcome" goes away.

The row is on the sheet from the moment it opens, empty boxes included.

Tap one word. The job saves that pick. Tap the same word again and the job stays as it is. Tap a different word and the pick changes.

Worked fills the button and shows on the Jobs row. The chat stays as it was.

Partly lowers the sheet and sends one message in that job's chat. "What happened? It only partly worked."

Didn't does the same with "What happened? It didn't work."

The sidekick answers in that same chat, the way it answers anything you type. The question goes out once for that job. Changing Partly to Didn't does not ask again. Picking Worked later leaves the question in the chat.

If the phone saves the pick and stops before the question is sent, tap Partly or Didn't again. That second tap sends the question. After the question is in the chat, the same tap does nothing.

"What fixed it?" stays on the full sheet. It is your note, and it is not sent to the chat.

## What is saved

One file on the phone, `jobs.json`, already holds every job. Each job already holds its chat, its steps, and the pick. The file is version 1. A step today is an id, a title, and a checked flag.

Version 2 adds the help kind on each step. The app still opens a version 1 file. It fills help for the old lines, and the next save writes version 2. Opening the same file twice fills it the same way. A file from a newer app stays put, and this app does not overwrite it. That last rule is already how the file works.

Old lines fill like this.

A title that starts with "Look at", on a job that has a photo or an outline, opens the highlight.

The exact title "Next step (from the cited page)" opens the first cited page. If that job has no page, those words prepare the chat question instead.

Any other old title keeps its checkbox and gains no help link.

New jobs are written as version 2 from the start. They never receive the two fixed Cold idle lines.

The answer file shared with the server stays as it is. The list is built on the phone from the citations and the outline already on that answer.

One new step looks like this. The document id and the page are a fake fixture, not a truck spec.

```json
{
  "id": 1,
  "title": "Look at the outlined part",
  "isComplete": false,
  "guidance": { "kind": "look" }
}
```

A page step stores the cited document and page beside the kind.

```json
{
  "id": 2,
  "title": "Read this page",
  "isComplete": false,
  "guidance": { "kind": "page", "doc_id": "FAKE-DOC-2JZ", "page": 999 }
}
```

The pick stays the three values `worked`, `partly`, and `didnt`. No pick is still an empty value.

The "What happened?" line is a normal message in that job's chat. Its id is built from the job id. A second job can ask its own question. A second tap in the same job cannot send a copy.

## Jobs and the scan log

The Jobs row already shows Worked, Partly, or Didn't. A job with no pick shows no word. That stays.

The scan log you open from Jobs becomes your jobs that have a photo, newest first. Each tile shows the outline and the same outcome word. No pick means no word on the tile. The filter chips use the tags already stored on the job. The chip "all" shows every job that has a photo. A job with no photo stays on the Jobs list only.

The design screenshot for the scan log keeps the nine demo tiles. Those tiles are for checking the picture. The list you use is the saved jobs.

## Screens

The sheet is white. The top corners stay rounded. Chat above a half sheet is dim. Chat above a full sheet is darker. A lowered sheet leaves the chat undimmed.

Half sheet, nothing checked, no pick yet.

```
+----------------------------+
| Job · Cold idle       Close|
| [ photo, part outlined ]   |
| Steps 0 of 2               |
| [ ] Look at the outlined   |
|     part                   |
| [ ] Read this page         |
|     FAKE-DOC-2JZ · p. 999  |
| How did it go?             |
| Worked   Partly   Didn't   |
+----------------------------+
```

The same sheet after the first box is checked. The words still open the photo.

```
+----------------------------+
| Job · Cold idle       Close|
| Steps 1 of 2               |
| [x] Look at the outlined   |
|     part                   |
| [ ] Read this page         |
| How did it go?             |
| Worked   Partly   Didn't   |
+----------------------------+
```

Full sheet after Worked. Notes and tags stay on this sheet. The last field is your note.

```
+----------------------------+
| Job · Cold idle       Close|
| Steps 2 of 2               |
| [x] Look at the outlined   |
|     part                   |
| [x] Read this page         |
| Notes                      |
| Tags                       |
| How did it go?             |
| [Worked]  Partly   Didn't  |
| What fixed it?             |
| [                        ] |
+----------------------------+
```

After Partly, the sheet drops. The question is already in the chat.

```
+----------------------------+
| What happened? It only     |
| partly worked.             |
|                            |
| The reply shows here.      |
|                            |
| +------------------------+ |
| | Job · Cold idle    Open| |
| | photo peek             | |
| +------------------------+ |
| [ type a message       ]   |
+----------------------------+
```

## Questions

These are the calls the code cannot settle. Under each one is the choice the build will use if you leave it. Answer in your own words.

1. The step lines stay short. "Look at the outlined part", "Read this page", and "Ask what to do next". A later issue can let the model write lines from the manual. Say so if you want that writing in the first build.
2. Partly and Didn't send "What happened?" on their own, one time. Say so if those words should wait in the typing box until you tap send.
3. The scan log you open from Jobs shows your job photos and the outcome word. The nine demo tiles stay on the design screenshot. Say so if the nine tiles should remain the screen you use.
4. Changing Partly to Didn't does not ask a second time. Say so if a changed pick should ask again.

## How to build it

Four small changes, in this order. Each one is checked before the next starts. None of them start until you accept this note.

1. Store the help kind on the step, and open today's job file without setting it aside. Linux tests. The screen stays as it is.
2. Build the list from the first answer, count the heading, and make the box and the words tappable. You check the sheet in Xcode.
3. Send the one "What happened?" message for Partly or Didn't, and lower the sheet. A second tap sends nothing. You check that chat in Xcode.
4. Build the live scan log from saved jobs, and show the outcome word on each tile. The screenshot launch keeps the nine demo tiles. You check the grid in Xcode.

[Issue 97](https://github.com/zeketx/sidekick-mechanic/issues/97) already asks for steps that come from the cited answer. It also asks for a count like "1 of 3", and for dropping any step that would need an uncited number. This plan covers that slice. The rest of that issue stays for later.
