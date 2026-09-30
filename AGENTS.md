<!-- BEGIN:swift-agent-rules -->
# This is NOT the Swift you know

This project's Swift version, Xcode version, and Apple SDKs may have breaking changes: APIs, concurrency rules, framework conventions, and project structure may all differ from your training data.

**MANDATORY: READ `Mandatory.md` FIRST**

Before doing **anything else**, you MUST locate and completely read the project's `Mandatory.md` file (in the project root, next to the `.xcodeproj`, `.xcworkspace`, or `Package.swift`).

**DO NOT write code, inspect other project files, run commands, add packages, modify files, or make any changes until `Mandatory.md` has been read and understood.**

`Mandatory.md` contains mandatory project-specific instructions and must be followed throughout the entire task.

If `Mandatory.md` cannot be found or read, **STOP immediately** and report that it could not be found or read. Do not continue based on assumptions.

After reading `Mandatory.md`:

1. Check the project's actual toolchain before writing any Swift code: Swift language version, Xcode version, and deployment targets (in `Package.swift`, `.xcodeproj` build settings, or `.swift-version`).
2. Treat the installed SDKs and the local documentation (Xcode's documentation viewer and the framework headers) as the source of truth.
3. Do not rely on your training data when it conflicts with the installed toolchain. Do not use APIs newer than the project's deployment target without an availability check (`#available` or `@available`).
4. Heed all deprecation warnings, availability annotations, and Swift concurrency or strict-checking diagnostics.
5. Follow the project's existing conventions: architecture (MVVM, TCA, etc.), UI framework (SwiftUI or UIKit), dependency manager (SwiftPM, CocoaPods, or Carthage), naming, and file and folder structure.
6. Before modifying any file, inspect and understand the existing implementation.
7. Make the smallest necessary changes. Do not modify unrelated files, and do not hand-edit generated files such as `project.pbxproj` unless there is no alternative.
8. Verify your changes after implementation: build the project (`xcodebuild` or `swift build`), run the relevant tests (`xcodebuild test` or `swift test`), and fix any new warnings or errors you introduced.

**Required order:**

`Mandatory.md` → toolchain and local docs → inspect relevant project files → implement → build and test

**Never skip these steps or assume the contents of `Mandatory.md` or the installed SDK documentation.**

<!-- END:swift-agent-rules -->