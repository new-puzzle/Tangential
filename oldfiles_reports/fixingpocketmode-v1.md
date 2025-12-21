 Here is a summary of the core problems and a strategic plan to fix them. This is not a code fix, but a high-level
  roadmap for a developer to follow to correctly engineer the solution.

  Root Cause Analysis: Why It's Failing

1. Unstable Background Audio: The app uses a custom native service for audio recording (AudioCaptureService.kt). To
   save battery, the Android operating system forcefully shuts this service down when the screen is off. This is the
   main reason the app stops working in your pocket.

2. A "Keep-Alive" Hack: Instead of building the service correctly, the previous developer added a "band-aid" fix in
   the Dart code (ConversationManager.dart). It's a timer that tries to restart the dead audio service every 5
   seconds. This is extremely unreliable and is a primary source of the instability and crashes.

3. Conflicting Power Management: The app has two separate and conflicting systems trying to keep the device awake
   (Wakelock): one in the native Android code and another in the Dart code. This creates chaos and unpredictable
   behavior.

4. UI Overload: When you turn the screen on, the app frantically tries to recover from its crashed state. It triggers
   a "storm" of operations all at once—restarting audio, reconnecting to AI services, and rapidly changing the app's
   state. This overwhelms the UI, causing it to freeze.
   Strategic Plan for a Proper Fix
   The solution is to remove the hacks and rebuild the background processing a single time, the correct way, using
   Android's standard recommended practices.
   Phase 1: Remove the Unstable Foundation
* Action: Consolidate Power Management.
  
  * Why: Eliminate the conflict between the two Wakelock systems.
  * How: A developer must remove the custom wakelock code from the MainActivity.kt file and rely only on the
    standard wakelock_plus package already in the project.

* Action: Delete the "Keep-Alive" Hack.
  
  * Why: This is the main source of instability and must be removed entirely.
  * How: A developer must delete the 5-second timer logic (_startScreenOffKeepAlive) from the
    ConversationManager.dart file.
  
  Phase 2: Build a Robust and Correct Background Service

* Action: Promote the Audio Service to a "Foreground Service".
  
  * Why: This is the official Android way to tell the OS that the app is performing an important, long-running task
    (like a music player or GPS navigation) and should not be killed when the screen is off.
  * How: A developer needs to modify AudioCaptureService.kt to run as a proper Android Foreground Service. This
    will require displaying a persistent notification in the Android status bar while pocket mode is active, which
    is standard and expected behavior for apps of this kind.

* Action: Centralize Control.
  
  * Why: The Dart code should be the single source of truth for starting and stopping the service.
  * How: The ConversationManager.dart file should be updated to directly and cleanly start and stop the new, stable
    Foreground Service, removing all the broken recovery logic.
  
  Phase 3: Ensure a Smooth and Responsive UI

* Action: Simplify State Management.
  
  * Why: With a stable background service, the UI no longer has to handle a "storm" of chaotic updates.
  * How: A developer can now simplify the code in app_state.dart and the UI widgets. The app will transition
    smoothly between states (e.g., listening, speaking, idle) without freezing, as it will be receiving predictable
    updates from the stable service.
  
  This plan addresses the deep architectural flaws you've been dealing with. It's a roadmap to make the application
  reliable and perform the core function you originally wanted.
