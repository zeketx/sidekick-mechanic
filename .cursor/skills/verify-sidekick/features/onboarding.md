# Onboarding

Onboarding is three first-open screens (welcome, how it works, your garage). Skip or Start chatting lands on chat. The Garage list is also a sheet from Chat so the conversation is not wiped.

## Sub-features

- `onboarding-1` shows the welcome pitch, truck identity, and an organic magenta outline on a placeholder air box (never a rectangle).
- `onboarding-2` shows the three how-it-works cards.
- `onboarding-3` shows confirmed garage facts and TBD rows.
- `onboarding-skip` leaves onboarding from Skip or Start chatting.
- `onboarding-garage-sheet` opens Your garage from Chat without resetting the thread.

## How to get to it (user POV)

- Cold launch when `sidekick.onboarding.completed` is not YES.
- Pass `-resetOnboarding -screen onboarding-1` or `onboarding-2` or `onboarding-3`.
- After chat is showing, choose `Garage` (`chat.garage`) to present the sheet.

## Driving it with verify-sidekick

Preconditions:

- `app/SidekickMechanic/OnboardingFlow.swift` exists. On this stack it does not (PR #111, `cursor/v1-onboarding-5c2a`).
- Doctor has run. Do not claim onboarding verified from Jobs or from a chat screenshot.

- **Detect the gap.** Confirm the file is missing. Run `test -f app/SidekickMechanic/OnboardingFlow.swift`. Exit 1 on this branch. Write `artifacts/verify/<run-id>/screenshots/skipped.json` with reason `OnboardingFlow.swift is not in this checkout (PR #111).`
- **Welcome.** On a checkout that has #111: `.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens --screens onboarding-1`. Identifier `onboarding.welcome`. The bay drawing is an irregular outline, not a box. Title copy is `Your mechanic. One truck.`
- **How it works.** `--screens onboarding-2`. Identifier `onboarding.howItWorks`. Three cards. Citation example is `FAKE-DOC-2JZ · p. 999`.
- **Garage page.** `--screens onboarding-3`. Identifier `onboarding.garage`. Confirmed: Chassis `1990 Land Cruiser LJ78`, Engine `2JZ-GE swap`, Donor ECU `Lexus · year TBD`. Pending rows are `TBD`.
- **Skip.** Tap `onboarding.skip`. Chat composer `chat.composer` appears.
- **Garage sheet.** After onboarding is completed, tap `chat.garage`. Sheet identifier `onboarding.garage`. Dismiss with `garage.done`. `DriveUITests.testOpenGarageIfPresent` does this and XCTSkips when `chat.garage` is absent.
- **Proof.** Side-by-side `compare/onboarding-1.png` (and 2, 3) against `features/figma/onboarding-1.png`. Fill the design checklist. Header buttons are plain text Skip, not glass capsules.

## Gotchas

- This UI stack (PRs #112–#114) does not compile onboarding. `screens --screens onboarding-1` records a skip; it does not fail the Mac run. Do not treat chat as onboarding.
- `-sidekick.onboarding.completed YES` is a UserDefaults launch argument. It does nothing until #111 is merged.
- Garage facts come from `docs/vehicle/TRUCK.md`. Unknowns stay `TBD`. Do not fill typical values in the screenshot assertion.
- The welcome outline must not be a rectangle. If the air box is a rounded rect, fail the highlight rule.
