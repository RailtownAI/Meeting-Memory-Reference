# Coding Style

Swift coding conventions for WhiteboardApp (iOS app, macOS app, and `WhiteboardCore`).
Adapted from the Railtracks-swift project's conventions.

- **Type/file name prefix (platform-scoped).** Every type you define — `struct`, `class`, `enum`, `actor`, `protocol` — and the file it lives in carry a prefix that reflects **which module it belongs to**:
  - **`WB`** — shared code in `WhiteboardCore` (e.g. `WBCoreModel` in `WBCoreModel.swift`, `WBKeychainStore`).
  - **`WBiOS`** — the iOS app target (e.g. `WBiOSRootTabView`, `WBiOSSearchView`).
  - **`WBmacOS`** — the macOS app target (e.g. `WBmacOSRootView`).

  This prevents symbol collisions with third-party libraries (notably RailtracksSwift's `RTS…` types) and makes it obvious at a glance which module a type belongs to. Nested types inside an already-prefixed type don't repeat it. The Xcode-generated `@main` app entry points (`WhiteboardAppApp`, `WhiteboardMacApp`) keep their generated names.
- **No abbreviated variable names** when a clear full name is available. Prefer `detail`, `index`, `content`, `message` over `d`, `idx`, `c`, `m`. Idiomatic short names (`id`) and closure shorthand (`$0`) in trivial one-liners are fine.
- **One statement per line.** Do not chain statements with `;` (e.g. no `self.a = a; self.b = b` — split into separate lines).
- **No single-line function declarations.** A function/initializer/computed-property *declaration* always puts its body on its own line(s):

```swift
public init(epoch: TimeInterval) {
    self.epoch = epoch
}
```

  Not `public init(epoch: TimeInterval) { self.epoch = epoch }`. This applies only to declarations — inline closures at *call sites* (e.g. `items.map { $0.name }`) may stay on one line.
- **Parameter lists** (declarations *and* call sites) must not be grouped unevenly across lines (e.g. 2 on one line, then 3 on the next). Pick one of:
  - **All on one line** when the whole declaration/call line fits within **100 characters**.
  - **One parameter per line** when a single line would exceed 100 characters, in Xcode "⌃M" layout: the opening `(` stays on the declaration/call line, each parameter is on its own line, and the closing `)` is on its **own** line (before ` {`, or before the call's trailing `)`). Never place the first parameter on the `(` line, and never leave the closing `)` on the same line as the last parameter.

Example of the multi-line form:

```swift
public init(
    name: String,
    identifier: String,
    categories: [String]
) {
    self.name = name
    self.identifier = identifier
    self.categories = categories
}
```

- **Modifier order.** When any declaration carries multiple modifiers — properties, computed
  properties, subscripts, methods, or types — order them by category:
  1. **Access control** — `open`, `public`, `internal`, `fileprivate`, `private`
  2. **Overriding / finality** — `override`, `final`
  3. **Type-level** — `static`, `class`
  4. **Mutation** — `mutating`, `nonmutating`
  5. **Isolation** — `nonisolated`, `isolated`

  Include only the modifiers a declaration actually has, in this relative order (skip empty categories):

```swift
private mutating nonisolated func updateState() {   // method: access → mutation → isolation
    // …
}

public static let shared = Registry()               // property: access → type-level
```

## Comments

- **Never cite the design doc from code.** No `see §9 #12`, no `docs/project-design.md`, no ticket
  numbers standing in for an explanation. Section numbers shift as items are added, and the doc may
  be rewritten or retired entirely — a comment pointing at a `§9 #12` that no longer exists is worse
  than no comment, because the reader can't tell whether the reasoning was lost or was never right.
  Write the reason out **in full, in the comment**, so it survives on its own:

```swift
// BAD — dies with the doc
// Keeps manual items; see §9 #12.

// GOOD — self-contained
// This runs more than once for the *same* photo: `.task` re-fires whenever the view reappears,
// so a typed item still describes the board on screen and has to survive.
```

  The design doc is for design rationale that spans the codebase; a comment explains the code in
  front of you. If a decision is genuinely too large to restate, summarize the *conclusion* and the
  one fact that makes it true — not a pointer.

- **Referencing code is encouraged.** Naming types, functions, and properties (`setImage`,
  `WBWhiteboardSaveService.makeIDs()`) is fine and preferred: those are checkable, and a rename that
  breaks them is visible in review in a way a stale section number never is.

## Logging

Use the shared **`WBLog`** facade (in `WhiteboardCore`, swift-log backed) for all logging — do not
use `print(...)` or create `Logger` instances directly.

```swift
import WhiteboardCore

WBLog.trace("entered matchMeeting(for:)")     // fine-grained flow
WBLog.debug("resolved iCloud container \(url)") // developer diagnostics
WBLog.info("Ingested record \(id)")            // notable events
WBLog.warning("No calendar match for \(id)")   // recoverable problems
WBLog.error("Ingest failed: \(error)")         // failures
```

- Core code can call `WBLog` directly (same module); app code needs `import WhiteboardCore`
  (usually already present).
- `WBLog.setup()` is called **once per app** in the `App` init — don't call it anywhere else.
- Levels shown above, from most to least verbose; DEBUG builds log `.debug` and up, release logs
  `.info` and up.

## Architecture — MVVM

New, non-trivial views use MVVM so logic stays out of the `View`.

- Each screen has an **`@Observable @MainActor final class` view model** named `<View>ViewModel`
  (e.g. `WBiOSHomeViewModel` backs `WBiOSHomeView`).
- The **view model owns state and logic** — data, presentation flags (which sheet/dialog is shown),
  and the handlers that react to user actions or async results.
- The **view is declarative only**: it renders from the view model and forwards intent by calling
  view-model methods. It owns the model with `@State private var viewModel = <View>ViewModel()`.
- UIKit bridges (`UIViewControllerRepresentable`, `PhotosPicker` glue, …) stay in the view layer as
  thin wrappers that hand their result back to the view model.
- Trivial or throwaway views (placeholders, spikes) don't need a view model.
