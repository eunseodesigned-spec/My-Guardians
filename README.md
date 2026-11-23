# My Guardians

**A playful iOS prototype that turns everyday objects into little companions.**

My Guardians explores a simple idea: the objects we keep can carry personal meaning. What if we could give them characters, find them again, and build memories around them?

Using a camera, drawing tools, and a personal collection, the app lets people create a guardian for a familiar object and revisit it later.

## Experience

1. **Meet a new friend:** Capture an everyday object and isolate it from its background.
2. **Bring it to life:** Draw directly on the object, name the guardian, and save it.
3. **Find an old friend:** Return to the camera to look for a saved guardian.
4. **Capture a memory:** Position the drawing over the camera view and save a moment with optional details.
5. **Visit the shelf:** Browse saved guardians and their memories.

## Design and AI-assisted development

This project followed a designer-led, AI-assisted workflow:

| Phase | Design decisions and manual work | AI assistance |
| --- | --- | --- |
| Explore | Chose the concept and defined the intended emotional experience | ChatGPT-supported brainstorming and alternatives |
| Define | Created sketches, user flows, and wireframes | Feasibility questions, requirements and PRD structuring, timeline planning |
| Design | Built a hand-drawn visual system in Figma, including custom illustrations and SVG assets | Translated design decisions into implementation instructions |
| Build | Specified interaction behavior, visual constraints, and trade-offs | Codex-assisted SwiftUI implementation |
| Evaluate | Tested screens in the simulator and on a physical iPhone; reviewed screenshots and behavior | Debugging assistance and targeted implementation changes |
| Refine | Corrected spacing, icon consistency, keyboard/safe-area behavior, and camera-overlay alignment | Implemented and revised focused changes |

**AI accelerated exploration and execution. The product direction, design judgment, and evaluation remained human-led.**

## Prototype scope and limitations

- This is an **iOS SwiftUI prototype**, not a web app or an App Store release.
- Camera capture, drawing, navigation, and saved-guardian flows are the central prototype experiences.
- **Object recognition should be evaluated separately from the demo experience.** Some test flows may use a timed fallback that displays the most recently saved guardian rather than a verified live-camera match. A fallback is not evidence of production-grade recognition.
- The experience is intended to demonstrate a concept and its interactions, not to claim production readiness.

## Run on an iPhone

**Requirements:** A Mac with a compatible Xcode installation, an iPhone, and an Apple Account configured for development signing.

1. Clone this repository and open its Xcode project (`.xcodeproj` or `.xcworkspace`, depending on the checked-in project structure).
2. Select the app target in Xcode, open **Signing & Capabilities**, and configure your development team.
3. Connect and unlock an iPhone, and select it as the run destination.
4. Press **Command-R** to build and run. Approve device trust or Developer Mode if iOS requests it.
5. Grant requested camera or photo permissions when needed.

## Project context

My Guardians is a personal product-design exploration, developed with AI assistance for ideation, planning, coding, and debugging. The project showcases the iterative process of moving from sketches and Figma wireframes to a native prototype, with design evaluation at each step.
