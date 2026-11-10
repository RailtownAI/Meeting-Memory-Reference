# Meeting Memory

A cross-platform meeting-memory app (iOS + macOS) that captures whiteboard photos, links them
to calendar meetings, and makes them searchable. It has **independent UI per platform** and a
**shared, platform-agnostic core** for server access.

> This repo was copied from `WhiteboardApp`. The Xcode project, targets, bundle IDs, iCloud
> container and Swift types still use the `Whiteboard` / `WB` names. That is intentional:
> renaming the bundle IDs or iCloud container would disconnect existing installs from their data.

## Getting started

### Requirements

- macOS with **Xcode 26** or later (the core package uses `swift-tools-version: 6.2`)
- iOS app: iOS 18+ (device or simulator)
- macOS app: macOS 15+
- Network access to GitHub. All Swift package dependencies are public and resolve automatically.

### Build and run

```sh
git clone https://github.com/RailtownAI/Meeting-Memory-Demo.git
cd Meeting-Memory-Demo
open WhiteboardApp.xcodeproj
```

1. Wait for Xcode to finish **Resolving Package Graph**. If it fails, use
   *File → Packages → Reset Package Caches*.
2. Pick a scheme: **WhiteboardApp** (iOS) or **WhiteboardMac** (macOS). Xcode creates the
   schemes automatically on first open.
3. **Signing:** set up signing with your own Apple Developer account.
   - Sign in to Xcode with your Apple ID under *Settings → Accounts*.
   - For each target (**WhiteboardApp** and **WhiteboardMac**), open *Signing & Capabilities*,
     choose your team, and change the bundle identifier to one you own (for example,
     `com.yourname.WhiteboardApp`).
   - In both `.entitlements` files, replace the iCloud container (`iCloud.Railtown.WhiteboardApp`)
     and the keychain group (`Railtown.Whiteboard.shared`) with your own identifiers.
   - iCloud and push notifications (`aps-environment`) need a paid Apple Developer Program
     membership. A free personal team cannot sign these entitlements.
4. Build and run (⌘R).

### First-launch configuration

The repo contains no secrets. Enter the API keys in the app's **Settings** screen. They are
stored in the Keychain:

- **Gemini** API key (Google AI Studio): reads whiteboards and answers prompts
- **Railengine** token + PAT for the whiteboard engine and the calendar engine
- **Railtown Conductr** API key (optional): error-log and agent-trace uploads

The app also asks for Calendar, Contacts and (on iOS) Camera access. iCloud Drive must be signed
in, because whiteboard photos are stored in the app's iCloud container.

Server endpoints and engine IDs are in
[`WBConstants.swift`](Packages/WhiteboardCore/Sources/WhiteboardCore/WBConstants.swift). The
endpoints point to the **production** environment. Before building, set
`whiteboardEngineID` and `calendarEngineID` to the engine IDs from your Railengine environment.

## Target architecture

Two independent app targets, each with its own UI, `@main` entry point, assets, and
entitlements. Both depend on a single shared Swift package for server-accessing code.

```
┌─────────────────┐     ┌─────────────────┐
│  WhiteboardApp  │     │  WhiteboardMac  │   ← two independent app targets
│  (iOS: iPhone   │     │  (macOS)        │      each with its OWN UI, @main,
│   + iPad)       │     │                 │      assets, entitlements
└────────┬────────┘     └────────┬────────┘
         │                       │
         └───────────┬───────────┘
                     ▼
          ┌──────────────────────┐
          │   WhiteboardCore     │   ← local Swift package (shared)
          │  (models, API client,│      Foundation-only, no UIKit/AppKit,
          │   networking, auth)  │      no SwiftUI. Both targets import it.
          └──────────────────────┘
```

**Why this shape:** Two separate app targets give fully independent UI (no `#if os(...)`
branching — each platform has its own view files and `@main`). A local Swift package is
the home for shared server-accessing code — it is platform-agnostic, independently
testable, and both targets simply `import WhiteboardCore`.

## Folder layout

```
Meeting-Memory-Demo/                 (repo root)
├── WhiteboardApp.xcodeproj
├── Packages/
│   └── WhiteboardCore/              ← shared package
│       ├── Package.swift
│       └── Sources/WhiteboardCore/
├── WhiteboardApp/
│   ├── Info.plist
│   ├── iOS/                         ← iOS target sources ONLY
│   │   ├── WhiteboardAppApp.swift   (@main)
│   │   ├── WhiteboardApp.entitlements
│   │   └── Assets.xcassets
│   └── macOS/                       ← macOS target sources ONLY
│       ├── WhiteboardMacApp.swift   (@main)
│       ├── WhiteboardMac.entitlements
│       └── Assets.xcassets
└── docs/                            ← design notes and coding style
```

The `WhiteboardApp/` folder is a file-system-synchronized group: new files are picked up
automatically. The `macOS/` files are excluded from the iOS target through membership exceptions
in the project file.

## The boundary rule

- **`WhiteboardCore`** — anything platform-agnostic: server access, `URLSession` API
  client, DTOs/models, auth tokens, business logic. Foundation only.
- **iOS / macOS targets** — views, view models tied to platform idioms, navigation,
  platform APIs (`UIKit`/`AppKit`). Never imported into the package.
- If shared code *must* touch a platform API, guard it inside the package with
  `#if canImport(UIKit)` rather than leaking it into both app targets.
