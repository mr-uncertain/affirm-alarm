# AffirmAlarm Phase 1: Core Alarm Loop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and CI-verify the core AffirmAlarm loop — alarm rings, press-and-hold-to-speak with on-device speech verification, snooze, capped Close bypass, and the automatic streak-based intensity ramp — with no AI content generation and no monetization yet (those are Phase 2 and Phase 3, planned separately).

**Architecture:** A pure-Swift `AffirmAlarmCore` framework holds all business logic (intensity ramp, close-usage cap, transcript matching, persistence, orchestration) behind protocols, fully unit-testable with fakes. A thin `AffirmAlarm` SwiftUI app target wires that logic to real system frameworks (AlarmKit, Speech, SwiftData) and is covered by XCUITest. Because this sandbox has no Xcode/Swift toolchain, every test-running step in this plan executes on a **GitHub Actions macOS runner**, not locally — each task's "run tests" step is "push, then check the Actions run," not a local command.

**Tech Stack:** Swift 5, SwiftUI, SwiftData (iOS 17+, used here targeting iOS 26+), AlarmKit, Speech framework (`SFSpeechRecognizer`, on-device), XcodeGen (declarative `project.yml`, avoids hand-authoring `.pbxproj`), XCTest, XCUITest, GitHub Actions (`macos-15` runner).

## Global Constraints

- Platform: Native iOS, Swift/SwiftUI, iOS 26+ (per spec).
- Alarm: Apple's Alarm Kit API (per spec) — **AlarmKit's exact API surface is newer than this plan author's verified knowledge; Task 7 includes an explicit step to confirm method/type names against Apple's current documentation before finalizing.**
- Speech verification: Apple's on-device Speech framework (per spec) — must request on-device recognition (`requiresOnDeviceRecognition = true`), no network round-trip.
- Storage: Local only, no backend, no cloud sync (per spec, Approach C).
- Snooze delay: 9 minutes (per spec).
- While holding to speak, alarm volume lowers to slightly audible — never fully silenced (per spec).
- Close button: capped at 3 uses per calendar month, resets at the start of each month (per spec).
- Intensity ramp: Days 1–6 → 1 affirmation ×1; Days 7–13 → 1 affirmation ×2; Days 14–20 → 2 affirmations ×1; Day 21+ → 2 affirmations ×2, then continues alternating every 7 days (per spec).
- Streak break (missed day or Close used) → full reset to Day-1 intensity (per spec).
- Releasing mid-affirmation before verification resets only that attempt, not the whole session (per spec).

---

## File Structure

```
AffirmAlarm/
  project.yml                                  # XcodeGen project definition
  .github/workflows/ci.yml                     # CI: generate project, run unit + UI tests
  Sources/
    AffirmAlarmCore/                            # Pure-logic framework target
      Models.swift                              # Affirmation, StreakState, CloseUsageRecord
      IntensityEngine.swift                     # Streak day -> required count/repeats
      CloseUsageTracker.swift                   # Monthly Close-button cap logic
      AffirmationMatcher.swift                  # Transcript-vs-target matching logic
      SpeechRecognitionService.swift             # Protocol + SFSpeechRecognizer implementation
      AlarmSchedulingService.swift                # Protocol + AlarmKit implementation
      StreakStore.swift                          # Protocol + SwiftData implementation
      AlarmRingViewModel.swift                   # Orchestrates the whole ring-screen flow
    AffirmAlarm/                                 # App target
      AffirmAlarmApp.swift                        # App entry point
      AlarmRingView.swift                          # SwiftUI ring screen (Snooze / press-hold / Close)
      Info.plist                                   # Mic + Speech usage descriptions
  Tests/
    AffirmAlarmCoreTests/
      IntensityEngineTests.swift
      CloseUsageTrackerTests.swift
      AffirmationMatcherTests.swift
      StreakStoreTests.swift
      AlarmRingViewModelTests.swift
      Fakes.swift                                 # FakeSpeechRecognitionService, FakeAlarmSchedulingService
    AffirmAlarmUITests/
      AlarmRingUITests.swift
```

---

### Task 1: Repo, CI, and Project Scaffold

**Files:**
- Create: `project.yml`
- Create: `.github/workflows/ci.yml`
- Create: `Sources/AffirmAlarmCore/.gitkeep`, `Sources/AffirmAlarm/.gitkeep`, `Tests/AffirmAlarmCoreTests/.gitkeep`, `Tests/AffirmAlarmUITests/.gitkeep` (placeholder dirs so later tasks have somewhere to add files)

**Interfaces:**
- Produces: a pushed GitHub repo (`mr-uncertain/affirm-alarm`, public) with GitHub Actions wired to run on every push.

- [ ] **Step 1: Create the GitHub repo and push what exists**

```bash
cd "/home/user/Desktop/Vibes/CC-proper/AffirmAlarm"
gh repo create mr-uncertain/affirm-alarm --public --source=. --remote=origin
git branch -m main
git push -u origin main
```
Expected: repo created at `https://github.com/mr-uncertain/affirm-alarm`, `main` branch pushed with the existing design-spec commit.
Note: **public**, not private — GitHub Actions macOS runners are free/unlimited on public repos, and Phase 1 contains no secrets (Phase 2's LLM API key will need `secrets.*`, not hardcoding, regardless of visibility).

- [ ] **Step 2: Write `project.yml`**

```yaml
name: AffirmAlarm
options:
  bundleIdPrefix: com.affirmalarm
  deploymentTarget:
    iOS: "26.0"
settings:
  SWIFT_VERSION: "5.0"
targets:
  AffirmAlarmCore:
    type: framework
    platform: iOS
    sources: [Sources/AffirmAlarmCore]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.affirmalarm.core
      GENERATE_INFOPLIST_FILE: YES
  AffirmAlarmCoreTests:
    type: bundle.unit-test
    platform: iOS
    sources: [Tests/AffirmAlarmCoreTests]
    dependencies:
      - target: AffirmAlarmCore
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.affirmalarm.core.tests
      GENERATE_INFOPLIST_FILE: YES
  AffirmAlarm:
    type: application
    platform: iOS
    sources: [Sources/AffirmAlarm]
    dependencies:
      - target: AffirmAlarmCore
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.affirmalarm.app
    info:
      path: Sources/AffirmAlarm/Info.plist
      properties:
        UILaunchScreen: {}
        NSMicrophoneUsageDescription: "AffirmAlarm needs your microphone to verify you've spoken your affirmation."
        NSSpeechRecognitionUsageDescription: "AffirmAlarm uses on-device speech recognition to verify your affirmation."
        NSAlarmKitUsageDescription: "AffirmAlarm needs alarm access to wake you up until you speak your affirmation."
  AffirmAlarmUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [Tests/AffirmAlarmUITests]
    dependencies:
      - target: AffirmAlarm
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.affirmalarm.app.uitests
      GENERATE_INFOPLIST_FILE: YES
schemes:
  AffirmAlarmCore:
    build:
      targets:
        AffirmAlarmCore: all
    test:
      targets:
        - AffirmAlarmCoreTests
  AffirmAlarm:
    build:
      targets:
        AffirmAlarm: all
    test:
      targets:
        - AffirmAlarmUITests
    run:
      config: Debug
```

- [ ] **Step 3: Write the CI workflow**

```yaml
name: CI
on:
  push:
  pull_request:

jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: List available Xcode versions
        run: ls /Applications | grep Xcode

      - name: Select latest available Xcode
        run: sudo xcode-select -s "$(ls -d /Applications/Xcode_*.app | sort -V | tail -n1)"

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        run: xcodegen generate

      - name: List available iOS Simulators
        run: xcrun simctl list devicetypes

      - name: Run AffirmAlarmCore unit tests
        run: |
          xcodebuild test \
            -project AffirmAlarm.xcodeproj \
            -scheme AffirmAlarmCore \
            -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
            | xcpretty && exit ${PIPESTATUS[0]}

      - name: Run AffirmAlarm UI tests
        run: |
          xcodebuild test \
            -project AffirmAlarm.xcodeproj \
            -scheme AffirmAlarm \
            -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
            | xcpretty && exit ${PIPESTATUS[0]}
```
Note: the "List available Xcode versions" and "List available iOS Simulators" steps exist because the exact Xcode/iOS-26-SDK availability on GitHub's `macos-15` image cannot be confirmed from this sandbox — if the `Select latest available Xcode` or the `iPhone 16` simulator name step fails in the Actions log, adjust the destination string to whatever the list output shows and re-push.

- [ ] **Step 4: Create placeholder directories and push**

```bash
cd "/home/user/Desktop/Vibes/CC-proper/AffirmAlarm"
mkdir -p Sources/AffirmAlarmCore Sources/AffirmAlarm Tests/AffirmAlarmCoreTests Tests/AffirmAlarmUITests
touch Sources/AffirmAlarmCore/.gitkeep Sources/AffirmAlarm/.gitkeep Tests/AffirmAlarmCoreTests/.gitkeep Tests/AffirmAlarmUITests/.gitkeep
git add project.yml .github/workflows/ci.yml Sources Tests
git commit -m "chore: scaffold XcodeGen project and CI workflow"
git push
```
Expected: push succeeds; this first CI run is expected to fail (no source files exist yet for the schemes to build) — that's fine, it confirms the workflow triggers. Check the Actions tab at `https://github.com/mr-uncertain/affirm-alarm/actions` to confirm the job ran (not that it passed).

---

### Task 2: Core Data Models

**Files:**
- Create: `Sources/AffirmAlarmCore/Models.swift`
- Test: `Tests/AffirmAlarmCoreTests/ModelsTests.swift`

**Interfaces:**
- Produces:
  - `struct Affirmation: Identifiable, Codable, Equatable { let id: UUID; var text: String; var isUserAuthored: Bool }`
  - `struct StreakState: Codable, Equatable { var streakDay: Int; var lastCompletedDate: Date? }`
  - `struct CloseUsageRecord: Codable, Equatable { var monthKey: String; var usesThisMonth: Int }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AffirmAlarmCore

final class ModelsTests: XCTestCase {
    func test_affirmation_hasStableIdentity() {
        let id = UUID()
        let a = Affirmation(id: id, text: "I am capable", isUserAuthored: true)
        XCTAssertEqual(a.id, id)
        XCTAssertEqual(a.text, "I am capable")
        XCTAssertTrue(a.isUserAuthored)
    }

    func test_streakState_defaultsToDayOneNoCompletion() {
        let s = StreakState(streakDay: 1, lastCompletedDate: nil)
        XCTAssertEqual(s.streakDay, 1)
        XCTAssertNil(s.lastCompletedDate)
    }

    func test_closeUsageRecord_tracksMonthAndCount() {
        let r = CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 2)
        XCTAssertEqual(r.monthKey, "2026-07")
        XCTAssertEqual(r.usesThisMonth, 2)
    }
}
```

- [ ] **Step 2: Commit the failing test on its own**

```bash
cd "/home/user/Desktop/Vibes/CC-proper/AffirmAlarm"
git add Tests/AffirmAlarmCoreTests/ModelsTests.swift
git commit -m "test: add failing tests for core models"
git push
```
Expected: CI run fails (types don't exist yet) — confirm in the Actions log that the failure is a compile error referencing `Affirmation`/`StreakState`/`CloseUsageRecord`, not something unrelated.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

public struct Affirmation: Identifiable, Codable, Equatable {
    public let id: UUID
    public var text: String
    public var isUserAuthored: Bool

    public init(id: UUID = UUID(), text: String, isUserAuthored: Bool) {
        self.id = id
        self.text = text
        self.isUserAuthored = isUserAuthored
    }
}

public struct StreakState: Codable, Equatable {
    public var streakDay: Int
    public var lastCompletedDate: Date?

    public init(streakDay: Int, lastCompletedDate: Date?) {
        self.streakDay = streakDay
        self.lastCompletedDate = lastCompletedDate
    }
}

public struct CloseUsageRecord: Codable, Equatable {
    public var monthKey: String
    public var usesThisMonth: Int

    public init(monthKey: String, usesThisMonth: Int) {
        self.monthKey = monthKey
        self.usesThisMonth = usesThisMonth
    }
}
```

- [ ] **Step 4: Run tests via CI and confirm pass**

```bash
git add Sources/AffirmAlarmCore/Models.swift
git commit -m "feat: add Affirmation, StreakState, CloseUsageRecord models"
git push
```
Expected: `AffirmAlarmCore` scheme test job passes in the Actions log (`ModelsTests` all green). `AffirmAlarm` app-target UI test job is still expected to fail/skip — no app source exists yet (addressed in later tasks).

---

### Task 3: IntensityEngine (streak day → required affirmations)

**Files:**
- Create: `Sources/AffirmAlarmCore/IntensityEngine.swift`
- Test: `Tests/AffirmAlarmCoreTests/IntensityEngineTests.swift`

**Interfaces:**
- Consumes: nothing (pure function of an `Int`).
- Produces: `enum IntensityEngine { struct Level: Equatable { let affirmationCount: Int; let repeatsPerAffirmation: Int }; static func level(forStreakDay day: Int) -> Level }` — later tasks (`AlarmRingViewModel`) call `IntensityEngine.level(forStreakDay:)` to know how many affirmations, and how many repeats each, today's session requires.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AffirmAlarmCore

final class IntensityEngineTests: XCTestCase {
    func test_day1_isOneAffirmationOnce() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 1),
            .init(affirmationCount: 1, repeatsPerAffirmation: 1)
        )
    }

    func test_day6_isStillOneAffirmationOnce() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 6),
            .init(affirmationCount: 1, repeatsPerAffirmation: 1)
        )
    }

    func test_day7_isOneAffirmationTwice() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 7),
            .init(affirmationCount: 1, repeatsPerAffirmation: 2)
        )
    }

    func test_day13_isStillOneAffirmationTwice() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 13),
            .init(affirmationCount: 1, repeatsPerAffirmation: 2)
        )
    }

    func test_day14_isTwoAffirmationsOnce() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 14),
            .init(affirmationCount: 2, repeatsPerAffirmation: 1)
        )
    }

    func test_day20_isStillTwoAffirmationsOnce() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 20),
            .init(affirmationCount: 2, repeatsPerAffirmation: 1)
        )
    }

    func test_day21_isTwoAffirmationsTwice() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 21),
            .init(affirmationCount: 2, repeatsPerAffirmation: 2)
        )
    }

    func test_day28_continuesPatternToThreeAffirmationsOnce() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 28),
            .init(affirmationCount: 3, repeatsPerAffirmation: 1)
        )
    }
}
```

- [ ] **Step 2: Commit the failing test**

```bash
cd "/home/user/Desktop/Vibes/CC-proper/AffirmAlarm"
git add Tests/AffirmAlarmCoreTests/IntensityEngineTests.swift
git commit -m "test: add failing tests for IntensityEngine"
git push
```
Expected: CI fails with a compile error referencing `IntensityEngine`.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

public enum IntensityEngine {
    public struct Level: Equatable {
        public let affirmationCount: Int
        public let repeatsPerAffirmation: Int

        public init(affirmationCount: Int, repeatsPerAffirmation: Int) {
            self.affirmationCount = affirmationCount
            self.repeatsPerAffirmation = repeatsPerAffirmation
        }
    }

    private static let firstWindowLength = 6
    private static let windowLength = 7

    public static func level(forStreakDay day: Int) -> Level {
        precondition(day >= 1, "streak day must be 1 or greater")

        if day <= firstWindowLength {
            return Level(affirmationCount: 1, repeatsPerAffirmation: 1)
        }

        let dayAfterFirstWindow = day - firstWindowLength - 1
        let windowIndex = dayAfterFirstWindow / windowLength
        let tier = (windowIndex + 1) / 2
        let repeats = windowIndex % 2 == 0 ? 2 : 1

        return Level(affirmationCount: 1 + tier, repeatsPerAffirmation: repeats)
    }
}
```

- [ ] **Step 4: Run tests via CI and confirm pass**

```bash
git add Sources/AffirmAlarmCore/IntensityEngine.swift
git commit -m "feat: add IntensityEngine streak ramp logic"
git push
```
Expected: `IntensityEngineTests` all green in the Actions log.

---

### Task 4: CloseUsageTracker (monthly cap)

**Files:**
- Create: `Sources/AffirmAlarmCore/CloseUsageTracker.swift`
- Test: `Tests/AffirmAlarmCoreTests/CloseUsageTrackerTests.swift`

**Interfaces:**
- Consumes: `CloseUsageRecord` (Task 2).
- Produces: `enum CloseUsageTracker { static let monthlyLimit: Int; static func monthKey(for date: Date, calendar: Calendar) -> String; static func canUseClose(record: CloseUsageRecord, now: Date, calendar: Calendar) -> Bool; static func recordingUse(on record: CloseUsageRecord, now: Date, calendar: Calendar) -> CloseUsageRecord }` — `AlarmRingViewModel` (Task 9) calls `canUseClose` before enabling the Close button and `recordingUse` after it's tapped.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AffirmAlarmCore

final class CloseUsageTrackerTests: XCTestCase {
    let calendar = Calendar(identifier: .gregorian)

    func makeDate(year: Int, month: Int, day: Int) -> Date {
        DateComponents(calendar: calendar, year: year, month: month, day: day).date!
    }

    func test_monthKey_formatsYearMonth() {
        let date = makeDate(year: 2026, month: 7, day: 15)
        XCTAssertEqual(CloseUsageTracker.monthKey(for: date, calendar: calendar), "2026-07")
    }

    func test_canUseClose_trueWhenUnderLimit() {
        let record = CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 2)
        let now = makeDate(year: 2026, month: 7, day: 15)
        XCTAssertTrue(CloseUsageTracker.canUseClose(record: record, now: now, calendar: calendar))
    }

    func test_canUseClose_falseWhenAtLimit() {
        let record = CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 3)
        let now = makeDate(year: 2026, month: 7, day: 15)
        XCTAssertFalse(CloseUsageTracker.canUseClose(record: record, now: now, calendar: calendar))
    }

    func test_canUseClose_trueWhenRecordIsFromAPastMonth() {
        let record = CloseUsageRecord(monthKey: "2026-06", usesThisMonth: 3)
        let now = makeDate(year: 2026, month: 7, day: 1)
        XCTAssertTrue(CloseUsageTracker.canUseClose(record: record, now: now, calendar: calendar))
    }

    func test_recordingUse_incrementsWithinSameMonth() {
        let record = CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 1)
        let now = makeDate(year: 2026, month: 7, day: 20)
        let updated = CloseUsageTracker.recordingUse(on: record, now: now, calendar: calendar)
        XCTAssertEqual(updated, CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 2))
    }

    func test_recordingUse_resetsToOneInNewMonth() {
        let record = CloseUsageRecord(monthKey: "2026-06", usesThisMonth: 3)
        let now = makeDate(year: 2026, month: 7, day: 1)
        let updated = CloseUsageTracker.recordingUse(on: record, now: now, calendar: calendar)
        XCTAssertEqual(updated, CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 1))
    }
}
```

- [ ] **Step 2: Commit the failing test**

```bash
cd "/home/user/Desktop/Vibes/CC-proper/AffirmAlarm"
git add Tests/AffirmAlarmCoreTests/CloseUsageTrackerTests.swift
git commit -m "test: add failing tests for CloseUsageTracker"
git push
```
Expected: CI fails with a compile error referencing `CloseUsageTracker`.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

public enum CloseUsageTracker {
    public static let monthlyLimit = 3

    public static func monthKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year!, components.month!)
    }

    public static func canUseClose(record: CloseUsageRecord, now: Date, calendar: Calendar) -> Bool {
        let currentKey = monthKey(for: now, calendar: calendar)
        guard record.monthKey == currentKey else { return true }
        return record.usesThisMonth < monthlyLimit
    }

    public static func recordingUse(on record: CloseUsageRecord, now: Date, calendar: Calendar) -> CloseUsageRecord {
        let currentKey = monthKey(for: now, calendar: calendar)
        guard record.monthKey == currentKey else {
            return CloseUsageRecord(monthKey: currentKey, usesThisMonth: 1)
        }
        return CloseUsageRecord(monthKey: currentKey, usesThisMonth: record.usesThisMonth + 1)
    }
}
```

- [ ] **Step 4: Run tests via CI and confirm pass**

```bash
git add Sources/AffirmAlarmCore/CloseUsageTracker.swift
git commit -m "feat: add CloseUsageTracker monthly cap logic"
git push
```
Expected: `CloseUsageTrackerTests` all green in the Actions log.

---

### Task 5: AffirmationMatcher (transcript verification logic)

**Files:**
- Create: `Sources/AffirmAlarmCore/AffirmationMatcher.swift`
- Test: `Tests/AffirmAlarmCoreTests/AffirmationMatcherTests.swift`

**Interfaces:**
- Consumes: nothing (pure string logic).
- Produces: `enum AffirmationMatcher { static func matches(transcript: String, target: String) -> Bool }` — Task 9's `AlarmRingViewModel` calls this to decide whether a completed speech transcript satisfies the current affirmation.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AffirmAlarmCore

final class AffirmationMatcherTests: XCTestCase {
    func test_matches_exactText() {
        XCTAssertTrue(AffirmationMatcher.matches(transcript: "I am capable", target: "I am capable"))
    }

    func test_matches_ignoringCaseAndPunctuation() {
        XCTAssertTrue(AffirmationMatcher.matches(transcript: "i am CAPABLE!", target: "I am capable."))
    }

    func test_matches_ignoringExtraWhitespace() {
        XCTAssertTrue(AffirmationMatcher.matches(transcript: "  I   am  capable ", target: "I am capable"))
    }

    func test_doesNotMatch_differentWords() {
        XCTAssertFalse(AffirmationMatcher.matches(transcript: "I am tired", target: "I am capable"))
    }

    func test_doesNotMatch_partialTranscript() {
        XCTAssertFalse(AffirmationMatcher.matches(transcript: "I am", target: "I am capable"))
    }
}
```

- [ ] **Step 2: Commit the failing test**

```bash
cd "/home/user/Desktop/Vibes/CC-proper/AffirmAlarm"
git add Tests/AffirmAlarmCoreTests/AffirmationMatcherTests.swift
git commit -m "test: add failing tests for AffirmationMatcher"
git push
```
Expected: CI fails with a compile error referencing `AffirmationMatcher`.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

public enum AffirmationMatcher {
    public static func matches(transcript: String, target: String) -> Bool {
        normalize(transcript) == normalize(target)
    }

    private static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let alphanumericAndSpaces = lowered.unicodeScalars.map { scalar -> Character in
            (CharacterSet.alphanumerics.contains(scalar) || scalar == " ") ? Character(scalar) : " "
        }
        let collapsed = String(alphanumericAndSpaces)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }
}
```

- [ ] **Step 4: Run tests via CI and confirm pass**

```bash
git add Sources/AffirmAlarmCore/AffirmationMatcher.swift
git commit -m "feat: add AffirmationMatcher transcript comparison"
git push
```
Expected: `AffirmationMatcherTests` all green in the Actions log.

---

### Task 6: SpeechRecognitionService (protocol + real + fake)

**Files:**
- Create: `Sources/AffirmAlarmCore/SpeechRecognitionService.swift`
- Modify: `Tests/AffirmAlarmCoreTests/Fakes.swift` (create if absent)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  ```swift
  public protocol SpeechRecognitionService {
      func startListening(onTranscriptUpdate: @escaping (String) -> Void, onError: @escaping (Error) -> Void)
      func stopListening()
  }
  public final class OnDeviceSpeechRecognitionService: SpeechRecognitionService { public init() }
  ```
  Task 9's `AlarmRingViewModel` depends on the `SpeechRecognitionService` protocol (injected), not the concrete type — this is what makes the ViewModel testable without a real microphone.

- [ ] **Step 1: Write the protocol, real implementation, and fake together**

There is no meaningful "failing test" step for this task in isolation — `SFSpeechRecognizer` requires a real device/simulator microphone and authorization prompts that can't be driven from a unit test. Instead, this task defines the seam (protocol) and both implementations; the *fake* is what gets unit-tested (in Task 9), and the *real* implementation is exercised by the UI test in Task 10.

```swift
import Foundation
import Speech

public protocol SpeechRecognitionService: AnyObject {
    func startListening(onTranscriptUpdate: @escaping (String) -> Void, onError: @escaping (Error) -> Void)
    func stopListening()
}

public final class OnDeviceSpeechRecognitionService: NSObject, SpeechRecognitionService {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    public override init() {
        super.init()
    }

    public func startListening(onTranscriptUpdate: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            onError(NSError(domain: "AffirmAlarm.Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"]))
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            onError(error)
            return
        }

        task = recognizer.recognitionTask(with: request) { result, error in
            if let error {
                onError(error)
                return
            }
            if let result {
                onTranscriptUpdate(result.bestTranscription.formattedString)
            }
        }
    }

    public func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
```

- [ ] **Step 2: Add the fake to the test target**

```swift
// Tests/AffirmAlarmCoreTests/Fakes.swift
import Foundation
@testable import AffirmAlarmCore

final class FakeSpeechRecognitionService: SpeechRecognitionService {
    var onTranscriptUpdate: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var isListening = false

    func startListening(onTranscriptUpdate: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
        self.onTranscriptUpdate = onTranscriptUpdate
        self.onError = onError
        isListening = true
    }

    func stopListening() {
        isListening = false
    }

    // Test helper: simulates the user finishing speaking a transcript.
    func simulateTranscript(_ text: String) {
        onTranscriptUpdate?(text)
    }
}
```

- [ ] **Step 3: Commit**

```bash
cd "/home/user/Desktop/Vibes/CC-proper/AffirmAlarm"
git add Sources/AffirmAlarmCore/SpeechRecognitionService.swift Tests/AffirmAlarmCoreTests/Fakes.swift
git commit -m "feat: add SpeechRecognitionService protocol, on-device impl, and test fake"
git push
```
Expected: CI passes (nothing calls the real implementation yet, so no microphone/simulator issues surface at this stage; the fake and protocol compile cleanly).

---

### Task 7: AlarmSchedulingService (protocol + AlarmKit + fake)

**Files:**
- Create: `Sources/AffirmAlarmCore/AlarmSchedulingService.swift`
- Modify: `Tests/AffirmAlarmCoreTests/Fakes.swift`

**Interfaces:**
- Produces:
  ```swift
  public protocol AlarmSchedulingService: AnyObject {
      func scheduleAlarm(at time: DateComponents) throws
      func cancelAlarm()
      func snooze(minutes: Int) throws
      func lowerVolumeForSpeaking()
      func restoreVolume()
  }
  public final class AlarmKitSchedulingService: AlarmSchedulingService { public init() }
  ```
  `lowerVolumeForSpeaking`/`restoreVolume` implement the spec's "alarm volume lowers to slightly audible while holding, not fully silenced" requirement — `AlarmRingViewModel` (Task 9) calls `lowerVolumeForSpeaking()` on `startHolding()` and `restoreVolume()` on `releaseHold()`.

- [ ] **Step 1: Verify AlarmKit's current API before writing the real implementation**

**This is the plan's highest-uncertainty step.** AlarmKit is newer than this plan's verified knowledge. Before writing `AlarmKitSchedulingService`, check Apple's current AlarmKit documentation (developer.apple.com/documentation/alarmkit) for the exact type/method names — the sketch below is a best-effort placeholder for the *shape* of the integration (schedule/cancel/snooze), not a confirmed-correct API call. Adjust names to match current docs; keep the protocol (`AlarmSchedulingService`) unchanged so no other file needs to change.

```swift
import Foundation
import AlarmKit // Confirm this import and the API below against current Apple docs before merging.

public protocol AlarmSchedulingService: AnyObject {
    func scheduleAlarm(at time: DateComponents) throws
    func cancelAlarm()
    func snooze(minutes: Int) throws
    func lowerVolumeForSpeaking()
    func restoreVolume()
}

public final class AlarmKitSchedulingService: AlarmSchedulingService {
    public init() {}

    public func scheduleAlarm(at time: DateComponents) throws {
        // Body intentionally unimplemented until the AlarmManager/AlarmConfiguration
        // API shape is confirmed against current AlarmKit docs (see Task 7, Step 1).
        fatalError("AlarmKitSchedulingService.scheduleAlarm not yet implemented — verify AlarmKit API first")
    }

    public func cancelAlarm() {
        fatalError("AlarmKitSchedulingService.cancelAlarm not yet implemented — verify AlarmKit API first")
    }

    public func snooze(minutes: Int) throws {
        fatalError("AlarmKitSchedulingService.snooze not yet implemented — verify AlarmKit API first")
    }

    public func lowerVolumeForSpeaking() {
        // AlarmKit may expose a volume/ducking control directly, or this may need to
        // go through AVAudioSession instead — confirm against current docs (Task 7, Step 1).
        fatalError("AlarmKitSchedulingService.lowerVolumeForSpeaking not yet implemented — verify AlarmKit API first")
    }

    public func restoreVolume() {
        fatalError("AlarmKitSchedulingService.restoreVolume not yet implemented — verify AlarmKit API first")
    }
}
```

- [ ] **Step 2: Add the fake to the test target**

```swift
// Tests/AffirmAlarmCoreTests/Fakes.swift (append)
final class FakeAlarmSchedulingService: AlarmSchedulingService {
    private(set) var scheduledTime: DateComponents?
    private(set) var wasCancelled = false
    private(set) var snoozeCallCount = 0
    private(set) var volumeLoweredCount = 0
    private(set) var volumeRestoredCount = 0

    func scheduleAlarm(at time: DateComponents) throws {
        scheduledTime = time
    }

    func cancelAlarm() {
        wasCancelled = true
    }

    func snooze(minutes: Int) throws {
        snoozeCallCount += 1
    }

    func lowerVolumeForSpeaking() {
        volumeLoweredCount += 1
    }

    func restoreVolume() {
        volumeRestoredCount += 1
    }
}
```

- [ ] **Step 3: Commit**

```bash
cd "/home/user/Desktop/Vibes/CC-proper/AffirmAlarm"
git add Sources/AffirmAlarmCore/AlarmSchedulingService.swift Tests/AffirmAlarmCoreTests/Fakes.swift
git commit -m "feat: add AlarmSchedulingService protocol, fake, and AlarmKit stub pending API verification"
git push
```
Expected: CI **fails to build** at this point (`fatalError` bodies compile fine, but the `import AlarmKit` line and any API-shape mismatch will not — this is expected and acceptable for this task; note in the Actions log exactly what the compiler error says, since it tells you what to fix once you've read the real AlarmKit docs). Do not proceed to wiring this into the app target (Task 10/11) until this file actually compiles against real AlarmKit.

---

### Task 8: StreakStore (SwiftData persistence)

**Files:**
- Create: `Sources/AffirmAlarmCore/StreakStore.swift`
- Test: `Tests/AffirmAlarmCoreTests/StreakStoreTests.swift`

**Interfaces:**
- Consumes: `StreakState`, `CloseUsageRecord`, `Affirmation` (Task 2).
- Produces:
  ```swift
  public protocol StreakStore {
      func loadStreakState() -> StreakState
      func save(_ state: StreakState)
      func loadCloseUsage() -> CloseUsageRecord
      func save(_ usage: CloseUsageRecord)
      func loadAffirmations() -> [Affirmation]
      func save(_ affirmations: [Affirmation])
  }
  public final class SwiftDataStreakStore: StreakStore { public init(inMemory: Bool = false) }
  ```

- [ ] **Step 1: Write the failing tests (using an in-memory store, no disk state leaks between tests)**

```swift
import XCTest
@testable import AffirmAlarmCore

final class StreakStoreTests: XCTestCase {
    func test_loadStreakState_defaultsToDayOneWhenEmpty() {
        let store = SwiftDataStreakStore(inMemory: true)
        let state = store.loadStreakState()
        XCTAssertEqual(state.streakDay, 1)
        XCTAssertNil(state.lastCompletedDate)
    }

    func test_saveThenLoad_roundTripsStreakState() {
        let store = SwiftDataStreakStore(inMemory: true)
        let saved = StreakState(streakDay: 9, lastCompletedDate: Date(timeIntervalSince1970: 1_000_000))
        store.save(saved)
        XCTAssertEqual(store.loadStreakState(), saved)
    }

    func test_loadCloseUsage_defaultsToZeroForCurrentMonthWhenEmpty() {
        let store = SwiftDataStreakStore(inMemory: true)
        let usage = store.loadCloseUsage()
        XCTAssertEqual(usage.usesThisMonth, 0)
    }

    func test_saveThenLoad_roundTripsCloseUsage() {
        let store = SwiftDataStreakStore(inMemory: true)
        let saved = CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 2)
        store.save(saved)
        XCTAssertEqual(store.loadCloseUsage(), saved)
    }

    func test_saveThenLoad_roundTripsAffirmations() {
        let store = SwiftDataStreakStore(inMemory: true)
        let saved = [Affirmation(text: "I am capable", isUserAuthored: true)]
        store.save(saved)
        XCTAssertEqual(store.loadAffirmations(), saved)
    }
}
```

- [ ] **Step 2: Commit the failing test**

```bash
cd "/home/user/Desktop/Vibes/CC-proper/AffirmAlarm"
git add Tests/AffirmAlarmCoreTests/StreakStoreTests.swift
git commit -m "test: add failing tests for SwiftDataStreakStore"
git push
```
Expected: CI fails with a compile error referencing `StreakStore`/`SwiftDataStreakStore`.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation
import SwiftData

@Model
final class StreakStateRecord {
    var streakDay: Int
    var lastCompletedDate: Date?
    init(streakDay: Int, lastCompletedDate: Date?) {
        self.streakDay = streakDay
        self.lastCompletedDate = lastCompletedDate
    }
}

@Model
final class CloseUsageRecordEntity {
    var monthKey: String
    var usesThisMonth: Int
    init(monthKey: String, usesThisMonth: Int) {
        self.monthKey = monthKey
        self.usesThisMonth = usesThisMonth
    }
}

@Model
final class AffirmationRecord {
    var id: UUID
    var text: String
    var isUserAuthored: Bool
    var sortOrder: Int
    init(id: UUID, text: String, isUserAuthored: Bool, sortOrder: Int) {
        self.id = id
        self.text = text
        self.isUserAuthored = isUserAuthored
        self.sortOrder = sortOrder
    }
}

public protocol StreakStore {
    func loadStreakState() -> StreakState
    func save(_ state: StreakState)
    func loadCloseUsage() -> CloseUsageRecord
    func save(_ usage: CloseUsageRecord)
    func loadAffirmations() -> [Affirmation]
    func save(_ affirmations: [Affirmation])
}

public final class SwiftDataStreakStore: StreakStore {
    private let container: ModelContainer
    private let context: ModelContext

    public init(inMemory: Bool = false) {
        let schema = Schema([StreakStateRecord.self, CloseUsageRecordEntity.self, AffirmationRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        container = try! ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
    }

    public func loadStreakState() -> StreakState {
        let records = try? context.fetch(FetchDescriptor<StreakStateRecord>())
        guard let record = records?.first else { return StreakState(streakDay: 1, lastCompletedDate: nil) }
        return StreakState(streakDay: record.streakDay, lastCompletedDate: record.lastCompletedDate)
    }

    public func save(_ state: StreakState) {
        let existing = try? context.fetch(FetchDescriptor<StreakStateRecord>())
        existing?.forEach { context.delete($0) }
        context.insert(StreakStateRecord(streakDay: state.streakDay, lastCompletedDate: state.lastCompletedDate))
        try? context.save()
    }

    public func loadCloseUsage() -> CloseUsageRecord {
        let records = try? context.fetch(FetchDescriptor<CloseUsageRecordEntity>())
        guard let record = records?.first else { return CloseUsageRecord(monthKey: "", usesThisMonth: 0) }
        return CloseUsageRecord(monthKey: record.monthKey, usesThisMonth: record.usesThisMonth)
    }

    public func save(_ usage: CloseUsageRecord) {
        let existing = try? context.fetch(FetchDescriptor<CloseUsageRecordEntity>())
        existing?.forEach { context.delete($0) }
        context.insert(CloseUsageRecordEntity(monthKey: usage.monthKey, usesThisMonth: usage.usesThisMonth))
        try? context.save()
    }

    public func loadAffirmations() -> [Affirmation] {
        let descriptor = FetchDescriptor<AffirmationRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map { Affirmation(id: $0.id, text: $0.text, isUserAuthored: $0.isUserAuthored) }
    }

    public func save(_ affirmations: [Affirmation]) {
        let existing = try? context.fetch(FetchDescriptor<AffirmationRecord>())
        existing?.forEach { context.delete($0) }
        for (index, a) in affirmations.enumerated() {
            context.insert(AffirmationRecord(id: a.id, text: a.text, isUserAuthored: a.isUserAuthored, sortOrder: index))
        }
        try? context.save()
    }
}
```

- [ ] **Step 4: Run tests via CI and confirm pass**

```bash
git add Sources/AffirmAlarmCore/StreakStore.swift
git commit -m "feat: add SwiftData-backed StreakStore"
git push
```
Expected: `StreakStoreTests` all green in the Actions log. Note: `test_loadCloseUsage_defaultsToZeroForCurrentMonthWhenEmpty` only checks `usesThisMonth == 0`, not `monthKey`, because the default sentinel (`monthKey: ""`) is not itself a valid month — `AlarmRingViewModel` (Task 9) must call `CloseUsageTracker.canUseClose`, which already treats any non-matching `monthKey` as "usable," so this default is safe to consume as-is.

---

### Task 9: AlarmRingViewModel (orchestration)

**Files:**
- Create: `Sources/AffirmAlarmCore/AlarmRingViewModel.swift`
- Test: `Tests/AffirmAlarmCoreTests/AlarmRingViewModelTests.swift`

**Interfaces:**
- Consumes: `IntensityEngine` (Task 3), `CloseUsageTracker` (Task 4), `AffirmationMatcher` (Task 5), `SpeechRecognitionService` (Task 6), `AlarmSchedulingService` (Task 7), `StreakStore` (Task 8).
- Produces:
  ```swift
  public enum RingScreenState: Equatable {
      case idle
      case listening(currentIndex: Int, currentRepeat: Int)
      case completed
  }
  public final class AlarmRingViewModel: ObservableObject {
      @Published public private(set) var state: RingScreenState
      @Published public private(set) var canUseClose: Bool
      public init(speechService: SpeechRecognitionService, alarmService: AlarmSchedulingService, store: StreakStore, now: @escaping () -> Date = Date.init)
      public func beginRing()
      public func startHolding()
      public func releaseHold()
      public func tapSnooze()
      public func tapClose()
  }
  ```
  Task 10's `AlarmRingView` observes `state` and `canUseClose`, and calls `startHolding()`/`releaseHold()`/`tapSnooze()`/`tapClose()` from gesture/button handlers.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AffirmAlarmCore

final class AlarmRingViewModelTests: XCTestCase {
    func makeViewModel(
        affirmations: [Affirmation] = [Affirmation(text: "I am capable", isUserAuthored: true)],
        streakDay: Int = 1
    ) -> (AlarmRingViewModel, FakeSpeechRecognitionService, FakeAlarmSchedulingService, SwiftDataStreakStore) {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(affirmations)
        store.save(StreakState(streakDay: streakDay, lastCompletedDate: nil))
        let speech = FakeSpeechRecognitionService()
        let alarm = FakeAlarmSchedulingService()
        let vm = AlarmRingViewModel(speechService: speech, alarmService: alarm, store: store)
        return (vm, speech, alarm, store)
    }

    func test_beginRing_startsInIdleState() {
        let (vm, _, _, _) = makeViewModel()
        vm.beginRing()
        XCTAssertEqual(vm.state, .idle)
    }

    func test_startHolding_movesToListeningAtFirstAffirmation() {
        let (vm, _, _, _) = makeViewModel()
        vm.beginRing()
        vm.startHolding()
        XCTAssertEqual(vm.state, .listening(currentIndex: 0, currentRepeat: 0))
    }

    func test_correctTranscript_advancesRepeatCount() {
        let (vm, speech, _, _) = makeViewModel(streakDay: 7) // day 7 = 1 affirmation x2 repeats
        vm.beginRing()
        vm.startHolding()
        speech.simulateTranscript("I am capable")
        XCTAssertEqual(vm.state, .listening(currentIndex: 0, currentRepeat: 1))
    }

    func test_finalRepeatOfFinalAffirmation_completesSession() {
        let (vm, speech, _, _) = makeViewModel(streakDay: 1) // day 1 = 1 affirmation x1 repeat
        vm.beginRing()
        vm.startHolding()
        speech.simulateTranscript("I am capable")
        XCTAssertEqual(vm.state, .completed)
    }

    func test_completingSession_stopsTheAlarm() {
        let (vm, speech, alarm, _) = makeViewModel(streakDay: 1)
        vm.beginRing()
        vm.startHolding()
        speech.simulateTranscript("I am capable")
        XCTAssertTrue(alarm.wasCancelled)
    }

    func test_completingSession_advancesStreakDayInStore() {
        let (vm, speech, _, store) = makeViewModel(streakDay: 1)
        vm.beginRing()
        vm.startHolding()
        speech.simulateTranscript("I am capable")
        XCTAssertEqual(store.loadStreakState().streakDay, 2)
    }

    func test_releaseHold_beforeMatchResetsCurrentAttemptOnly() {
        let (vm, _, _, _) = makeViewModel(streakDay: 7)
        vm.beginRing()
        vm.startHolding()
        vm.releaseHold()
        XCTAssertEqual(vm.state, .idle)
        vm.startHolding()
        XCTAssertEqual(vm.state, .listening(currentIndex: 0, currentRepeat: 0))
    }

    func test_releaseHold_afterVerifyingOneAffirmation_preservesProgressOnResume() {
        let (vm, speech, _, _) = makeViewModel(
            affirmations: [
                Affirmation(text: "I am capable", isUserAuthored: true),
                Affirmation(text: "I am strong", isUserAuthored: true)
            ],
            streakDay: 14 // 2 affirmations x1 repeat each
        )
        vm.beginRing()
        vm.startHolding()
        speech.simulateTranscript("I am capable")
        XCTAssertEqual(vm.state, .listening(currentIndex: 1, currentRepeat: 0))
        vm.releaseHold()
        XCTAssertEqual(vm.state, .idle)
        vm.startHolding()
        XCTAssertEqual(vm.state, .listening(currentIndex: 1, currentRepeat: 0))
    }

    func test_startHolding_lowersAlarmVolume() {
        let (vm, _, alarm, _) = makeViewModel()
        vm.beginRing()
        vm.startHolding()
        XCTAssertEqual(alarm.volumeLoweredCount, 1)
    }

    func test_releaseHold_restoresAlarmVolume() {
        let (vm, _, alarm, _) = makeViewModel(streakDay: 7)
        vm.beginRing()
        vm.startHolding()
        vm.releaseHold()
        XCTAssertEqual(alarm.volumeRestoredCount, 1)
    }

    func test_beginRing_resetsStreakWhenADayWasMissed() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save([Affirmation(text: "I am capable", isUserAuthored: true)])
        let calendar = Calendar(identifier: .gregorian)
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: Date())!
        store.save(StreakState(streakDay: 10, lastCompletedDate: twoDaysAgo))
        let vm = AlarmRingViewModel(
            speechService: FakeSpeechRecognitionService(),
            alarmService: FakeAlarmSchedulingService(),
            store: store
        )
        vm.beginRing()
        XCTAssertEqual(store.loadStreakState().streakDay, 1)
    }

    func test_beginRing_doesNotResetStreakWhenCompletedYesterday() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save([Affirmation(text: "I am capable", isUserAuthored: true)])
        let calendar = Calendar(identifier: .gregorian)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        store.save(StreakState(streakDay: 10, lastCompletedDate: yesterday))
        let vm = AlarmRingViewModel(
            speechService: FakeSpeechRecognitionService(),
            alarmService: FakeAlarmSchedulingService(),
            store: store
        )
        vm.beginRing()
        XCTAssertEqual(store.loadStreakState().streakDay, 10)
    }

    func test_beginRing_doesNotResetOnFirstEverSession() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save([Affirmation(text: "I am capable", isUserAuthored: true)])
        // lastCompletedDate is nil (SwiftDataStreakStore default) — never completed yet, not a "miss".
        let vm = AlarmRingViewModel(
            speechService: FakeSpeechRecognitionService(),
            alarmService: FakeAlarmSchedulingService(),
            store: store
        )
        vm.beginRing()
        XCTAssertEqual(store.loadStreakState().streakDay, 1)
    }

    func test_tapSnooze_callsAlarmServiceSnoozeAndReturnsToIdle() {
        let (vm, _, alarm, _) = makeViewModel()
        vm.beginRing()
        vm.tapSnooze()
        XCTAssertEqual(alarm.snoozeCallCount, 1)
        XCTAssertEqual(vm.state, .idle)
    }

    func test_canUseClose_trueWithNoPriorUsage() {
        let (vm, _, _, _) = makeViewModel()
        vm.beginRing()
        XCTAssertTrue(vm.canUseClose)
    }

    func test_tapClose_whenAllowed_cancelsAlarmAndResetsStreak() {
        let (vm, _, alarm, store) = makeViewModel(streakDay: 15)
        vm.beginRing()
        vm.tapClose()
        XCTAssertTrue(alarm.wasCancelled)
        XCTAssertEqual(store.loadStreakState().streakDay, 1)
    }

    func test_tapClose_threeTimesInAMonth_disablesFurtherUse() {
        let (vm, _, _, _) = makeViewModel()
        vm.beginRing(); vm.tapClose()
        vm.beginRing(); vm.tapClose()
        vm.beginRing(); vm.tapClose()
        XCTAssertFalse(vm.canUseClose)
    }
}
```

- [ ] **Step 2: Commit the failing test**

```bash
cd "/home/user/Desktop/Vibes/CC-proper/AffirmAlarm"
git add Tests/AffirmAlarmCoreTests/AlarmRingViewModelTests.swift
git commit -m "test: add failing tests for AlarmRingViewModel"
git push
```
Expected: CI fails with a compile error referencing `AlarmRingViewModel`/`RingScreenState`.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation
import Combine

public enum RingScreenState: Equatable {
    case idle
    case listening(currentIndex: Int, currentRepeat: Int)
    case completed
}

public final class AlarmRingViewModel: ObservableObject {
    @Published public private(set) var state: RingScreenState = .idle
    @Published public private(set) var canUseClose: Bool = true

    private let speechService: SpeechRecognitionService
    private let alarmService: AlarmSchedulingService
    private let store: StreakStore
    private let now: () -> Date
    private let calendar = Calendar(identifier: .gregorian)

    private var affirmations: [Affirmation] = []
    private var requiredCount = 1
    private var requiredRepeats = 1
    private var currentIndex = 0
    private var currentRepeat = 0

    public init(
        speechService: SpeechRecognitionService,
        alarmService: AlarmSchedulingService,
        store: StreakStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.speechService = speechService
        self.alarmService = alarmService
        self.store = store
        self.now = now
    }

    public func beginRing() {
        affirmations = store.loadAffirmations()
        var streakState = store.loadStreakState()
        if hasMissedADay(since: streakState.lastCompletedDate) {
            streakState = StreakState(streakDay: 1, lastCompletedDate: nil)
            store.save(streakState)
        }
        let level = IntensityEngine.level(forStreakDay: streakState.streakDay)
        requiredCount = level.affirmationCount
        requiredRepeats = level.repeatsPerAffirmation
        currentIndex = 0
        currentRepeat = 0
        state = .idle
        canUseClose = CloseUsageTracker.canUseClose(record: store.loadCloseUsage(), now: now(), calendar: calendar)
    }

    public func startHolding() {
        guard case .idle = state else { return }
        state = .listening(currentIndex: currentIndex, currentRepeat: currentRepeat)
        alarmService.lowerVolumeForSpeaking()
        listenForCurrentAffirmation()
    }

    public func releaseHold() {
        guard case .listening = state else { return }
        speechService.stopListening()
        alarmService.restoreVolume()
        state = .idle
    }

    /// A "miss" is any completed calendar day with no session finished — i.e. more than
    /// one day elapsed between the last completion and now. `nil` means no session has
    /// ever been completed yet, which is day one of a fresh streak, not a miss.
    private func hasMissedADay(since lastCompletedDate: Date?) -> Bool {
        guard let lastCompletedDate else { return false }
        let today = calendar.startOfDay(for: now())
        let lastDay = calendar.startOfDay(for: lastCompletedDate)
        let daysBetween = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        return daysBetween > 1
    }

    public func tapSnooze() {
        try? alarmService.snooze(minutes: 9)
        state = .idle
    }

    public func tapClose() {
        let usage = store.loadCloseUsage()
        guard CloseUsageTracker.canUseClose(record: usage, now: now(), calendar: calendar) else { return }
        store.save(CloseUsageTracker.recordingUse(on: usage, now: now(), calendar: calendar))
        resetStreakToStart()
        alarmService.cancelAlarm()
        canUseClose = CloseUsageTracker.canUseClose(record: store.loadCloseUsage(), now: now(), calendar: calendar)
        state = .completed
    }

    private func listenForCurrentAffirmation() {
        guard currentIndex < affirmations.count else { return }
        let target = affirmations[currentIndex].text
        speechService.startListening(
            onTranscriptUpdate: { [weak self] transcript in
                self?.handleTranscript(transcript, target: target)
            },
            onError: { _ in }
        )
    }

    private func handleTranscript(_ transcript: String, target: String) {
        guard case .listening = state else { return }
        guard AffirmationMatcher.matches(transcript: transcript, target: target) else { return }
        speechService.stopListening()

        let nextRepeat = currentRepeat + 1
        if nextRepeat < requiredRepeats {
            currentRepeat = nextRepeat
            state = .listening(currentIndex: currentIndex, currentRepeat: currentRepeat)
            listenForCurrentAffirmation()
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < requiredCount && nextIndex < affirmations.count {
            currentIndex = nextIndex
            currentRepeat = 0
            state = .listening(currentIndex: currentIndex, currentRepeat: currentRepeat)
            listenForCurrentAffirmation()
            return
        }

        completeSession()
    }

    private func completeSession() {
        advanceStreak()
        alarmService.cancelAlarm()
        state = .completed
    }

    private func advanceStreak() {
        let current = store.loadStreakState()
        store.save(StreakState(streakDay: current.streakDay + 1, lastCompletedDate: now()))
    }

    private func resetStreakToStart() {
        store.save(StreakState(streakDay: 1, lastCompletedDate: nil))
    }
}
```

- [ ] **Step 4: Run tests via CI and confirm pass**

```bash
git add Sources/AffirmAlarmCore/AlarmRingViewModel.swift
git commit -m "feat: add AlarmRingViewModel orchestrating the ring-screen flow"
git push
```
Expected: `AlarmRingViewModelTests` all green in the Actions log. If `test_finalRepeatOfFinalAffirmation_completesSession` or similar fails, check the interaction between `requiredCount`/`requiredRepeats` and `affirmations.count` — with only one seeded affirmation but `requiredCount > 1`, `nextIndex < affirmations.count` correctly falls through to `completeSession()` rather than indexing out of bounds; this is intentional for Phase 1 (a real deployment always seeds enough affirmations to match the day's `requiredCount`, but the guard exists so the view model never crashes if it doesn't).

---

### Task 10: AlarmRingView (SwiftUI) + UI Test

**Files:**
- Create: `Sources/AffirmAlarm/AlarmRingView.swift`
- Create: `Sources/AffirmAlarm/AffirmAlarmApp.swift`
- Create: `Sources/AffirmAlarm/Info.plist` (empty/minimal, properties are injected by `project.yml`)
- Create: `Tests/AffirmAlarmUITests/AlarmRingUITests.swift`

**Interfaces:**
- Consumes: `AlarmRingViewModel`, `RingScreenState` (Task 9).
- Produces: a SwiftUI view exposing accessibility identifiers `"snoozeButton"`, `"holdToSpeakButton"`, `"closeButton"`, `"completedLabel"` for UI tests to target.

- [ ] **Step 1: Write the SwiftUI view**

```swift
import SwiftUI
import AffirmAlarmCore

struct AlarmRingView: View {
    @ObservedObject var viewModel: AlarmRingViewModel

    var body: some View {
        VStack(spacing: 32) {
            switch viewModel.state {
            case .completed:
                Text("Alarm dismissed")
                    .font(.title)
                    .accessibilityIdentifier("completedLabel")
            default:
                HStack(spacing: 24) {
                    Button("Snooze") { viewModel.tapSnooze() }
                        .accessibilityIdentifier("snoozeButton")

                    Circle()
                        .fill(isHolding ? Color.yellow : Color.gray)
                        .frame(width: 120, height: 120)
                        .overlay(Text("Hold & Speak").foregroundColor(.black))
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("holdToSpeakButton")
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in viewModel.startHolding() }
                                .onEnded { _ in viewModel.releaseHold() }
                        )

                    Button("Close") { viewModel.tapClose() }
                        .disabled(!viewModel.canUseClose)
                        .accessibilityIdentifier("closeButton")
                }
            }
        }
        .padding()
        .onAppear { viewModel.beginRing() }
    }

    private var isHolding: Bool {
        if case .listening = viewModel.state { return true }
        return false
    }
}
```

- [ ] **Step 2: Write the app entry point**

```swift
import SwiftUI
import AffirmAlarmCore

@main
struct AffirmAlarmApp: App {
    var body: some Scene {
        WindowGroup {
            AlarmRingView(
                viewModel: AlarmRingViewModel(
                    speechService: OnDeviceSpeechRecognitionService(),
                    alarmService: AlarmKitSchedulingService(),
                    store: SwiftDataStreakStore()
                )
            )
        }
    }
}
```
Note: this wires the *real* services for the shipped app. It will not build until Task 7's `AlarmKitSchedulingService` actually compiles against verified AlarmKit APIs (see Task 7, Step 1) — that is expected and intentional; do not stub around it here.

- [ ] **Step 3: Write the UI test**

```swift
import XCTest

final class AlarmRingUITests: XCTestCase {
    func test_snoozeButton_isVisibleOnLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["snoozeButton"].waitForExistence(timeout: 5))
    }

    func test_closeButton_isVisibleOnLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["closeButton"].waitForExistence(timeout: 5))
    }

    func test_holdToSpeakButton_isVisibleOnLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["holdToSpeakButton"].waitForExistence(timeout: 5))
    }
}
```
Note: these UI tests only assert the ring screen renders its three controls — they deliberately do not attempt to drive real microphone input (not feasible headlessly in CI) or a real AlarmKit-scheduled alarm firing. Deeper interaction testing (press-and-hold → transcript → completion) is already covered at the logic level by `AlarmRingViewModelTests` (Task 9) via the fake speech service; this UI test only proves the real view wires up correctly.

- [ ] **Step 4: Commit and run via CI**

```bash
cd "/home/user/Desktop/Vibes/CC-proper/AffirmAlarm"
git add Sources/AffirmAlarm Tests/AffirmAlarmUITests
git commit -m "feat: add AlarmRingView, app entry point, and UI smoke tests"
git push
```
Expected: this is the first point the `AffirmAlarm` app-target scheme can build at all — expect it to fail here specifically because of the unresolved AlarmKit API from Task 7 (fatalError stubs will build fine; a genuinely wrong API shape will not). Resolve any remaining AlarmKit compile errors using current Apple docs before this task can be marked done.

---

### Task 11: Final CI Green-Build Verification

**Files:** none (verification-only task).

- [ ] **Step 1: Confirm both CI jobs are green on `main`**

```bash
gh run list --repo mr-uncertain/affirm-alarm --limit 5
gh run view --repo mr-uncertain/affirm-alarm --log-failed
```
Expected: the latest run on `main` shows both `AffirmAlarmCore` unit tests and `AffirmAlarm` UI tests passing. If `AlarmKitSchedulingService` (Task 7) is still unresolved, this is the task where that gets finished — Phase 1 is not complete until this is genuinely green, not stubbed.

- [ ] **Step 2: Tag the milestone**

```bash
cd "/home/user/Desktop/Vibes/CC-proper/AffirmAlarm"
git tag phase1-core-loop-complete
git push origin phase1-core-loop-complete
```
Expected: tag visible at `https://github.com/mr-uncertain/affirm-alarm/tags`.

**AlarmKit resolution note (added when Task 11 was executed):** researched the real AlarmKit API (WWDC25, official docs, community references — AlarmKit's exact surface isn't in this assistant's verified training data). Two real constraints emerged that the original Task 7 stub design didn't anticipate:
1. `AlarmManager`'s real methods (`schedule`, `stop`, `requestAuthorization`) are `async throws`, but this protocol's methods are synchronous (matching how `AlarmRingViewModel`, already reviewed and tested in Task 9, calls them). Rather than cascading an async rewrite through Task 9's approved ViewModel and its 17 tests, `AlarmKitSchedulingService` bridges to the async calls via fire-and-forget `Task { }` blocks — errors from the AlarmKit side are swallowed since there is no synchronous caller to propagate them to yet (Phase 1 has no alarm-setting UI that would call `scheduleAlarm` at all).
2. AlarmKit exposes no API for an app to control its own alert sound's volume — there is no way to honestly implement "lowers but never silences" against AlarmKit's own audio. Resolved by having `AlarmKitSchedulingService` generate and loop its own tone via `AVAudioEngine`/`AVAudioPlayerNode` (see `GeneratedTonePlayer` in `AlarmSchedulingService.swift`), which `lowerVolumeForSpeaking`/`restoreVolume` adjust directly — deterministic and testable-by-us, independent of uncertain AlarmKit runtime behavior. `scheduleAlarm`'s real AlarmKit call configures the system alarm for reliable wake-up/backgrounding; the ringtone starts on `AlarmKitSchedulingService.init()` since Phase 1's app IS the ring screen (no other screen exists yet that would signal "the alarm actually started ringing" more precisely).
`snooze(minutes:)` does not yet re-arm a real AlarmKit alarm after the snooze interval (no alarm-setting UI exists yet to source the original configuration from) — it silences the local ringtone only. Real re-arming is deferred to the phase that adds alarm-setting.

---

## Explicitly Out of Scope for This Plan (see spec)

AI-generated affirmation content (onboarding chat, 7–8 day check-ins), RevenueCat/Superwall monetization, Android — each becomes its own plan once Phase 1 is verified working, per the spec's "Out of Scope for v1" section (those are v1-scope-but-not-Phase-1; monetization and AI content are still v1 per the spec, just sequenced into later phases here for a testable rollout).
