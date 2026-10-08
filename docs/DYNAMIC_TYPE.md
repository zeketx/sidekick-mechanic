# Dynamic Type

Sidekick is used in a garage, often with large text. **Accessibility XXXL** (AXXXL) is a layout, not a zoomed default layout.

Launch argument: `-dynamicTypeSize accessibility5`. SwiftUI size: `.accessibility5` (`dynamicTypeSize.isAccessibilitySize` is true from AX1 up). The verify harness also sends that flag on every sheet and cover. Sheets do not reliably inherit the root environment, so `AccessibilityLaunchModifier` has to sit on the sheet itself (`CitationSheet`, the garage sheet, the highlight cover). Dropping the flag or the modifier leaves the sheet at the system size while the screen behind it grows. That miss has shipped before.

## Check both sizes

Every screen is designed at the **default** size and at **AXXXL**. UI proofs use both. A default-size screenshot does not cover this rule.

New screen tests in `DriveUITests` call `assertFitsOnScreen(app, screen:)` after the screen is showing at AXXXL. The bundled test `testAccessibilityXXXLHeaderAndHalfSheet` does that for chat, onboarding, the job sheet (half, full, closeout), the citation sheet, and — when those files exist — Jobs and Scan log. It writes `taps/layout-axxxl.json`. `design_checks.py` turns overflow, island overlap, an ellipsis in the accessibility label, and a narrow-column wrap into checklist **FAIL** (verify exit **3** when the taps themselves passed). The same assertions fail the XCUITest (verify exit **1**).

```swift
let app = XCUIApplication()
app.launchArguments = [
    "-sidekick.onboarding.completed", "YES",
    "-screen", "job-history",
    "-dynamicTypeSize", "accessibility5",
]
app.launch()
assertFitsOnScreen(app, screen: "job-history")
```

`assertFitsOnScreen` lives on `DriveUITests`. Thresholds match `measure_axxxl` in `.cursor/skills/verify-sidekick/scripts/design_checks.py`.

## Header and toolbar buttons

At accessibility sizes, a header with **two or more text buttons** collapses. Use icon-only buttons with accessibility labels, or one overflow menu. One text button plus a title is fine when the title has the full width. Do not keep "Back", "Jobs", and "Scan log" (or "Close" plus a long title) in one shrinking row.

```swift
if dynamicTypeSize.isAccessibilitySize {
    HStack(alignment: .top, spacing: 8) {
        Text(title)
            .font(.headline)
            .wrapsWords(maxLines: 3)
            .frame(maxWidth: .infinity, alignment: .leading)
        Button(action: close) {
            Image(systemName: "xmark")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Close")
        .buttonStyle(.plain)
    }
} else {
    HStack {
        Text(title).font(.headline)
        Spacer()
        Button("Close", action: close).buttonStyle(.plain)
    }
}
```

`wrapsWords` is on `View` in `SidekickMechanicApp.swift`: word wrap, no `minimumScaleFactor`.

## List rows

A row that is label plus value, or title plus date plus badge, switches to a **vertical** stack at accessibility sizes. `ViewThatFits` only works when the horizontal candidate uses `fixedSize(horizontal: true, vertical: false)`. Without that, the horizontal row "fits" by truncating and `ViewThatFits` never switches. Branching on `dynamicTypeSize.isAccessibilitySize` is the predictable choice.

```swift
if dynamicTypeSize.isAccessibilitySize {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline).wrapsWords(maxLines: 2)
        Text(date).font(.subheadline).foregroundStyle(.secondary)
    }
} else {
    HStack {
        Text(title)
        Spacer()
        Text(date)
    }
}
```

Horizontal chip or tag scrolls do the same: a `VStack` at accessibility sizes. A chip left in a horizontal scroll is wider than the phone at AXXXL and fails `assertFitsOnScreen`.

## Words stay whole

- Wrap on word boundaries (`wrapsWords` / `lineLimit` greater than 1 plus `fixedSize(horizontal: false, vertical: true)`).
- Do not use `lineLimit(1)` on titles, dates, or row values at accessibility sizes. That is how "Today" becomes "Tod…" and how a title breaks as "Ma / nu…".
- `minimumScaleFactor` is a last resort after the layout has already changed, not the way a header is made to fit.
- A single token wider than the screen may still hyphenate. Prefer a shorter label or a stack over scaling.

## Safe area

Nothing tappable and no header title sits under the status bar or the Dynamic Island. Full-height sheets keep their title and Close below that inset (`JobSheetLayout.contentTopInset` / `accessibilityHalfTopGap`). Do not draw a custom header in the top inset. Bottom sheets still show their key controls at AXXXL: Close, the outcome segments, the last step, and Go deeper (scroll the body if the block is tall; do not clip it).

## What fails automatically

On each main screen at AXXXL, `assertFitsOnScreen` and `measure_axxxl` **FAIL** when:

- A visible element's frame extends past the window horizontally (tolerance 2pt).
- A button, a header (title, close, skip, garage, back), or unlabeled text intersects the top safe-area inset. Full-screen scrims (`jobSheet.dim`) and status-bar chrome (clock, signal) are ignored. Scrolling the answer does not fail this check.
- Two header controls in the top band overlap by more than 4pt (the "Garage" over "Sidekick" bug). A control that fully contains its own label does not count.
- The accessibility label contains `…` or `...`.
- A long token is squeezed into a column narrower than 72pt and taller than 1.35× its width (mid-word wrap proxy).

Jobs and Scan log are skipped, not failed, while `JobHistoryView.swift` / `ScanLogView.swift` are absent. When those screens are in the checkout they are checked like the others. PR #114 (`cursor/job-history-scan-log-a9cc`) is being fixed separately. These checks are expected to fail on that branch until its headers and rows follow this page. Do not weaken the checks to match it.

## What a screenshot still has to catch

XCUITest reads the accessibility label. SwiftUI usually keeps the full string when it draws "Tod…" or hyphenates "Bat- / tery". The narrow-column proxy and the ellipsis check do not see that. They are a backstop, not the proof.

Every UI PR opens the AXXXL shots and marks the large-text checklist row **PASS** or **FAIL**:

- `screenshots/axxxl/<screen>.png` (harness, flag on the screen and the sheet)
- `taps/taps-<screen>-axxxl.png`

Fail the row if a word is broken (`Ma / nu…`, `Col / d i…`, `Bat- / tery l…`) or a date is cut (`Tod…`). `design_checks.py` leaves that row at **REVIEW** when the geometry passed, so it cannot be skipped as an automatic pass. verify-sidekick's large-text section is mandatory on any UI change.
