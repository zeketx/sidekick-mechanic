# Onboarding animation ideas (for owner review)

Ideas only. No animation ships in v1. The three static screens in [user-journey.md](user-journey.md) are enough for first open.

Audience: Zeke, who does not need engine-part vocabulary. Each idea should make one promise obvious in a few seconds: *ask in chat, get a cited page, see the part on a photo.*

Safety: no torque, spec, pinout, wire color, part number, or firing order. The 2JZ-GE in this truck is naturally aspirated — **do not draw a turbo**. Placeholder copy stays `FAKE-DOC-2JZ` / `p. 999` if any text appears.

Effort is a sketch-level guess: **low** = a few hours on the phone, **med** = a couple of days, **high** = a specialist pass (Lottie, 3D, or video).

---

### 1. Self-tracing outline

A line drawing of the engine bay draws itself the way the highlight does: one continuous outline around the air box on top, then the rest of the bay fades in as a photo underneath.

**Why it fits.** The product’s visual signature is that outline (fuchsia in the app, black in the wireframes). Teaching the outline *as* the animation means onboarding is already speaking highlight language.

**Effort:** med.

---

### 2. Scan sweep

A vertical light bar travels across a still bay photo. As it passes, one region lights up (the air box). A small label appears: “this is the part the answer named.” No part-store name required.

**Why it fits.** Matches the “I scanned your photo” feeling without claiming live AR (that is Phase 2). Easy to pause on the last frame as the first onboarding screen.

**Effort:** med.

---

### 3. Exploded assemble (no turbo)

The engine comes apart into a few big, friendly blocks — air box, long engine body, radiator area — then they click back together. One block stays outlined. Never a turbo snail. Never a torque callout.

**Why it fits.** Shows “this is one engine, made of a few areas you can talk about” without a parts catalog. Risk: looks like a video game if it gets too clever.

**Effort:** high.

---

### 4. Hood lift

The hood of a boxy 70-series-shaped truck lifts. The camera eases into a placeholder bay. A single outline appears. Title card: “Your mechanic. One truck.”

**Why it fits.** Instantly says *this app is for this vehicle*, not a generic chatbot. Low information density, which is what a first screen wants.

**Effort:** low (still frames + a short motion of the hood). High if the truck is 3D.

---

### 5. Chat → chip → outline

A chat bubble types “rough idle after a cold start.” An answer card slides up. A citation chip (`FAKE-DOC-2JZ · p. 999`) peels off the card and lands on the outlined air box in the photo.

**Why it fits.** It *is* the loop. Good as screen 2 (“How it works”) if the static cards feel dry.

**Effort:** med.

---

### 6. Follow the air (naturally aspirated)

A small puff of air goes in through the air box on top and along the intake path. No turbo, no compressor, no boost gauge. The path pauses on the outlined box: “start here.”

**Why it fits.** Cold-idle questions are often “air side first.” It teaches a direction of travel without a spec. Must stay NA; a snail-shaped turbo would be the wrong engine.

**Effort:** med.

---

### 7. Manual page to photo

A fake manual page (`FAKE-DOC-2JZ p. 999`, gray boxes instead of real diagrams) dissolves into the bay photo. The same region that was a box on the page becomes the outline on the photo.

**Why it fits.** Makes the citation promise visual: the page and the photo are talking about the same place. Do not use a real scanned manual page.

**Effort:** high (two layouts have to line up).

---

### 8. Dim-the-rest pulse

The whole bay is visible. Once, the surround dims and the air box saturates — the treatment the highlight bakeoff already picked — then it eases back so you still see neighbors. Repeat once.

**Why it fits.** Cheap, honest, and already how the renderer works. Teaches “the rest of the bay stays readable.”

**Effort:** low.

---

## Recommendation

v1: **no animation.** Use the three static screens.

If one motion lands after v1, start with **1 (self-tracing outline)** or **8 (dim-the-rest pulse)**. Both reuse the highlight style we already have. Save **3** and **7** for a portfolio polish pass.
