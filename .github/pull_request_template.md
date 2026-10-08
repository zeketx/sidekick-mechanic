<!--
  One issue per PR.
  Use `Closes #N` when this PR finishes the issue.
  Use `Part of #N` when owner-only work remains (for example the Projects board).
-->

## Linked issue

Part of #

## What changed


## How verified


## Screenshots (UI PRs)

Required when UI, layout, or rendered states change. Include light, dark, and large Dynamic Type.

| State | Screenshot or recording |
| --- | --- |
| Light | |
| Dark | |
| Large Dynamic Type | |

Large text follows [docs/DYNAMIC_TYPE.md](docs/DYNAMIC_TYPE.md): default size and Accessibility XXXL, no mid-word breaks, headers and sheets still fit. `assertFitsOnScreen` covers the geometry; the AXXXL screenshots still need a look for "Tod…" and hyphenated titles.

If you cannot run the app on Linux, attach SwiftUI preview code and ask the owner to capture screenshots in Xcode.

## Sources (vehicle facts)

Every vehicle fact cites a document ID and page from `docs/MANUALS.md`, or an owner observation in `docs/vehicle/TRUCK.md`. Unknowns are `TBD`. Test fixtures use obviously fake values (for example `"page": 999`, `"value": "FAKE-SPEC"`).

- [ ] No vehicle facts in this PR
- Sources:

## Could not verify on Linux

Cloud agents cannot compile iOS (no Xcode, SwiftUI, UIKit, AVFoundation, Vision, Core ML, or CoreBluetooth). List every app-target file this PR changes that was not compiled, and what the owner should check in Xcode. Put logic in `app/SidekickCore/` so `swift build && swift test` runs on Linux.

- Files not compiled:
- Owner should check in Xcode:
- [ ] N/A (no app-target Swift)
