# What Sidekick can do

Sidekick is a mechanic you text from your phone, for one truck. The demo truck is a 1990 Land Cruiser LJ78 with a 2JZ-GE swap. The person using the app is a home mechanic working on their own truck.

You describe a problem. It answers from the real manuals, shows the page, and can draw a line around a part on a photo.

This file lists what the app can do. Each section starts with the annoying part, then the stories that help. Checked against `main` at `e0352d4` (14 Oct 2026), which includes garage notes on each question ([#124](https://github.com/zeketx/sidekick-mechanic/pull/124)), cheap checks when the manual has no page ([#143](https://github.com/zeketx/sidekick-mechanic/pull/143)), and no related page when that page is off-topic ([#145](https://github.com/zeketx/sidekick-mechanic/pull/145)), on top of the safety-gap fixes ([#135](https://github.com/zeketx/sidekick-mechanic/pull/135)), a saved chat on each job ([#138](https://github.com/zeketx/sidekick-mechanic/pull/138)), and zooming a manual page plus Ask about this page ([#137](https://github.com/zeketx/sidekick-mechanic/pull/137)).

**Keep it current.** If a pull request changes something a person can do in the app, update this file in that same pull request.

- **Shipped** — on `main` now.
- **In review** — an open pull request. Linked.
- **Planned** — an open issue, not built yet. Linked.

## The factory book is a pile of PDFs

The factory manuals are huge. You can't flip them with greasy hands, and search is useless when you don't know the shop name for the part.

As a user, I can describe the problem in my own words and get a short reply so that I don't have to hunt the PDF.

Where: Chat, the box that says Describe the problem, then Send.
Status: Shipped

As a user, I can tap a label on the reply that names the book and the page so that I open the page the answer actually used.

Where: the reply, the label that looks like `DOC · p. N`.
Status: Shipped

As a user, I can read that page on the phone, picture and quoted bit included, so that I stay out of the PDF. A practice page is drawn on the phone. A real manual page comes from the manuals the app has.

Where: that label, in the chat or on the job panel.
Status: Shipped

As a user, I can pinch, double-tap, and drag the page, and flip to the next or previous page once it has loaded, so that a tiny diagram is readable. Double-tap goes to 2.5×. Pinch goes up to 4×. While I'm zoomed in, a drag moves the page.

Where: the page picture, and the previous and next arrows.
Status: Shipped

As a user, I can tap Ask about this page and get three ready questions in that same job's chat so that I don't have to type with dirty hands. The questions are Explain this page simply, What tools do I need?, and Which connector is this? If I don't have a job yet, this starts one.

Where: Ask about this page, at the bottom of the page. The questions sit above the text box.
Status: Shipped

## The page is written for a dealer tech

Wiring diagrams and test steps use shop words, and they name tools you don't own.

As a user, I can ask for the page in plain words, and ask which tools it wants, so that I know what the step means before I buy anything.

Where: Explain this page simply, and What tools do I need?, above the text box.
Status: Shipped

As a user, I can read a short plain note under the page (how it works, what to test, how to test it, tools) so that the shop wording gets translated. It only uses that one page.

Where: Go deeper, on the page.
Status: Shipped

As a user, I can be told the wiring manual isn't loaded yet when I ask a wiring question it can't back up so that I don't get a made-up pin or wire color.

Where: the reply.
Status: Shipped

As a user, I can see a short safety line at the start of a numbered how-to (let the engine cool, pull the battery cable when a step says to, and put the truck on stands before you get under it) so that the first line isn't "stick your hand in there."

Where: the first lines of that reply.
Status: Shipped

As a user, I can be told the app can't read the words on a page so that it doesn't explain a blank picture.

Where: the reply, after Explain this page simply on a page with no text.
Status: Shipped

## You can't tell if that's the right plug

Connectors look the same until you unplug the wrong one.

As a user, I can take or pick a photo of a plug and ask which connector it is so that I can check it against the page before I unplug anything. If the shape, the pin count, and the color look the same, it still says it can be wrong and tells me to hold them next to each other. If it can't tell, it says so. The photo goes out with the question and is not kept on the job.

Where: Which connector is this?, then Take a photo or Choose from library.
Status: Shipped

## A number from the internet can be the wrong engine

A forum post will hand you a torque for a different motor. The wrong number breaks parts.

As a user, I can have a torque, a pin, a connector, or another number-with-a-unit dropped when that number is not in the manual text the reply used so that a guessed spec never looks like the book. The reply says "Not found in the cited manual text" and names what it blocked.

Where: the reply, in place of the answer.
Status: Shipped

As a user, I can see "Not in your manual. Here's what usually causes this." and then the cheap checks, cheapest first, so that I have a place to start without a made-up procedure. The card has a wrench, not the closed book. Chassis and engine from the garage show as Truck and Engine. One can show without the other, and TBD stays TBD. If neither is written down, that line is left off. The same safety line sits above the numbered checks. If a check names a torque, a pin, or another spec, the reply says "Not found in the cited manual text" and names what it blocked. A wiring question the wiring manual can't back up still says that manual isn't loaded. A page that is about the question can be opened from the card and from the job sheet under Related pages, with a dashed label, and it is marked as related, not as the page that answered.

Where: the reply, the card with the wrench, and the job sheet.
Status: Shipped. [#143](https://github.com/zeketx/sidekick-mechanic/pull/143)

As a user, I can see no related page rather than one about a different part, so that an off-topic page doesn't look like it belongs to the question. A page stays only when the opening that would be shown names the thing I asked about. A word that only shows up further down the page does not count. The checks still show.

Where: Related pages, on the card and on the job sheet. The row is left off when nothing qualifies.
Status: Shipped. [#145](https://github.com/zeketx/sidekick-mechanic/pull/145)

As a user, I can have more ways of writing a torque caught, a missing manual come back as "not found", and "The mechanic is unavailable right now" show up as a failure instead of a normal reply so that none of those look like the book said it.

Where: the reply.
Status: Shipped. [#135](https://github.com/zeketx/sidekick-mechanic/pull/135) is on `main` at `b1d3952`.

## The repair takes all week

You try something Saturday, come back Wednesday, and can't remember what you asked or whether it worked.

As a user, I can keep a separate chat for each problem, start a new one when the next problem is different, and open the old one later, including after I quit the app, so that two jobs don't get mixed.

Where: New job, in the header. Jobs, then a row. The list says "Each one keeps its own chat."
Status: Shipped

As a user, I can see each job named from the first few words of the question, with Today, Yesterday, or a date, so that I can find last week's idle problem. The sample question "Rough idle after a cold start" is titled Cold idle.

Where: Jobs.
Status: Shipped

As a user, I can read the last answer on the job and open its page from there so that the book stays with the job when I come back.

Where: the panel that slides up over the chat.
Status: Shipped

As a user, I can mark the job Worked, Partly, or Didn't, write what fixed it, jot notes, and add a tag, and see Worked, Partly, or Didn't on the Jobs row so that I remember how it ended. Picking one does not start a new chat message.

Where: pull the panel all the way up for notes, tags, How did it go?, and What fixed it? The outcome buttons are also on the half-open panel.
Status: Shipped

As a user, I can check off steps, open the page or the photo or this job's chat for a step, and have those checks saved so that I know what I already did. Today the boxes are just a picture. The heading says "Steps 1 of 3", two lines show, and a tap does nothing.

Where: the step rows on the job panel.
Status: Planned — [#129](https://github.com/zeketx/sidekick-mechanic/issues/129). The write-up to review first is [#139](https://github.com/zeketx/sidekick-mechanic/pull/139).

As a user, I can have Partly or Didn't ask what happened in that job's chat and suggest what to try next, and see that result on the job, so that a failed try leads somewhere.

Where: the outcome row, then that job's chat.
Status: Planned — [#129](https://github.com/zeketx/sidekick-mechanic/issues/129). The write-up to review first is [#139](https://github.com/zeketx/sidekick-mechanic/pull/139).

## You can't find the part in the bay

The book says "air box" and you're staring at a pile of hoses.

As a user, I can stick a public engine-bay photo on the job and open it with a line around a part so that I have a picture of what the reply is talking about. The photo is a demo bay. The app says it isn't your truck. The camera isn't used.

Where: Attach a photo, on the small job panel or next to the text box, then the photo.
Status: Shipped

As a user, I can zoom that photo with the pinch button so that the outline is big enough to see.

Where: the big photo, the control labeled pinch.
Status: Shipped

As a user, I can pinch and double-tap that photo, with the line stuck to the picture, so that a small part is still findable.

Where: the big photo.
Status: Planned — [#106](https://github.com/zeketx/sidekick-mechanic/issues/106)

As a user, I can get a clear line on a photo of my own engine bay so that the picture is my truck. That isn't built. The truck in the demo isn't here yet.

Where: a photo I take.
Status: Planned — [#109](https://github.com/zeketx/sidekick-mechanic/issues/109)

As a user, I can be asked "Is this it?" and tap Yes or Not this when the app isn't sure so that a shaky line doesn't look certain. That question is off in the app today.

Where: the big photo.
Status: Planned — [#87](https://github.com/zeketx/sidekick-mechanic/issues/87)

## You forget what you already have

Parts in a box, a photo from last month, a to-do you swore you'd remember.

As a user, I can write down a fact about the truck, change it, or remove it, and leave TBD as TBD until I actually know, so that I don't treat a guess as a fact. The starting list is the chassis, the engine, and the donor ECU, plus the rows that are still unknown.

Where: Garage, Edit, then Add a fact, Change, or Remove, then Save.
Status: Shipped

As a user, I can add a photo from the camera or the photo library, with a short note, and remove it later so that bay pictures stay with the truck.

Where: Garage, Edit, Add a photo.
Status: Shipped

As a user, I can save a part or a paper, with a name, a note, and an optional photo, and remove it later so that I remember what I already bought or found.

Where: Garage, Edit, Add a part or paper.
Status: Shipped

As a user, I can add a to-do, check it off, and remove it so that the little jobs aren't only in my head.

Where: Garage, To-do, Add a to-do, and the checkbox on a line.
Status: Shipped

As a user, I can have the truck facts, the parts and papers, and the open to-dos go out with my question, including when I ask about a page, so that the reply can mention what I already wrote down. Photos and finished to-dos stay on the phone. A very long note is shortened. Those notes are not a page in the book, and a page the reply points at still has to come from a manual.

Where: Send, and Ask about this page. No new screen.
Status: Shipped. [#124](https://github.com/zeketx/sidekick-mechanic/pull/124)

## Your notes should still be there tomorrow

A restart, a bad save, or a dead connection shouldn't eat the week or pretend it has an answer.

As a user, I can quit the app and come back to the same jobs and the same garage notes so that a restart doesn't wipe the week. They live on this phone. A new question still needs a connection. A reply that was still on its way starts over.

Where: open the app again, then Chat, Jobs, or Garage.
Status: Shipped

As a user, I can see a notice when saved jobs can't be opened, and the app leaves those files alone, so that a bad read doesn't erase them. One line says a copy was kept and new jobs save normally. One says the jobs were saved by a newer version of the app. One says nothing was changed and new jobs aren't saved until the app restarts.

Where: the line under the chat title.
Status: Shipped

As a user, I can see a red line when a garage note or photo couldn't be saved, or when saved notes couldn't be read, so that a failed save isn't quiet. If the notes can't be read, they stay on the phone and the app shows the starting list.

Where: Garage.
Status: Shipped

As a user, I can see a plain error if the phone is offline, the answer takes too long, the reply can't be read, or the request fails, and then send again, so that a dead connection doesn't look like an answer. The words on screen are "No network connection…", "The backend took too long to respond.", "The backend sent a reply this app could not read.", or "The backend could not complete this request."

Where: the red bar above the text box.
Status: Shipped
