# What Sidekick can do

Sidekick Mechanic is a chat-first mechanic on iPhone for one truck: Zeke's 1990 Land Cruiser LJ78 with a 2JZ-GE swap. He describes a problem. The app answers from the manuals, shows the page, and can point at a part on a photo.

This file is the living list of those capabilities, written as user stories. Every story is something the app on `main` does today, or an open pull request or issue. Checked against `main` at `62d4813` (12 Oct 2026), which includes per-job chat ([#138](https://github.com/zeketx/sidekick-mechanic/pull/138)) and manual-page zoom plus Ask about this page ([#137](https://github.com/zeketx/sidekick-mechanic/pull/137)).

**Keep it current.** Any pull request that adds or changes something a person can do in the app updates this file in the same pull request.

Each story ends with a status:

- **Shipped** — on `main` now.
- **In review** — an open pull request. Linked.
- **Planned** — an open issue, not built yet. Linked.

## Onboarding

As Zeke, I can walk through three first-open screens (a welcome, how chat works, and the known facts about the truck) so that I know what the app will and will not guess before I ask a question.

Where: the first launch, then Next, then Start chatting.
Status: Shipped

As Zeke, I can skip the intro, or finish it, so that the next time I open the app I land in chat.

Where: Skip, or Start chatting on the last screen.
Status: Shipped

As Zeke, I can see the truck named as a 1990 Land Cruiser LJ78 with a 2JZ-GE swap, donor year still unknown, and OBD type, harness, and photo angles left as TBD so that nothing is filled in from memory.

Where: the welcome card, and the first-open page titled Your garage.
Status: Shipped

## Chat and answers

As Zeke, I can describe a problem in my own words, without part names, and get a reply so that I can start from the symptom.

Where: Chat, the box that says Describe the problem, then Send.
Status: Shipped

As Zeke, I can start a new chat so that the next question becomes its own job.

Where: New job, in the chat header.
Status: Shipped

As Zeke, I can see "Waiting for a reply" while an answer is on the way so that I know the app is still working.

Where: the message list, under my question.
Status: Shipped

As Zeke, I can read a short answer with a chip that names the manual and the page, and tap that chip, so that I can open the page the answer came from.

Where: the answer card, the chip that looks like `DOC · p. N`.
Status: Shipped

As Zeke, I can see "Not found in the manual" when there is no cited page so that the app does not invent a procedure.

Where: the answer card, the line with the closed-book mark.
Status: Shipped

As Zeke, I can have a torque, a pin, a connector, or another numbered spec withheld when that number is not in the cited manual text so that a guessed spec never looks like advice. The reply says "Not found in the cited manual text" and names what it blocked.

Where: the reply itself, in place of the answer.
Status: Shipped

As Zeke, I can see a short safety note at the start of a numbered how-to (let the engine cool, disconnect the battery when a step calls for it, and support the vehicle on stands before working underneath) so that a procedure does not start with the first wrench turn.

Where: the first lines of that reply.
Status: Shipped

As Zeke, I can be told the wiring manual is not loaded yet when I ask a wiring question it cannot cite so that I do not get a made-up pin or wire color.

Where: the reply.
Status: Shipped

As Zeke, I can see a plain error if the phone is offline, the answer takes too long, the reply cannot be read, or the request fails, and then send again so that a dead connection is obvious.

Where: the red bar above the composer. The words are "No network connection…", "The backend took too long to respond.", "The backend sent a reply this app could not read.", or "The backend could not complete this request."
Status: Shipped

As Zeke, I can be told "The mechanic is unavailable right now" when the answer service cannot produce a reply so that I know to try again in a moment. Today that line arrives as a normal answer card.

Where: the answer card.
Status: Shipped

As Zeke, I can have my Garage notes travel with a question (truck facts, parts and papers, and open to-dos) so that the reply can mention what I already wrote down. Photos and finished to-dos stay on the phone. Page citations still come only from the manuals.

Where: the same Send button. No new screen.
Status: In review — [#124](https://github.com/zeketx/sidekick-mechanic/pull/124) (draft)

As Zeke, I can have a missing manual index come back as "not found" without the app asking the model, have more ways of writing a torque blocked when they are not on the cited page, and have a downed answer service show up as a failure instead of a normal answer card so that none of those look like cited advice.

Where: the reply.
Status: In review — [#135](https://github.com/zeketx/sidekick-mechanic/pull/135)

## Jobs

As Zeke, I can keep a separate chat on each job, open that job later, and still have the messages after I quit the app so that two problems do not share one thread.

Where: Jobs, then a row. The list says "Each one keeps its own chat."
Status: Shipped

As Zeke, I can see each job named from the first few words of its first question, with Today, Yesterday, or a date, so that I can find it again. The sample question "Rough idle after a cold start" is titled Cold idle.

Where: Jobs.
Status: Shipped

As Zeke, I can see "No jobs yet. Describe a problem to start one." when the list is empty so that I know the first message creates the first job.

Where: Jobs.
Status: Shipped

As Zeke, I can pull the job sheet from a peek, to half height, to full, and close it so that I can read the job and then get the composer back. The composer hides while the sheet is half or full.

Where: the sheet handle, or Open and Close.
Status: Shipped

As Zeke, I can read the latest answer and its page chips on the job sheet, and open a chip, so that the job and the manual stay together.

Where: the job sheet.
Status: Shipped

As Zeke, I can attach a public engine-bay photo to the job, see that it is not my truck, and open it to look at an outline around a part so that I have a picture to go with the answer. The attach button uses a demo bay photo, not the camera.

Where: Attach a photo, on the peek or in the composer, then the photo. Photo credit is on the info button.
Status: Shipped

As Zeke, I can zoom that highlight photo in and out with the pinch control so that I can look at the outline up close.

Where: the highlight card, the control labeled pinch.
Status: Shipped

As Zeke, I can pinch and double-tap the highlight photo, with the outline staying locked to the picture, so that a small part is still findable.

Where: the highlight card.
Status: Planned — [#106](https://github.com/zeketx/sidekick-mechanic/issues/106)

As Zeke, I can see a short step list on the sheet so that the job shows a next action. The heading says "Steps 1 of 3" and two lines are shown. The boxes are a picture of progress. They do not respond to a tap.

Where: the job sheet, under Steps.
Status: Shipped

As Zeke, I can tap a step to check it off, open guidance for that step (the manual page, the photo, or this job's chat), and have the checks saved on the job so that I know what I have already done.

Where: the job sheet, the step rows.
Status: Planned — [#129](https://github.com/zeketx/sidekick-mechanic/issues/129). The write-up to review first is [#139](https://github.com/zeketx/sidekick-mechanic/pull/139).

As Zeke, I can mark a job Worked, Partly, or Didn't, type what fixed it, write notes, and add a tag, and see Worked, Partly, or Didn't on the Jobs row so that the close-out stays with the job. Picking an outcome does not start a new chat message.

Where: pull the sheet all the way up for notes, tags, How did it go?, and What fixed it? Outcome is also on the half sheet.
Status: Shipped

As Zeke, I can have Partly or Didn't ask what happened in that job's chat and suggest a next step, and see the saved outcome in Jobs and the scan log, so that a failed try leads somewhere.

Where: the outcome row, then that job's chat.
Status: Planned — [#129](https://github.com/zeketx/sidekick-mechanic/issues/129). The write-up to review first is [#139](https://github.com/zeketx/sidekick-mechanic/pull/139).

As Zeke, I can get a confident outline on a photo of my own engine bay so that the highlight is my truck, not a public stand-in. The truck is not here yet, so this is not built.

Where: a photo I take.
Status: Planned — [#109](https://github.com/zeketx/sidekick-mechanic/issues/109)

As Zeke, I can be asked "Is this it?" and tap Yes or Not this when the app is unsure which part it found so that a doubtful outline does not look certain. That prompt is off in the app I use today.

Where: the highlight card.
Status: Planned — [#87](https://github.com/zeketx/sidekick-mechanic/issues/87)

## Manual pages

As Zeke, I can open a cited page on a white sheet and see the document, the page number, the page image, the cited snippet, and a Go deeper block (How this works, What to test, How to test it, Tools) so that I can read the page the answer used. Go deeper uses only that page. A `FAKE-DOC` page is a stand-in drawn on the phone. A real manual page is loaded from the answer service.

Where: any citation chip, in chat or on the job sheet.
Status: Shipped

As Zeke, I can tap Try again when a page image fails to load so that a missed download is not a dead end.

Where: the page sheet, Try again.
Status: Shipped

As Zeke, I can pinch, double-tap, and drag a zoomed manual page, and turn to the next or previous page once that image is loaded, so that I can read a small diagram. While I am zoomed in, a drag moves the page and the sheet stays put. Double-tap zooms to 2.5×. Pinch goes up to 4×.

Where: the page image, and the previous and next arrows.
Status: Shipped

As Zeke, I can tap Ask about this page and land back in the same job's chat, with that page pinned, so that the next question is about the page I was reading. If I have no job yet, this starts one. The job sheet drops so the starters are visible.

Where: Ask about this page, at the bottom of the page sheet.
Status: Shipped

As Zeke, I can tap one of three starters — Explain this page simply, What tools do I need?, or Which connector is this? — so that I do not have to invent the question. The first two ask in plain language. The page's text is what the answer is allowed to use.

Where: the chips stacked above the composer, after Ask about this page.
Status: Shipped

As Zeke, I can unpin the page so that my next message is a normal typed question again.

Where: the x on the page chip above the composer.
Status: Shipped

As Zeke, I can take or choose a photo of a plug for Which connector is this?, and read whether the outline, the number of pins, and the color look like the plug on the page, so that I can check a connector before I unplug it. A match still says the check can be wrong and tells me to hold them next to each other. If the app cannot tell, it says so and does not call it a match. The photo is sent with the question and is not saved in the job.

Where: Which connector is this?, then the white sheet with Take a photo, Choose from library, and Close.
Status: Shipped

As Zeke, I can be told the app cannot read the text on a page so that it does not explain a blank image.

Where: the reply, after an explain question on a page with no text.
Status: Shipped

## Scan log

As Zeke, I can open a grid of public engine-bay photos, filter it by all, intake, cooling, ignition, electrical, fuel, inspected, or watch, and see "Nothing matches." when a filter is empty so that the chips actually change the grid. These are sample photos, not a log of my own scans. A cell that is a stand-in says "Not your truck".

Where: Scan log, from the chat header, or from the Jobs header.
Status: Shipped

As Zeke, I can tap a scan-log photo and open its highlight card so that I can look at the outline.

Where: a cell in the grid.
Status: Shipped

## Garage

As Zeke, I can open Your garage from chat, on a white sheet, so that I can look at notes without losing the conversation underneath.

Where: Garage, in the chat header.
Status: Shipped

As Zeke, I can read the starting facts (chassis, engine, donor ECU) and the TBD rows, and add, change, or remove a fact, so that what I know about the truck lives in one place. TBD means it is not known yet.

Where: Garage, Edit, then Add a fact, Change, or Remove, then Save.
Status: Shipped

As Zeke, I can add a photo from the camera or the photo library, with an optional short note, and remove it later so that bay pictures stay with the truck.

Where: Garage, Edit, Add a photo.
Status: Shipped

As Zeke, I can add a part or a paper with a name, an optional note, and an optional photo, and remove it later so that I remember what I already bought or found.

Where: Garage, Edit, Add a part or paper.
Status: Shipped

As Zeke, I can add a to-do, check it off, and remove it so that small jobs do not live only in my head.

Where: Garage, the To-do section, Add a to-do, and the checkbox on a line.
Status: Shipped

As Zeke, I can close the garage, quit the app, and open it again and still have the facts, photos, parts, and to-dos so that the notes are really saved on this phone.

Where: the same Garage sheet, after a relaunch.
Status: Shipped

As Zeke, I can see a clear line when a note or a photo could not be saved, or when saved notes could not be read, so that a failed save is not silent. If the notes cannot be read, they stay on the phone and the app shows the starting list.

Where: the status line on the garage sheet.
Status: Shipped

## Behind the scenes

As Zeke, I can quit the app and come back to the same jobs and the same garage notes so that chat and the garage survive a relaunch. Both live on this phone. A new question still needs the answer service. A reply that was still in flight starts over as idle.

Where: reopen the app, then Chat, Jobs, or Garage.
Status: Shipped

As Zeke, I can see a notice when saved jobs cannot be opened, and the app leaves those files alone, so that a bad save is not overwritten. One message says a copy was kept and new jobs save normally. Another says the jobs were saved by a newer version of the app. Another says nothing was changed and new jobs are not saved until the app restarts.

Where: the line under the chat title.
Status: Shipped

As Zeke, I can turn on a demo mode that labels highlights as scripted and not my truck, pick Outline, Saturate, Circle, or Dim the rest, and open a Readings tab of simulated numbers marked "Simulated readings. Not engine specs." so that a demo never looks like live data from the truck. This chrome is on only when the app is launched that way. The everyday app is Chat, Jobs, Scan log, and Garage.

Where: Demo mode, in the header, and the Readings tab. Both appear with demo chrome.
Status: Shipped

As Zeke, I can read one page that says where each kind of note lives (on the phone or on the answer service) and how a job, its chat, its steps, and the garage relate so that the storage is written down. That page is not on `main` yet.

Where: `docs/DATA_SCHEMA.md`, once the pull request lands. Not a button in the app.
Status: In review — [#133](https://github.com/zeketx/sidekick-mechanic/pull/133), for [#131](https://github.com/zeketx/sidekick-mechanic/issues/131)
