# My Guardians

**A playful iOS prototype that turns everyday objects into little companions.**

My Guardians explores the personal meaning of familiar objects through photography, drawing, and small moments of reconnection. Photograph an object, draw its guardian, and build a collection of characters and memories.

## Experience

- **Meet a new friend:** Capture an object and isolate its foreground with Vision.
- **Bring it to life:** Draw with PencilKit, name the guardian, and save its artwork.
- **Find an old friend:** Compare the camera view with registered object images and confirm a guardian.
- **Capture a memory:** Move, resize, and rotate the guardian drawing over the camera, then save a photo with an optional location and note.
- **Home and Shelf:** Watch guardians wander around their illustrated home, browse profiles and memories, and edit or delete saved guardians.

## Design process

The experience follows a designer-led, AI-assisted workflow:

1. Explore the relationship between everyday objects, attachment, and character.
2. Define the interaction flow through sketches and wireframes.
3. Develop a hand-drawn visual system in Figma, with custom illustrations, irregular black outlines, Patrick Hand typography, and butter-yellow accents.
4. Translate the designs into SwiftUI components and native camera and drawing interactions.
5. Evaluate the prototype in the iPhone Simulator and on a physical iPhone, refining spacing, navigation, gestures, and image alignment.

Product direction, visual design, interaction decisions, and evaluation were human-led. ChatGPT supported ideation and requirements; Codex assisted implementation and debugging.

## Technical implementation

| Area | Implementation |
| --- | --- |
| Interface | SwiftUI screens, reusable sketch components, and vector PDF asset catalogs |
| Camera | AVFoundation preview and frame capture, with image processing on a dedicated queue |
| Object preparation | Vision foreground isolation and reference-image feature prints |
| Drawing | PencilKit strokes, erasing, undo, and transparent drawing exports |
| Photo composition | Preview-aware aspect-fill cropping with shared overlay position, scale, and rotation |
| Persistence | A local JSON catalog and image/stroke files managed by `GuardianStore` |
| Optional location | Core Location and reverse geocoding, requested through the memory form |
| Ambient motion | Deterministic guardian wandering within the illustrated house |

### Project structure

```text
MyGuardians.xcodeproj/    Xcode project and shared MyGuardians scheme
MyGuardians/
  MyGuardiansApp.swift    SwiftUI entry point
  Design/                Shared styling, artwork views, motion, and preview fixtures
  Models/                Guardian, memory, and capture models
  Resources/             Artwork catalogs, Patrick Hand font, and font license
  Services/              Camera, Vision matching, storage, and optional location
  Views/                 Home, Find, creation, profile, Shelf, and memory screens
project.yml              XcodeGen project specification
```

The bundle identifier is `com.objectguardians.prototype.b`. Guardians and memories remain in the app sandbox under `Documents/ObjectGuardians`; the project name does not change this storage location. Camera and location permissions are requested when needed. The app does not implement cloud synchronization.

## Run locally

Requires macOS, Xcode with an iOS SDK, and an iPhone running iOS 17 or later for live-camera testing. The project has been built with Xcode 27.2.

1. Clone the repository and open `MyGuardians.xcodeproj`.
2. Select the **MyGuardians** scheme and target.
3. For a physical iPhone, choose your development team under **Signing & Capabilities**, connect and unlock the device, and enable Developer Mode if requested.
4. Select the device and press **Command-R**. Grant camera permission to use live capture; location remains optional.

The checked-in project has no personal development team configured. XcodeGen is optional: the generated Xcode project and shared scheme are already included.

To verify a Simulator build without signing:

```sh
xcodebuild -project MyGuardians.xcodeproj \
  -scheme MyGuardians \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Prototype scope

- Vision feature-print matching depends on viewpoint, framing, and lighting; it is not semantic object identification or 3D tracking.
- Recognition includes a one-time five-second fallback that suggests the most recently added guardian if no match appears. This suggestion is not a verified camera detection.
- Demo and manual-preview actions are available through the Information menu. Evaluate these separately from live recognition.
- The drawing is a movable 2D camera overlay, not a world-anchored AR object.
- The Simulator does not provide the live-camera experience. Use a physical iPhone to evaluate capture and recognition.

This prototype demonstrates the concept and interaction design; it is not an App Store release or a production recognition system.

## Typography and artwork

Patrick Hand is bundled with its copyright notice and [SIL Open Font License](MyGuardians/Resources/OFL.txt). Custom hand-drawn interface artwork is included in the asset catalogs. The font license applies to the font; it does not grant a license to the app source or custom artwork.
