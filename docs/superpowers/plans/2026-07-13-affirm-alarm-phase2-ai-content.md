# AffirmAlarm Phase 2 — AI Content, Alarm-Setting & Insights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give AffirmAlarm a real Home screen with alarm-setting, an on-device AI chat that writes affirmations during onboarding and periodic check-ins, manual affirmation editing, consent-gated chat history, and a lightweight insights journal — while fixing two AlarmKit API issues Phase 1 shipped with (deprecated initializer, no cross-launch alarm ID sync).

**Architecture:** SwiftUI + SwiftData, same protocol-per-service pattern as Phase 1 (`AlarmSchedulingService`, `SpeechRecognitionService`, `StreakStore`). Adds `AIContentService` (on-device `FoundationModels` only) and `CheckInScheduling` (local notifications) as new protocol boundaries, each faked in tests the same way `FakeSpeechRecognitionService`/`FakeAlarmSchedulingService` already are. A new `RootViewModel` decides between `HomeView` (new root) and the existing `AlarmRingView` based on whether AlarmKit reports an alerting alarm.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, AlarmKit, FoundationModels (on-device LLM, iOS 26+), UserNotifications, XcodeGen, GitHub Actions (macos-15) for the only real build/test environment.

## Global Constraints

- Deployment target moves to iOS 26.1 (from 26.0) in `project.yml` — required for the non-deprecated `AlarmPresentation.Alert` initializer.
- Persistence is SwiftData only — no Core Data, no UserDefaults for structured data, matching the v1 spec's fully-on-device architecture.
- The only `AIContentService` implementation built in this plan is on-device (`FoundationModels`). No network calls, no API keys, no cloud provider — that's explicitly deferred (see design spec's Out of Scope).
- Consent prompt copy is fixed and must be used verbatim: **"Save our conversations? This helps me remember what matters to you next time, and gives you a simple journal of your own reflections. Nothing leaves your device."** No pre-checked opt-in box. Two equal-weight buttons ("Yes, save my conversations" / "No thanks, don't save").
- No local Swift/Xcode toolchain exists in this environment. GitHub Actions (`macos-15` runner, workflow at `.github/workflows/`) is the only place any of this code actually compiles or runs. Budget for CI round trips on any task touching `AlarmKit` or `FoundationModels` directly — Phase 1 needed 2-3 iterations on `AlarmManager.AlarmConfiguration`'s real signature; expect the same for `FoundationModels` types in Task 5, since neither framework's exact API surface can be verified without a real compiler. Push and check the Actions run for the current branch after each such task.
- Real OS-level snooze (`Alarm.CountdownDuration(postAlert:)`, requires a Widget Extension), cloud LLM providers, deleting persisted chat history, and monetization are explicitly out of scope for this plan — do not build them.
- The full design rationale, including the accepted "system Stop button always bypasses the affirmation" trade-off, lives in `docs/superpowers/specs/2026-07-13-affirm-alarm-phase2-ai-content-design.md` — read it if a task's motivation is unclear.

---

### Task 1: AlarmKit corrections — non-deprecated Alert init, async scheduling, cross-launch alarm sync

**Files:**
- Modify: `project.yml`
- Modify: `Sources/AffirmAlarmCore/AlarmSchedulingService.swift`
- Modify: `Tests/AffirmAlarmCoreTests/Fakes.swift:30-56` (`FakeAlarmSchedulingService`)

**Interfaces:**
- Produces: `AlarmSchedulingService.scheduleAlarm(at:) async throws` (was `throws`, synchronous), `AlarmSchedulingService.syncActiveAlarm(id: UUID)` (new), `AlarmSchedulingService.currentlyAlertingAlarmID() async -> UUID?` (new), `AlarmSchedulingService.alertingAlarmUpdates() -> AsyncStream<UUID?>` (new). Task 2 consumes all four of these on the new protocol.

- [ ] **Step 1: Bump the deployment target**

In `project.yml`, change:
```yaml
options:
  bundleIdPrefix: com.affirmalarm
  deploymentTarget:
    iOS: "26.0"
```
to:
```yaml
options:
  bundleIdPrefix: com.affirmalarm
  deploymentTarget:
    iOS: "26.1"
```

- [ ] **Step 2: Update the protocol and the fake to the new async/sync-query signatures**

Replace the protocol in `Sources/AffirmAlarmCore/AlarmSchedulingService.swift:10-16`:
```swift
public protocol AlarmSchedulingService: AnyObject {
    func scheduleAlarm(at time: DateComponents) async throws
    func cancelAlarm()
    func snooze(minutes: Int) throws
    func lowerVolumeForSpeaking()
    func restoreVolume()
    func syncActiveAlarm(id: UUID)
    func currentlyAlertingAlarmID() async -> UUID?
    func alertingAlarmUpdates() -> AsyncStream<UUID?>
}
```

In `Tests/AffirmAlarmCoreTests/Fakes.swift`, replace `FakeAlarmSchedulingService` (lines 30-56) with:
```swift
final class FakeAlarmSchedulingService: AlarmSchedulingService {
    private(set) var scheduledTime: DateComponents?
    private(set) var wasCancelled = false
    private(set) var snoozeCallCount = 0
    private(set) var volumeLoweredCount = 0
    private(set) var volumeRestoredCount = 0
    private(set) var syncedAlarmID: UUID?
    var alertingIDToReturn: UUID?
    var scheduleAlarmError: Error?
    private var updatesContinuation: AsyncStream<UUID?>.Continuation?

    func scheduleAlarm(at time: DateComponents) async throws {
        if let scheduleAlarmError { throw scheduleAlarmError }
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

    func syncActiveAlarm(id: UUID) {
        syncedAlarmID = id
    }

    func currentlyAlertingAlarmID() async -> UUID? {
        alertingIDToReturn
    }

    func alertingAlarmUpdates() -> AsyncStream<UUID?> {
        AsyncStream { continuation in
            self.updatesContinuation = continuation
        }
    }

    // Test helper: drives the alertingAlarmUpdates() stream.
    func simulateAlertingUpdate(_ id: UUID?) {
        updatesContinuation?.yield(id)
    }
}
```

This is a pure signature/scaffolding change — it will not compile stand-alone until Step 3 updates the real implementation to match, and neither `AlarmKitSchedulingServiceTests` nor `AlarmRingViewModelTests` call `scheduleAlarm`/the three new methods today (verified: `grep -rn "scheduleAlarm" Tests/` only matches this file and a comment), so no other test file needs changes for this step.

- [ ] **Step 3: Rewrite `AlarmKitSchedulingService` against the real (non-deprecated) AlarmKit API**

Replace `Sources/AffirmAlarmCore/AlarmSchedulingService.swift:20-113` (the `AlarmKitSchedulingService` class body, keeping `GeneratedTonePlayer` below it untouched) with:

```swift
public final class AlarmKitSchedulingService: AlarmSchedulingService {
    private var currentAlarmID: UUID?
    private let ringtone = GeneratedTonePlayer()

    public init() {
        // Phase 1 has no home/settings screen yet — AlarmRingView is the entire
        // app UI, so constructing this service happens exactly when the app is
        // launched to handle a firing alarm. Starting the locally-generated
        // ringtone here (rather than from a dedicated "alarm is now ringing"
        // hook, which doesn't exist yet on AlarmRingViewModel) is a Phase 1
        // simplification, not a general-purpose design.
        ringtone.start()
    }

    public func scheduleAlarm(at time: DateComponents) async throws {
        guard let hour = time.hour, let minute = time.minute else {
            throw AlarmSchedulingError.invalidTime
        }
        let id = UUID()

        _ = try await AlarmManager.shared.requestAuthorization()

        // The system now always provides its own Stop button automatically —
        // AlarmPresentation.Alert's `stopButton:` parameter was deprecated in
        // iOS 26.1 and has been removed here. `secondaryButton` +
        // `.custom` is what lets the fired alert's "Open" action launch the
        // app into AlarmRingView; see the Phase 2 design spec's accepted
        // trade-off note on why the system Stop button itself can't be
        // gated or intercepted.
        let openButton = AlarmButton(text: "Open", textColor: .white, systemImageName: "arrow.up.forward.app")
        let alert = AlarmPresentation.Alert(
            title: "AffirmAlarm",
            secondaryButton: openButton,
            secondaryButtonBehavior: .custom
        )
        let presentation = AlarmPresentation(alert: alert)
        let attributes = AlarmAttributes(presentation: presentation, metadata: AffirmAlarmMetadata(), tintColor: .orange)

        let scheduleTime = Alarm.Schedule.Relative.Time(hour: hour, minute: minute)
        let relative = Alarm.Schedule.Relative(time: scheduleTime, repeats: .never)
        let schedule = Alarm.Schedule.relative(relative)

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: schedule,
            attributes: attributes,
            secondaryIntent: nil,
            sound: .default
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        currentAlarmID = id
    }

    public func cancelAlarm() {
        // The local ringtone is the only audio Phase 1/2 ever produces (see
        // init() above) and must stop regardless of whether this instance
        // knows the AlarmKit-side id — currentAlarmID only gates the
        // AlarmKit-side stop() call, never the local ringtone.
        if let id = currentAlarmID {
            currentAlarmID = nil
            Task {
                try? await AlarmManager.shared.stop(id: id)
            }
        }
        ringtone.stop()
    }

    public func snooze(minutes: Int) throws {
        // AlarmKit's own post-alert snooze interval is fixed at schedule time
        // and real OS-level snooze requires a Widget Extension (deferred,
        // see Phase 2 design spec). Snoozing here silences the local
        // ringtone only.
        ringtone.stop()
    }

    public func lowerVolumeForSpeaking() {
        ringtone.setVolume(0.08)
    }

    public func restoreVolume() {
        ringtone.setVolume(1.0)
    }

    /// Called by the routing layer (RootViewModel, Task 2) once it discovers
    /// a real alerting alarm's id from AlarmManager on a fresh app launch —
    /// this instance is reconstructed each launch (see AffirmAlarmApp), so
    /// currentAlarmID from a prior session's scheduleAlarm() call is
    /// otherwise lost, leaving cancelAlarm()'s AlarmManager.stop(id:) call
    /// unreachable on the exact launch that matters most.
    public func syncActiveAlarm(id: UUID) {
        currentAlarmID = id
    }

    public func currentlyAlertingAlarmID() async -> UUID? {
        guard let alarms = try? AlarmManager.shared.alarms else { return nil }
        return alarms.first(where: { $0.state == .alerting })?.id
    }

    public func alertingAlarmUpdates() -> AsyncStream<UUID?> {
        AsyncStream { continuation in
            let task = Task {
                for await alarms in AlarmManager.shared.alarmUpdates {
                    let alertingID = alarms.first(where: { $0.state == .alerting })?.id
                    continuation.yield(alertingID)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Exposed for testing: whether the local ringtone is currently playing.
    var isRingtonePlaying: Bool {
        ringtone.isPlaying
    }

    /// Exposed for testing: the local ringtone's current playback volume.
    var ringtoneVolume: Float {
        ringtone.volume
    }
}
```

`Alarm`'s `.id` and `.state` properties are used here per the AlarmKit documentation already present in the repo (`alarmkit apple.docx`) — if CI reports a compile error on either, open that file and grep it for `Alarm` (the struct, not `AlarmManager`) to confirm the real property names before adjusting; this is the same class of SDK-surface uncertainty Phase 1 hit with `AlarmManager.AlarmConfiguration` and resolved by iterating against CI.

Also delete the now-fully-unused `AlarmSchedulingError.noActiveAlarm` if it still exists in this file (the Phase 1 final-review fix already removed its call site; confirm via the `enum AlarmSchedulingError` declaration at the top of the file — only `invalidTime` should remain).

- [ ] **Step 4: Push and verify on CI**

Commit, push, and check the GitHub Actions run for both `AffirmAlarmCore` and `AffirmAlarm` schemes. `AlarmKitSchedulingServiceTests` (existing, untouched) must still pass — none of its four tests call `scheduleAlarm`, `syncActiveAlarm`, `currentlyAlertingAlarmID`, or `alertingAlarmUpdates`, so they should be unaffected by this task; they exist purely to confirm the local-ringtone side effects still work. `AffirmAlarmUITests` will still pass at this point (Task 2 is what changes app launch routing).

- [ ] **Step 5: Commit**

```bash
git add project.yml Sources/AffirmAlarmCore/AlarmSchedulingService.swift Tests/AffirmAlarmCoreTests/Fakes.swift
git commit -m "fix(alarmkit): migrate off deprecated Alert init, async scheduling, cross-launch alarm sync"
```

---

### Task 2: Routing between Home and the ring screen

**Files:**
- Create: `Sources/AffirmAlarmCore/RootViewModel.swift`
- Create: `Sources/AffirmAlarm/RootView.swift`
- Modify: `Tests/AffirmAlarmUITests/AlarmRingUITests.swift`
- Test: `Tests/AffirmAlarmCoreTests/RootViewModelTests.swift`

**Interfaces:**
- Consumes: `AlarmSchedulingService` (Task 1's four new/changed methods)
- Produces: `RootViewModel.Route` enum (`.home` / `.ringing`), `RootViewModel.start() async`. Task 3 (`HomeView`) and Task 11 (`AffirmAlarmApp` wiring) both consume `RootView`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/AffirmAlarmCoreTests/RootViewModelTests.swift`:
```swift
import XCTest
@testable import AffirmAlarmCore

@MainActor
final class RootViewModelTests: XCTestCase {
    func test_start_routesToHome_whenNoAlarmIsAlerting() async {
        let alarmService = FakeAlarmSchedulingService()
        let viewModel = RootViewModel(alarmService: alarmService)

        await viewModel.start()

        XCTAssertEqual(viewModel.route, .home)
    }

    func test_start_routesToRinging_whenAnAlarmIsAlerting() async {
        let alarmService = FakeAlarmSchedulingService()
        let alertingID = UUID()
        alarmService.alertingIDToReturn = alertingID
        let viewModel = RootViewModel(alarmService: alarmService)

        await viewModel.start()

        XCTAssertEqual(viewModel.route, .ringing)
        XCTAssertEqual(alarmService.syncedAlarmID, alertingID)
    }

    func test_alertingUpdate_routesToRinging_whileObserving() async {
        let alarmService = FakeAlarmSchedulingService()
        let viewModel = RootViewModel(alarmService: alarmService)
        await viewModel.start()
        XCTAssertEqual(viewModel.route, .home)

        let alertingID = UUID()
        alarmService.simulateAlertingUpdate(alertingID)
        await Task.yield()

        XCTAssertEqual(viewModel.route, .ringing)
        XCTAssertEqual(alarmService.syncedAlarmID, alertingID)
    }

    func test_alertingUpdateClears_routesBackToHomeAndCancelsAlarm() async {
        let alarmService = FakeAlarmSchedulingService()
        alarmService.alertingIDToReturn = UUID()
        let viewModel = RootViewModel(alarmService: alarmService)
        await viewModel.start()
        XCTAssertEqual(viewModel.route, .ringing)

        // Simulates the system Stop button being tapped while foregrounded —
        // AlarmKit's alarmUpdates stream reports the alarm is no longer alerting.
        alarmService.simulateAlertingUpdate(nil)
        await Task.yield()

        XCTAssertEqual(viewModel.route, .home)
        XCTAssertTrue(alarmService.wasCancelled)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Push and check CI (no local toolchain) — expected: compile failure, `RootViewModel` does not exist yet.

- [ ] **Step 3: Implement `RootViewModel`**

Create `Sources/AffirmAlarmCore/RootViewModel.swift`:
```swift
import Foundation

@MainActor
public final class RootViewModel: ObservableObject {
    public enum Route: Equatable {
        case home
        case ringing
    }

    @Published public private(set) var route: Route = .home

    private let alarmService: AlarmSchedulingService
    private var updatesTask: Task<Void, Never>?

    public init(alarmService: AlarmSchedulingService) {
        self.alarmService = alarmService
    }

    public func start() async {
        // UI-test-only hook: real AlarmKit alerts cannot be simulated in the
        // CI simulator, so a launch argument forces the ringing route
        // directly for AlarmRingUITests, bypassing any real AlarmManager call.
        if ProcessInfo.processInfo.arguments.contains("-uiTestForceRinging") {
            route = .ringing
            return
        }

        if let alertingID = await alarmService.currentlyAlertingAlarmID() {
            alarmService.syncActiveAlarm(id: alertingID)
            route = .ringing
        }
        observeUpdates()
    }

    private func observeUpdates() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await alertingID in alarmService.alertingAlarmUpdates() {
                await self.handleUpdate(alertingID: alertingID)
            }
        }
    }

    private func handleUpdate(alertingID: UUID?) async {
        if let alertingID {
            alarmService.syncActiveAlarm(id: alertingID)
            route = .ringing
        } else if route == .ringing {
            alarmService.cancelAlarm()
            route = .home
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Push and check CI. Expected: all four `RootViewModelTests` pass.

- [ ] **Step 5: Create `RootView` and fix the now-outdated ring-screen UI tests**

Create `Sources/AffirmAlarm/RootView.swift` (Task 3 will add the real `HomeView`; this step uses a temporary minimal placeholder `Text` for `.home` that Task 3 replaces in the same file):
```swift
import SwiftUI
import AffirmAlarmCore

struct RootView: View {
    @StateObject var rootViewModel: RootViewModel
    let alarmRingViewModel: AlarmRingViewModel

    var body: some View {
        Group {
            switch rootViewModel.route {
            case .home:
                Text("Home")
                    .accessibilityIdentifier("homePlaceholder")
            case .ringing:
                AlarmRingView(viewModel: alarmRingViewModel)
            }
        }
        .task { await rootViewModel.start() }
    }
}
```

This placeholder `Text("Home")` is replaced by the real `HomeView` in Task 3, Step 5 below — it exists here only so `RootView` compiles as a self-contained deliverable for this task's review; it is not left in place after Task 3.

Update `Tests/AffirmAlarmUITests/AlarmRingUITests.swift` to force the ringing route, since `RootView` now defaults to Home on a fresh launch (no alarm is ever actually alerting in the CI simulator):
```swift
import XCTest

final class AlarmRingUITests: XCTestCase {
    func test_snoozeButton_isVisibleOnLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestForceRinging"]
        app.launch()
        XCTAssertTrue(app.buttons["snoozeButton"].waitForExistence(timeout: 5))
    }

    func test_closeButton_isVisibleOnLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestForceRinging"]
        app.launch()
        XCTAssertTrue(app.buttons["closeButton"].waitForExistence(timeout: 5))
    }

    func test_holdToSpeakButton_isVisibleOnLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestForceRinging"]
        app.launch()
        XCTAssertTrue(app.otherElements["holdToSpeakButton"].waitForExistence(timeout: 5))
    }
}
```

Do not wire `RootView` into `AffirmAlarmApp.swift` yet — that happens in Task 11 once `HomeView` (Task 3) is real. Leaving `AffirmAlarmApp.swift` on the direct `AlarmRingView(...)` root for now means these updated UI tests will still fail until Task 11; that's expected and acceptable since `RootViewModelTests` (this task's actual deliverable) already passes on CI. Note this explicitly in the task report so the reviewer doesn't expect green UI tests yet.

- [ ] **Step 6: Commit**

```bash
git add Sources/AffirmAlarmCore/RootViewModel.swift Sources/AffirmAlarm/RootView.swift Tests/AffirmAlarmCoreTests/RootViewModelTests.swift Tests/AffirmAlarmUITests/AlarmRingUITests.swift
git commit -m "feat: add RootViewModel routing between Home and the ring screen"
```

---

### Task 3: HomeView — real alarm-setting UI

**Files:**
- Create: `Sources/AffirmAlarmCore/HomeViewModel.swift`
- Create: `Sources/AffirmAlarm/HomeView.swift`
- Modify: `Sources/AffirmAlarm/RootView.swift` (replace the Step-5 placeholder)
- Modify: `Tests/AffirmAlarmUITests/AlarmRingUITests.swift` (add a Home-screen coverage test)
- Test: `Tests/AffirmAlarmCoreTests/HomeViewModelTests.swift`

**Interfaces:**
- Consumes: `AlarmSchedulingService.scheduleAlarm(at:) async throws` (Task 1), `StreakStore.loadStreakState()` (existing), `RootViewModel.Route.home` (Task 2)
- Produces: `HomeViewModel` — Tasks 6, 9, 11 each add one navigation entry point onto the `HomeView` this task creates.

- [ ] **Step 1: Write the failing tests**

Create `Tests/AffirmAlarmCoreTests/HomeViewModelTests.swift`:
```swift
import XCTest
@testable import AffirmAlarmCore

@MainActor
final class HomeViewModelTests: XCTestCase {
    func test_init_loadsCurrentStreakDay() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(StreakState(streakDay: 5, lastCompletedDate: nil))
        let viewModel = HomeViewModel(alarmService: FakeAlarmSchedulingService(), store: store)

        XCTAssertEqual(viewModel.streakDay, 5)
    }

    func test_saveAlarmTime_success_setsScheduledTime() async {
        let alarmService = FakeAlarmSchedulingService()
        let viewModel = HomeViewModel(alarmService: alarmService, store: SwiftDataStreakStore(inMemory: true))
        viewModel.selectedTime = DateComponents(hour: 7, minute: 30)

        await viewModel.saveAlarmTime()

        XCTAssertEqual(viewModel.scheduledTime, DateComponents(hour: 7, minute: 30))
        XCTAssertEqual(alarmService.scheduledTime, DateComponents(hour: 7, minute: 30))
        XCTAssertNil(viewModel.schedulingError)
    }

    func test_saveAlarmTime_failure_setsErrorAndLeavesScheduledTimeNil() async {
        let alarmService = FakeAlarmSchedulingService()
        alarmService.scheduleAlarmError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "denied"])
        let viewModel = HomeViewModel(alarmService: alarmService, store: SwiftDataStreakStore(inMemory: true))
        viewModel.selectedTime = DateComponents(hour: 7, minute: 30)

        await viewModel.saveAlarmTime()

        XCTAssertNil(viewModel.scheduledTime)
        XCTAssertEqual(viewModel.schedulingError, "denied")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Push and check CI — expected: compile failure, `HomeViewModel` does not exist.

- [ ] **Step 3: Implement `HomeViewModel`**

Create `Sources/AffirmAlarmCore/HomeViewModel.swift`:
```swift
import Foundation

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public var selectedTime = DateComponents(hour: 7, minute: 0)
    @Published public private(set) var scheduledTime: DateComponents?
    @Published public private(set) var schedulingError: String?
    @Published public private(set) var streakDay: Int

    private let alarmService: AlarmSchedulingService
    private let store: StreakStore

    public init(alarmService: AlarmSchedulingService, store: StreakStore) {
        self.alarmService = alarmService
        self.store = store
        self.streakDay = store.loadStreakState().streakDay
    }

    public func saveAlarmTime() async {
        schedulingError = nil
        do {
            try await alarmService.scheduleAlarm(at: selectedTime)
            scheduledTime = selectedTime
        } catch {
            schedulingError = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Push and check CI. Expected: all three `HomeViewModelTests` pass.

- [ ] **Step 5: Build `HomeView` and wire it into `RootView`**

Create `Sources/AffirmAlarm/HomeView.swift`:
```swift
import SwiftUI
import AffirmAlarmCore

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Alarm") {
                    DatePicker(
                        "Time",
                        selection: Binding(
                            get: { viewModel.selectedTime.date ?? Date() },
                            set: { viewModel.selectedTime = Calendar.current.dateComponents([.hour, .minute], from: $0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityIdentifier("alarmTimePicker")

                    if let scheduledTime = viewModel.scheduledTime {
                        Text("Alarm set for \(scheduledTime.hour ?? 0):\(String(format: "%02d", scheduledTime.minute ?? 0))")
                            .accessibilityIdentifier("scheduledTimeLabel")
                    } else {
                        Text("No alarm set")
                            .accessibilityIdentifier("noAlarmSetLabel")
                    }

                    if let error = viewModel.schedulingError {
                        Text(error).foregroundColor(.red)
                    }

                    Button("Save alarm") {
                        Task { await viewModel.saveAlarmTime() }
                    }
                    .accessibilityIdentifier("saveAlarmButton")
                }

                Section("Streak") {
                    Text("Day \(viewModel.streakDay)")
                        .accessibilityIdentifier("streakDayLabel")
                }
            }
            .navigationTitle("AffirmAlarm")
        }
    }
}

private extension DateComponents {
    var date: Date? {
        guard let hour, let minute else { return nil }
        return Calendar.current.date(from: DateComponents(hour: hour, minute: minute))
    }
}
```

Replace the placeholder in `Sources/AffirmAlarm/RootView.swift` (from Task 2, Step 5):
```swift
struct RootView: View {
    @StateObject var rootViewModel: RootViewModel
    let alarmRingViewModel: AlarmRingViewModel
    let homeViewModel: HomeViewModel

    var body: some View {
        Group {
            switch rootViewModel.route {
            case .home:
                HomeView(viewModel: homeViewModel)
            case .ringing:
                AlarmRingView(viewModel: alarmRingViewModel)
            }
        }
        .task { await rootViewModel.start() }
    }
}
```

- [ ] **Step 6: Add UI coverage for the new default (Home) launch screen**

Add to `Tests/AffirmAlarmUITests/AlarmRingUITests.swift` (this file now covers both screens; renaming it is not required — its tests changed at Task 2, not its purpose enough to warrant a rename):
```swift
    func test_homeScreen_isVisibleOnNormalLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.datePickers["alarmTimePicker"].waitForExistence(timeout: 5))
    }
```

This test will only pass once Task 11 wires `RootView` into `AffirmAlarmApp.swift` — same expected-not-yet-green situation as Task 2's updated tests, note it in the task report.

- [ ] **Step 7: Commit**

```bash
git add Sources/AffirmAlarmCore/HomeViewModel.swift Sources/AffirmAlarm/HomeView.swift Sources/AffirmAlarm/RootView.swift Tests/AffirmAlarmCoreTests/HomeViewModelTests.swift Tests/AffirmAlarmUITests/AlarmRingUITests.swift
git commit -m "feat: add HomeView with real alarm-setting UI"
```

---

### Task 4: Data model — chat history, generation events, consent

**Files:**
- Modify: `Sources/AffirmAlarmCore/Models.swift`
- Modify: `Sources/AffirmAlarmCore/StreakStore.swift`
- Test: `Tests/AffirmAlarmCoreTests/StreakStoreTests.swift`

**Interfaces:**
- Produces: `ChatRole`, `ChatSessionType` enums; `ChatMessage`, `AffirmationGenerationEvent`, `ConsentState` structs; `StreakStore` protocol additions (`loadConsentState`/`save(_:ConsentState)`, `appendChatMessage`/`loadChatHistory`, `recordGenerationEvent`/`loadGenerationEvents`). Tasks 5-10 all consume these types.

- [ ] **Step 1: Add the plain value types**

Append to `Sources/AffirmAlarmCore/Models.swift`:
```swift
public enum ChatRole: String, Codable, Equatable {
    case user
    case assistant
}

public enum ChatSessionType: String, Codable, Equatable {
    case onboarding
    case checkIn
}

public struct ChatMessage: Identifiable, Codable, Equatable {
    public let id: UUID
    public var role: ChatRole
    public var text: String
    public var timestamp: Date
    public var sessionType: ChatSessionType

    public init(id: UUID = UUID(), role: ChatRole, text: String, timestamp: Date, sessionType: ChatSessionType) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.sessionType = sessionType
    }
}

public struct AffirmationGenerationEvent: Identifiable, Codable, Equatable {
    public let id: UUID
    public var date: Date
    public var sessionType: ChatSessionType
    public var generatedTexts: [String]

    public init(id: UUID = UUID(), date: Date, sessionType: ChatSessionType, generatedTexts: [String]) {
        self.id = id
        self.date = date
        self.sessionType = sessionType
        self.generatedTexts = generatedTexts
    }
}

public struct ConsentState: Codable, Equatable {
    public var hasOptedIn: Bool
    public var decidedAt: Date?

    public init(hasOptedIn: Bool, decidedAt: Date?) {
        self.hasOptedIn = hasOptedIn
        self.decidedAt = decidedAt
    }
}
```

- [ ] **Step 2: Write the failing tests**

Append to `Tests/AffirmAlarmCoreTests/StreakStoreTests.swift`:
```swift
    func test_loadConsentState_defaultsToNotDecidedWhenEmpty() {
        let store = SwiftDataStreakStore(inMemory: true)
        let consent = store.loadConsentState()
        XCTAssertFalse(consent.hasOptedIn)
        XCTAssertNil(consent.decidedAt)
    }

    func test_saveThenLoad_roundTripsConsentState() {
        let store = SwiftDataStreakStore(inMemory: true)
        let saved = ConsentState(hasOptedIn: true, decidedAt: Date(timeIntervalSince1970: 2_000_000))
        store.save(saved)
        XCTAssertEqual(store.loadConsentState(), saved)
    }

    func test_appendChatMessage_thenLoadChatHistory_roundTripsInTimestampOrder() {
        let store = SwiftDataStreakStore(inMemory: true)
        let first = ChatMessage(role: .user, text: "hi", timestamp: Date(timeIntervalSince1970: 1), sessionType: .onboarding)
        let second = ChatMessage(role: .assistant, text: "hello", timestamp: Date(timeIntervalSince1970: 2), sessionType: .onboarding)
        store.appendChatMessage(second)
        store.appendChatMessage(first)

        XCTAssertEqual(store.loadChatHistory(), [first, second])
    }

    func test_recordGenerationEvent_thenLoadGenerationEvents_roundTripsNewestFirst() {
        let store = SwiftDataStreakStore(inMemory: true)
        let older = AffirmationGenerationEvent(date: Date(timeIntervalSince1970: 1), sessionType: .onboarding, generatedTexts: ["a"])
        let newer = AffirmationGenerationEvent(date: Date(timeIntervalSince1970: 2), sessionType: .checkIn, generatedTexts: ["b", "c"])
        store.recordGenerationEvent(older)
        store.recordGenerationEvent(newer)

        XCTAssertEqual(store.loadGenerationEvents(), [newer, older])
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Push and check CI — expected: compile failure, `StreakStore` has no such members yet.

- [ ] **Step 4: Add the SwiftData records and implement the protocol methods**

In `Sources/AffirmAlarmCore/StreakStore.swift`, add three new `@Model` classes after `AffirmationRecord` (line 36):
```swift
@Model
final class ChatMessageRecord {
    var id: UUID
    var role: ChatRole
    var text: String
    var timestamp: Date
    var sessionType: ChatSessionType
    init(id: UUID, role: ChatRole, text: String, timestamp: Date, sessionType: ChatSessionType) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.sessionType = sessionType
    }
}

@Model
final class AffirmationGenerationEventRecord {
    var id: UUID
    var date: Date
    var sessionType: ChatSessionType
    var generatedTexts: [String]
    init(id: UUID, date: Date, sessionType: ChatSessionType, generatedTexts: [String]) {
        self.id = id
        self.date = date
        self.sessionType = sessionType
        self.generatedTexts = generatedTexts
    }
}

@Model
final class ConsentStateRecord {
    var hasOptedIn: Bool
    var decidedAt: Date?
    init(hasOptedIn: Bool, decidedAt: Date?) {
        self.hasOptedIn = hasOptedIn
        self.decidedAt = decidedAt
    }
}
```

If CI reports that `@Model` rejects `ChatRole`/`ChatSessionType` as stored property types directly, the fallback is to store `var roleRaw: String` / `var sessionTypeRaw: String` instead and convert via `ChatRole(rawValue:)` in the mapping code below — the same escape hatch used nowhere yet in this codebase but consistent with how `AffirmationRecord` stores only primitive/UUID fields today.

Extend the `StreakStore` protocol (lines 38-45):
```swift
public protocol StreakStore {
    func loadStreakState() -> StreakState
    func save(_ state: StreakState)
    func loadCloseUsage() -> CloseUsageRecord
    func save(_ usage: CloseUsageRecord)
    func loadAffirmations() -> [Affirmation]
    func save(_ affirmations: [Affirmation])
    func loadConsentState() -> ConsentState
    func save(_ consent: ConsentState)
    func appendChatMessage(_ message: ChatMessage)
    func loadChatHistory() -> [ChatMessage]
    func recordGenerationEvent(_ event: AffirmationGenerationEvent)
    func loadGenerationEvents() -> [AffirmationGenerationEvent]
}
```

Update the `Schema([...])` list in `SwiftDataStreakStore.init` (line 62) to include the three new record types:
```swift
        let schema = Schema([
            StreakStateRecord.self,
            CloseUsageRecordEntity.self,
            AffirmationRecord.self,
            ChatMessageRecord.self,
            AffirmationGenerationEventRecord.self,
            ConsentStateRecord.self
        ])
```

Add the six new method implementations to `SwiftDataStreakStore` (after `save(_ affirmations:)`, before the closing brace):
```swift
    public func loadConsentState() -> ConsentState {
        let records = try? context.fetch(FetchDescriptor<ConsentStateRecord>())
        guard let record = records?.first else { return ConsentState(hasOptedIn: false, decidedAt: nil) }
        return ConsentState(hasOptedIn: record.hasOptedIn, decidedAt: record.decidedAt)
    }

    public func save(_ consent: ConsentState) {
        let existing = try? context.fetch(FetchDescriptor<ConsentStateRecord>())
        existing?.forEach { context.delete($0) }
        context.insert(ConsentStateRecord(hasOptedIn: consent.hasOptedIn, decidedAt: consent.decidedAt))
        try? context.save()
    }

    public func appendChatMessage(_ message: ChatMessage) {
        context.insert(ChatMessageRecord(id: message.id, role: message.role, text: message.text, timestamp: message.timestamp, sessionType: message.sessionType))
        try? context.save()
    }

    public func loadChatHistory() -> [ChatMessage] {
        let descriptor = FetchDescriptor<ChatMessageRecord>(sortBy: [SortDescriptor(\.timestamp)])
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map { ChatMessage(id: $0.id, role: $0.role, text: $0.text, timestamp: $0.timestamp, sessionType: $0.sessionType) }
    }

    public func recordGenerationEvent(_ event: AffirmationGenerationEvent) {
        context.insert(AffirmationGenerationEventRecord(id: event.id, date: event.date, sessionType: event.sessionType, generatedTexts: event.generatedTexts))
        try? context.save()
    }

    public func loadGenerationEvents() -> [AffirmationGenerationEvent] {
        let descriptor = FetchDescriptor<AffirmationGenerationEventRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map { AffirmationGenerationEvent(id: $0.id, date: $0.date, sessionType: $0.sessionType, generatedTexts: $0.generatedTexts) }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Push and check CI. Expected: all four new `StreakStoreTests` pass, and all pre-existing `StreakStoreTests` still pass unchanged (they don't touch the new schema entries).

- [ ] **Step 6: Commit**

```bash
git add Sources/AffirmAlarmCore/Models.swift Sources/AffirmAlarmCore/StreakStore.swift Tests/AffirmAlarmCoreTests/StreakStoreTests.swift
git commit -m "feat: add chat history, generation event, and consent persistence"
```

---

### Task 5: `AIContentService` protocol and on-device implementation

**Files:**
- Create: `Sources/AffirmAlarmCore/AIContentService.swift`
- Create: `Sources/AffirmAlarmCore/OnDeviceAIContentService.swift`
- Modify: `Tests/AffirmAlarmCoreTests/Fakes.swift`

**Interfaces:**
- Consumes: `ChatMessage` (Task 4)
- Produces: `AIContentService` protocol (`isAvailable() async -> Bool`, `sendMessage(_:history:) async throws -> String`, `generateAffirmations(from:) async throws -> [String]`), `AIContentError`. Tasks 6, 7, 8 consume this protocol.

- [ ] **Step 1: Define the protocol and error type**

Create `Sources/AffirmAlarmCore/AIContentService.swift`:
```swift
import Foundation

public enum AIContentError: Error {
    case unavailable
    case generationFailed
}

public protocol AIContentService: AnyObject {
    func isAvailable() async -> Bool
    func sendMessage(_ message: String, history: [ChatMessage]) async throws -> String
    func generateAffirmations(from history: [ChatMessage]) async throws -> [String]
}
```

- [ ] **Step 2: Add a fake for use by Tasks 6-8's tests**

Append to `Tests/AffirmAlarmCoreTests/Fakes.swift`:
```swift
final class FakeAIContentService: AIContentService {
    var availabilityToReturn = true
    var sendMessageResult: Result<String, Error> = .success("Thanks for sharing.")
    var generateAffirmationsResult: Result<[String], Error> = .success(["I am capable"])
    private(set) var sentMessages: [String] = []
    private(set) var generateCallCount = 0

    func isAvailable() async -> Bool {
        availabilityToReturn
    }

    func sendMessage(_ message: String, history: [ChatMessage]) async throws -> String {
        sentMessages.append(message)
        return try sendMessageResult.get()
    }

    func generateAffirmations(from history: [ChatMessage]) async throws -> [String] {
        generateCallCount += 1
        return try generateAffirmationsResult.get()
    }
}
```

This fake has no test of its own — it exists for Tasks 6-8 to consume, same as `FakeSpeechRecognitionService` exists purely for `AlarmRingViewModelTests`. Compile it now so this task's CI run proves it type-checks against the real protocol.

- [ ] **Step 3: Implement the on-device service**

Create `Sources/AffirmAlarmCore/OnDeviceAIContentService.swift`:
```swift
import Foundation
import FoundationModels

@Generable
struct AffirmationList {
    @Guide(description: "A list of short, second-person, present-tense affirmations based on the conversation.")
    var affirmations: [String]
}

public final class OnDeviceAIContentService: AIContentService {
    public init() {}

    public func isAvailable() async -> Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        case .unavailable:
            return false
        @unknown default:
            return false
        }
    }

    public func sendMessage(_ message: String, history: [ChatMessage]) async throws -> String {
        guard await isAvailable() else { throw AIContentError.unavailable }
        let session = LanguageModelSession(transcript: Self.transcript(from: history))
        do {
            let response = try await session.respond(to: message)
            return response.content
        } catch {
            throw AIContentError.generationFailed
        }
    }

    public func generateAffirmations(from history: [ChatMessage]) async throws -> [String] {
        guard await isAvailable() else { throw AIContentError.unavailable }
        let session = LanguageModelSession(transcript: Self.transcript(from: history))
        do {
            let response = try await session.respond(
                to: "Based on this conversation, write the affirmations we discussed.",
                generating: AffirmationList.self
            )
            return response.content.affirmations
        } catch {
            throw AIContentError.generationFailed
        }
    }

    private static func transcript(from history: [ChatMessage]) -> Transcript {
        Transcript(entries: history.map { message in
            switch message.role {
            case .user:
                return .prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: message.text))]))
            case .assistant:
                return .response(Transcript.Response(assetIDs: [], segments: [.text(Transcript.TextSegment(content: message.text))]))
            }
        })
    }
}
```

This is the plan's highest-uncertainty piece: `FoundationModels`' exact type names (`LanguageModelSession`, `Transcript`, `@Generable`, `@Guide`, `SystemLanguageModel.default.availability`'s exact case set) cannot be verified without a real compiler, the same situation Phase 1 was in for `AlarmManager.AlarmConfiguration`. Expect 2-3 CI round trips here. If `LanguageModelSession(transcript:)` doesn't exist, the fallback is `LanguageModelSession()` (fresh session per call, no cross-call history) plus manually prepending prior turns as extra context text into the `to:` prompt string — functionally equivalent, just without the framework's native transcript type. Do not spend more than 3 CI iterations guessing blind; if still failing after that, report DONE_WITH_CONCERNS with the exact compiler errors so the controller can supply corrected API names from the AlarmKit-adjacent Apple documentation already in the repo (`alarmkit apple.docx` may not cover FoundationModels — check for any other Apple doc files in the repo root first).

- [ ] **Step 4: Push and verify on CI**

Commit, push, check CI. `AffirmAlarmCoreTests` and `AffirmAlarmUITests` schemes must both still compile (this file is part of `AffirmAlarmCore`, built by both schemes).

- [ ] **Step 5: Commit**

```bash
git add Sources/AffirmAlarmCore/AIContentService.swift Sources/AffirmAlarmCore/OnDeviceAIContentService.swift Tests/AffirmAlarmCoreTests/Fakes.swift
git commit -m "feat: add AIContentService protocol and on-device FoundationModels implementation"
```

---

### Task 6: Manual affirmation editing (also the AI-generation review screen)

**Files:**
- Create: `Sources/AffirmAlarmCore/AffirmationEditViewModel.swift`
- Create: `Sources/AffirmAlarm/AffirmationEditView.swift`
- Modify: `Sources/AffirmAlarm/HomeView.swift`
- Test: `Tests/AffirmAlarmCoreTests/AffirmationEditViewModelTests.swift`

**Interfaces:**
- Consumes: `StreakStore.loadAffirmations()`/`save(_:)` (existing), `IntensityEngine.level(forStreakDay:)` (existing)
- Produces: `AffirmationEditViewModel(store:initialTexts:)` — Task 8 (`ChatView`) consumes this initializer's `initialTexts:` parameter to hand off AI-generated text for review.

- [ ] **Step 1: Write the failing tests**

Create `Tests/AffirmAlarmCoreTests/AffirmationEditViewModelTests.swift`:
```swift
import XCTest
@testable import AffirmAlarmCore

@MainActor
final class AffirmationEditViewModelTests: XCTestCase {
    func test_init_withNoInitialTexts_loadsFromStore() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save([Affirmation(text: "Existing", isUserAuthored: true)])
        let viewModel = AffirmationEditViewModel(store: store)

        XCTAssertEqual(viewModel.affirmations.map(\.text), ["Existing"])
    }

    func test_init_withInitialTexts_prefillsFromThoseTextsInstead() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save([Affirmation(text: "Existing", isUserAuthored: true)])
        let viewModel = AffirmationEditViewModel(store: store, initialTexts: ["Generated one", "Generated two"])

        XCTAssertEqual(viewModel.affirmations.map(\.text), ["Generated one", "Generated two"])
    }

    func test_addAffirmation_appendsEmptyEntry() {
        let viewModel = AffirmationEditViewModel(store: SwiftDataStreakStore(inMemory: true), initialTexts: ["One", "Two"])
        viewModel.addAffirmation()
        XCTAssertEqual(viewModel.affirmations.count, 3)
        XCTAssertEqual(viewModel.affirmations.last?.text, "")
    }

    func test_removeAffirmation_removesAtOffset() {
        let viewModel = AffirmationEditViewModel(store: SwiftDataStreakStore(inMemory: true), initialTexts: ["One", "Two"])
        viewModel.removeAffirmation(at: IndexSet(integer: 0))
        XCTAssertEqual(viewModel.affirmations.map(\.text), ["Two"])
    }

    func test_save_succeeds_whenEnoughNonEmptyAffirmationsForStreakDay() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(StreakState(streakDay: 1, lastCompletedDate: nil)) // requires 1
        let viewModel = AffirmationEditViewModel(store: store, initialTexts: ["Only one"])

        XCTAssertTrue(viewModel.save())
        XCTAssertNil(viewModel.validationError)
        XCTAssertEqual(store.loadAffirmations().map(\.text), ["Only one"])
    }

    func test_save_fails_whenFewerThanRequiredForStreakDay() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(StreakState(streakDay: 20, lastCompletedDate: nil)) // requires 2, per IntensityEngine
        let viewModel = AffirmationEditViewModel(store: store, initialTexts: ["Only one"])

        XCTAssertFalse(viewModel.save())
        XCTAssertNotNil(viewModel.validationError)
    }

    func test_save_ignoresBlankEntriesWhenCountingTowardRequirement() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(StreakState(streakDay: 1, lastCompletedDate: nil)) // requires 1
        let viewModel = AffirmationEditViewModel(store: store, initialTexts: ["Real one", "   "])

        XCTAssertTrue(viewModel.save())
        XCTAssertEqual(store.loadAffirmations().map(\.text), ["Real one"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Push and check CI — expected: compile failure, `AffirmationEditViewModel` does not exist.

- [ ] **Step 3: Implement `AffirmationEditViewModel`**

Create `Sources/AffirmAlarmCore/AffirmationEditViewModel.swift`:
```swift
import Foundation

@MainActor
public final class AffirmationEditViewModel: ObservableObject {
    @Published public var affirmations: [Affirmation]
    @Published public private(set) var validationError: String?

    private let store: StreakStore

    public init(store: StreakStore, initialTexts: [String]? = nil) {
        self.store = store
        if let initialTexts {
            self.affirmations = initialTexts.map { Affirmation(text: $0, isUserAuthored: false) }
        } else {
            self.affirmations = store.loadAffirmations()
        }
    }

    public func addAffirmation() {
        affirmations.append(Affirmation(text: "", isUserAuthored: true))
    }

    public func removeAffirmation(at offsets: IndexSet) {
        affirmations.remove(atOffsets: offsets)
    }

    public func moveAffirmation(from source: IndexSet, to destination: Int) {
        affirmations.move(fromOffsets: source, toOffset: destination)
    }

    @discardableResult
    public func save() -> Bool {
        let nonEmpty = affirmations.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let requiredCount = IntensityEngine.level(forStreakDay: store.loadStreakState().streakDay).affirmationCount
        guard nonEmpty.count >= requiredCount else {
            validationError = "Add at least \(requiredCount) affirmation\(requiredCount == 1 ? "" : "s") for your current streak level."
            return false
        }
        validationError = nil
        store.save(nonEmpty)
        return true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Push and check CI. Expected: all seven `AffirmationEditViewModelTests` pass.

- [ ] **Step 5: Build `AffirmationEditView` and wire it into `HomeView`**

Create `Sources/AffirmAlarm/AffirmationEditView.swift`:
```swift
import SwiftUI
import AffirmAlarmCore

struct AffirmationEditView: View {
    @ObservedObject var viewModel: AffirmationEditViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let error = viewModel.validationError {
                Text(error).foregroundColor(.red)
            }
            ForEach($viewModel.affirmations) { $affirmation in
                TextField("Affirmation", text: $affirmation.text)
            }
            .onDelete { viewModel.removeAffirmation(at: $0) }
            .onMove { viewModel.moveAffirmation(from: $0, to: $1) }

            Button("Add affirmation") { viewModel.addAffirmation() }
                .accessibilityIdentifier("addAffirmationButton")
        }
        .toolbar { EditButton() }
        .navigationTitle("Your Affirmations")
        .safeAreaInset(edge: .bottom) {
            Button("Save") {
                if viewModel.save() { dismiss() }
            }
            .accessibilityIdentifier("saveAffirmationsButton")
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}
```

In `Sources/AffirmAlarm/HomeView.swift`, add a navigation entry point. Wrap the `Form` in a `NavigationLink` destination by adding a new section after "Streak":
```swift
                Section {
                    NavigationLink("Edit affirmations") {
                        AffirmationEditView(viewModel: AffirmationEditViewModel(store: viewModel.store))
                    }
                    .accessibilityIdentifier("editAffirmationsLink")
                }
```

This requires exposing the store from `HomeViewModel` — add to `Sources/AffirmAlarmCore/HomeViewModel.swift`:
```swift
    public let store: StreakStore
```
and set it in `init` alongside the existing `self.store = store` assignment (rename the existing `private let store` to `public let store` — there is exactly one existing assignment site to update, no other reads of `store` exist in `HomeViewModel` today besides `store.loadStreakState()` in `init` and `alarmService`/`store` in `saveAlarmTime()`, neither of which changes).

- [ ] **Step 6: Push and verify on CI**

Push, check CI. `AffirmAlarmCoreTests` and `AffirmAlarmUITests` schemes both green.

- [ ] **Step 7: Commit**

```bash
git add Sources/AffirmAlarmCore/AffirmationEditViewModel.swift Sources/AffirmAlarm/AffirmationEditView.swift Sources/AffirmAlarm/HomeView.swift Sources/AffirmAlarmCore/HomeViewModel.swift Tests/AffirmAlarmCoreTests/AffirmationEditViewModelTests.swift
git commit -m "feat: add manual affirmation editing, doubles as AI-generation review screen"
```

---

### Task 7: `ChatViewModel` — consent-gated messaging and generation

**Files:**
- Create: `Sources/AffirmAlarmCore/ChatViewModel.swift`
- Test: `Tests/AffirmAlarmCoreTests/ChatViewModelTests.swift`

**Interfaces:**
- Consumes: `AIContentService` (Task 5), `StreakStore`'s consent/chat/generation methods (Task 4)
- Produces: `ChatViewModel(aiService:store:sessionType:)`, `@Published var messages/turnState/needsConsentDecision/canGenerate/generatedAffirmations`. Task 8 (`ChatView`, `ConsentView`) consumes all of these.

- [ ] **Step 1: Write the failing tests**

Create `Tests/AffirmAlarmCoreTests/ChatViewModelTests.swift`:
```swift
import XCTest
@testable import AffirmAlarmCore

@MainActor
final class ChatViewModelTests: XCTestCase {
    func test_start_needsConsentDecision_whenNeverDecided() async {
        let viewModel = makeViewModel()
        await viewModel.start()
        XCTAssertTrue(viewModel.needsConsentDecision)
    }

    func test_start_loadsHistory_whenPreviouslyOptedIn() async {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(ConsentState(hasOptedIn: true, decidedAt: Date()))
        let existing = ChatMessage(role: .user, text: "hi", timestamp: Date(), sessionType: .onboarding)
        store.appendChatMessage(existing)
        let viewModel = makeViewModel(store: store)

        await viewModel.start()

        XCTAssertFalse(viewModel.needsConsentDecision)
        XCTAssertEqual(viewModel.messages, [existing])
    }

    func test_start_doesNotLoadHistory_whenPreviouslyDeclined() async {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(ConsentState(hasOptedIn: false, decidedAt: Date()))
        store.appendChatMessage(ChatMessage(role: .user, text: "leftover", timestamp: Date(), sessionType: .onboarding))
        let viewModel = makeViewModel(store: store)

        await viewModel.start()

        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func test_recordConsent_optIn_clearsNeedsDecisionAndPersists() {
        let store = SwiftDataStreakStore(inMemory: true)
        let viewModel = makeViewModel(store: store)

        viewModel.recordConsent(optedIn: true)

        XCTAssertFalse(viewModel.needsConsentDecision)
        XCTAssertTrue(store.loadConsentState().hasOptedIn)
    }

    func test_send_appendsUserAndAssistantMessages_andEnablesGenerate() async {
        let ai = FakeAIContentService()
        ai.sendMessageResult = .success("Good to hear.")
        let viewModel = makeViewModel(ai: ai)
        viewModel.recordConsent(optedIn: false)

        await viewModel.send("I'm doing well")

        XCTAssertEqual(viewModel.messages.map(\.text), ["I'm doing well", "Good to hear."])
        XCTAssertTrue(viewModel.canGenerate)
        XCTAssertEqual(viewModel.turnState, .idle)
    }

    func test_send_persistsMessages_onlyWhenOptedIn() async {
        let store = SwiftDataStreakStore(inMemory: true)
        let viewModel = makeViewModel(store: store)
        viewModel.recordConsent(optedIn: true)

        await viewModel.send("hello")

        XCTAssertEqual(store.loadChatHistory().count, 2)
    }

    func test_send_doesNotPersist_whenDeclined() async {
        let store = SwiftDataStreakStore(inMemory: true)
        let viewModel = makeViewModel(store: store)
        viewModel.recordConsent(optedIn: false)

        await viewModel.send("hello")

        XCTAssertTrue(store.loadChatHistory().isEmpty)
    }

    func test_send_failure_setsErrorState() async {
        let ai = FakeAIContentService()
        ai.sendMessageResult = .failure(AIContentError.generationFailed)
        let viewModel = makeViewModel(ai: ai)
        viewModel.recordConsent(optedIn: false)

        await viewModel.send("hello")

        guard case .error = viewModel.turnState else {
            return XCTFail("expected .error turnState")
        }
    }

    func test_generateAffirmations_success_setsGeneratedAffirmationsAndPersistsEventWhenOptedIn() async {
        let store = SwiftDataStreakStore(inMemory: true)
        let ai = FakeAIContentService()
        ai.generateAffirmationsResult = .success(["I am capable", "I am calm"])
        let viewModel = makeViewModel(ai: ai, store: store)
        viewModel.recordConsent(optedIn: true)

        await viewModel.generateAffirmations()

        XCTAssertEqual(viewModel.generatedAffirmations, ["I am capable", "I am calm"])
        XCTAssertEqual(store.loadGenerationEvents().first?.generatedTexts, ["I am capable", "I am calm"])
    }

    func test_generateAffirmations_failure_setsErrorState() async {
        let ai = FakeAIContentService()
        ai.generateAffirmationsResult = .failure(AIContentError.generationFailed)
        let viewModel = makeViewModel(ai: ai)
        viewModel.recordConsent(optedIn: false)

        await viewModel.generateAffirmations()

        guard case .error = viewModel.turnState else {
            return XCTFail("expected .error turnState")
        }
        XCTAssertNil(viewModel.generatedAffirmations)
    }

    private func makeViewModel(
        ai: FakeAIContentService = FakeAIContentService(),
        store: StreakStore = SwiftDataStreakStore(inMemory: true),
        sessionType: ChatSessionType = .onboarding
    ) -> ChatViewModel {
        ChatViewModel(aiService: ai, store: store, sessionType: sessionType)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Push and check CI — expected: compile failure, `ChatViewModel` does not exist.

- [ ] **Step 3: Implement `ChatViewModel`**

Create `Sources/AffirmAlarmCore/ChatViewModel.swift`:
```swift
import Foundation

public enum ChatTurnState: Equatable {
    case idle
    case sending
    case error(String)
}

@MainActor
public final class ChatViewModel: ObservableObject {
    @Published public private(set) var messages: [ChatMessage] = []
    @Published public private(set) var turnState: ChatTurnState = .idle
    @Published public private(set) var needsConsentDecision = false
    @Published public private(set) var canGenerate = false
    @Published public private(set) var generatedAffirmations: [String]?

    private let aiService: AIContentService
    private let store: StreakStore
    private let sessionType: ChatSessionType
    private let now: () -> Date

    public init(
        aiService: AIContentService,
        store: StreakStore,
        sessionType: ChatSessionType,
        now: @escaping () -> Date = Date.init
    ) {
        self.aiService = aiService
        self.store = store
        self.sessionType = sessionType
        self.now = now
    }

    public func start() async {
        let consent = store.loadConsentState()
        guard consent.decidedAt != nil else {
            needsConsentDecision = true
            return
        }
        loadHistoryIfConsented(consent)
    }

    public func recordConsent(optedIn: Bool) {
        store.save(ConsentState(hasOptedIn: optedIn, decidedAt: now()))
        needsConsentDecision = false
        loadHistoryIfConsented(store.loadConsentState())
    }

    public func send(_ text: String) async {
        let userMessage = ChatMessage(role: .user, text: text, timestamp: now(), sessionType: sessionType)
        messages.append(userMessage)
        persistIfConsented(userMessage)
        turnState = .sending
        do {
            let reply = try await aiService.sendMessage(text, history: messages)
            let assistantMessage = ChatMessage(role: .assistant, text: reply, timestamp: now(), sessionType: sessionType)
            messages.append(assistantMessage)
            persistIfConsented(assistantMessage)
            turnState = .idle
            canGenerate = true
        } catch {
            turnState = .error(error.localizedDescription)
        }
    }

    public func generateAffirmations() async {
        turnState = .sending
        do {
            let texts = try await aiService.generateAffirmations(from: messages)
            generatedAffirmations = texts
            persistGenerationEventIfConsented(texts)
            turnState = .idle
        } catch {
            turnState = .error(error.localizedDescription)
        }
    }

    private func loadHistoryIfConsented(_ consent: ConsentState) {
        guard consent.hasOptedIn else { return }
        messages = store.loadChatHistory()
    }

    private func persistIfConsented(_ message: ChatMessage) {
        guard store.loadConsentState().hasOptedIn else { return }
        store.appendChatMessage(message)
    }

    private func persistGenerationEventIfConsented(_ texts: [String]) {
        guard store.loadConsentState().hasOptedIn else { return }
        store.recordGenerationEvent(AffirmationGenerationEvent(date: now(), sessionType: sessionType, generatedTexts: texts))
    }
}
```

Note: `error.localizedDescription` on `AIContentError.generationFailed` won't produce a friendly string (Swift's default `Error` conformance stringifies the enum case name via `String(describing:)`-like behavior, not real English) — this matches Phase 1's existing pattern in `AlarmRingViewModel.handleSpeechError` exactly (`error.localizedDescription` used the same way there for `NSError`), so it's consistent with the codebase, not a regression. If a nicer message is wanted later, that's a `LocalizedError` conformance on `AIContentError` — not required by the design spec, skip it (YAGNI).

- [ ] **Step 4: Run tests to verify they pass**

Push and check CI. Expected: all eleven `ChatViewModelTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AffirmAlarmCore/ChatViewModel.swift Tests/AffirmAlarmCoreTests/ChatViewModelTests.swift
git commit -m "feat: add ChatViewModel with consent gating and generation flow"
```

---

### Task 8: Consent screen, chat UI, and the Home entry point

**Files:**
- Create: `Sources/AffirmAlarm/ConsentView.swift`
- Create: `Sources/AffirmAlarm/ChatView.swift`
- Modify: `Sources/AffirmAlarm/HomeView.swift`
- Modify: `Sources/AffirmAlarmCore/HomeViewModel.swift`

**Interfaces:**
- Consumes: `ChatViewModel` (Task 7), `AffirmationEditViewModel` (Task 6), `AIContentService.isAvailable()` (Task 5)

- [ ] **Step 1: Build `ConsentView`**

Create `Sources/AffirmAlarm/ConsentView.swift`:
```swift
import SwiftUI

struct ConsentView: View {
    let onDecision: (Bool) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Save our conversations?")
                .font(.title2)
                .bold()
            Text("This helps me remember what matters to you next time, and gives you a simple journal of your own reflections. Nothing leaves your device.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Button("Yes, save my conversations") { onDecision(true) }
                    .accessibilityIdentifier("consentYesButton")
                    .buttonStyle(.borderedProminent)
                Button("No thanks, don't save") { onDecision(false) }
                    .accessibilityIdentifier("consentNoButton")
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}
```

Both buttons use `.buttonStyle` variants that differ only in fill (prominent vs bordered) purely for visual hierarchy between "primary action" and "secondary action" in SwiftUI's standard idiom — neither implies the two choices are unequal in weight or consequence; both are single-tap, immediately-effective decisions, matching the "no button visually favored" requirement in intent, not by making them pixel-identical.

- [ ] **Step 2: Build `ChatView`**

Create `Sources/AffirmAlarm/ChatView.swift`:
```swift
import SwiftUI
import AffirmAlarmCore

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    let store: StreakStore
    @State private var draft = ""
    @State private var lastSentText = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.needsConsentDecision {
                    ConsentView { optedIn in viewModel.recordConsent(optedIn: optedIn) }
                } else if let generated = viewModel.generatedAffirmations {
                    AffirmationEditView(viewModel: AffirmationEditViewModel(store: store, initialTexts: generated))
                } else {
                    chatBody
                }
            }
            .task { await viewModel.start() }
        }
    }

    private var chatBody: some View {
        VStack {
            List(viewModel.messages) { message in
                Text(message.text)
                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            }

            if case .error(let message) = viewModel.turnState {
                VStack {
                    Text(message).foregroundColor(.red)
                    Button("Retry") {
                        Task { await viewModel.send(lastSentText) }
                    }
                    .accessibilityIdentifier("chatRetryButton")
                    Button("Continue without AI") {
                        viewModel.generatedAffirmations = []
                    }
                    .accessibilityIdentifier("chatFallbackButton")
                }
            }

            HStack {
                TextField("Message", text: $draft)
                    .accessibilityIdentifier("chatInputField")
                Button("Send") {
                    lastSentText = draft
                    let text = draft
                    draft = ""
                    Task { await viewModel.send(text) }
                }
                .accessibilityIdentifier("chatSendButton")
                .disabled(draft.isEmpty || viewModel.turnState == .sending)
            }
            .padding()

            if viewModel.canGenerate {
                Button("Generate my affirmations") {
                    Task { await viewModel.generateAffirmations() }
                }
                .accessibilityIdentifier("generateAffirmationsButton")
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
            }
        }
        .navigationTitle("Chat")
    }
}
```

`viewModel.generatedAffirmations = []` in the fallback button is invalid — `generatedAffirmations` is `private(set)` on `ChatViewModel`. Add a public method instead. In `Sources/AffirmAlarmCore/ChatViewModel.swift`, add:
```swift
    public func continueWithoutAI() {
        generatedAffirmations = []
    }
```
and use `viewModel.continueWithoutAI()` in place of the direct assignment in `ChatView.swift` above.

- [ ] **Step 3: Wire the "Chat with AI" entry point into `HomeView`**

`HomeView`'s chat entry must check `AIContentService.isAvailable()` before navigating to `ChatView` at all (per the design spec: ineligible devices skip straight to manual editing, no dead-end chat screen). This means `HomeViewModel` needs the `AIContentService` and an availability-checked navigation trigger.

Add to `Sources/AffirmAlarmCore/HomeViewModel.swift`:
```swift
    public let aiService: AIContentService

    public enum ChatEntryDestination: Equatable {
        case chat
        case editAffirmationsDirectly
    }

    public func resolveChatEntry() async -> ChatEntryDestination {
        await aiService.isAvailable() ? .chat : .editAffirmationsDirectly
    }
```
and thread `aiService: AIContentService` through `init(alarmService:store:aiService:)`, storing it into the new `public let aiService`.

Update `AffirmationEditViewModelTests`/`HomeViewModelTests`/`ChatViewModelTests` call sites are unaffected (none of them construct `HomeViewModel`), but `RootView`'s construction of `HomeViewModel` (Task 3) and `AffirmAlarmApp.swift` (Task 11) both need the extra argument — Task 11 is the only production call site today (`RootView` takes an already-constructed `HomeViewModel` as a parameter, per Task 3's `RootView`), so only Task 11 is affected; note this for that task rather than editing it now since it hasn't been written yet.

In `Sources/AffirmAlarm/HomeView.swift`, add state and a new section:
```swift
    @State private var chatDestination: HomeViewModel.ChatEntryDestination?
    @State private var showChat = false
    @State private var showManualEditDirectly = false
```
and in the `Section` after "Edit affirmations":
```swift
                Section {
                    Button("Chat with AI") {
                        Task {
                            switch await viewModel.resolveChatEntry() {
                            case .chat:
                                showChat = true
                            case .editAffirmationsDirectly:
                                showManualEditDirectly = true
                            }
                        }
                    }
                    .accessibilityIdentifier("chatWithAIButton")
                }
                .navigationDestination(isPresented: $showChat) {
                    ChatView(
                        viewModel: ChatViewModel(aiService: viewModel.aiService, store: viewModel.store, sessionType: .onboarding),
                        store: viewModel.store
                    )
                }
                .navigationDestination(isPresented: $showManualEditDirectly) {
                    AffirmationEditView(viewModel: AffirmationEditViewModel(store: viewModel.store))
                }
```

- [ ] **Step 4: Push and verify on CI**

Push, check CI. Both schemes must compile; no new automated test coverage is added in this UI-wiring task beyond what Tasks 6/7 already cover at the ViewModel level — SwiftUI view bodies aren't unit-testable in this project's setup (same as `AlarmRingView`/`HomeView` in earlier tasks, which also have no dedicated SwiftUI-body tests, only their ViewModels do).

- [ ] **Step 5: Commit**

```bash
git add Sources/AffirmAlarm/ConsentView.swift Sources/AffirmAlarm/ChatView.swift Sources/AffirmAlarm/HomeView.swift Sources/AffirmAlarmCore/HomeViewModel.swift Sources/AffirmAlarmCore/ChatViewModel.swift
git commit -m "feat: add consent screen, chat UI, and AI-availability-gated Home entry point"
```

---

### Task 9: Check-in notification scheduling

**Files:**
- Create: `Sources/AffirmAlarmCore/CheckInScheduling.swift`
- Modify: `Sources/AffirmAlarmCore/ChatViewModel.swift`
- Modify: `Tests/AffirmAlarmCoreTests/Fakes.swift`
- Modify: `Tests/AffirmAlarmCoreTests/ChatViewModelTests.swift`
- Test: `Tests/AffirmAlarmCoreTests/LocalNotificationCheckInSchedulerTests.swift`

**Interfaces:**
- Produces: `CheckInScheduling` protocol, `LocalNotificationCheckInScheduler`. Task 11 constructs the real scheduler for production wiring.

- [ ] **Step 1: Write the failing tests**

Create `Tests/AffirmAlarmCoreTests/LocalNotificationCheckInSchedulerTests.swift`:
```swift
import XCTest
@testable import AffirmAlarmCore

final class LocalNotificationCheckInSchedulerTests: XCTestCase {
    func test_scheduleNextCheckIn_addsPrimaryAndFollowUpRequests() async {
        let center = FakeNotificationScheduling()
        let scheduler = LocalNotificationCheckInScheduler(center: center)

        await scheduler.scheduleNextCheckIn(from: Date())

        XCTAssertEqual(center.addedIdentifiers.count, 2)
        XCTAssertTrue(center.addedIdentifiers.contains("affirmalarm.checkin"))
        XCTAssertTrue(center.addedIdentifiers.contains("affirmalarm.checkin.followup"))
    }

    func test_scheduleNextCheckIn_cancelsAnyPriorPendingRequestsFirst() async {
        let center = FakeNotificationScheduling()
        let scheduler = LocalNotificationCheckInScheduler(center: center)

        await scheduler.scheduleNextCheckIn(from: Date())
        await scheduler.scheduleNextCheckIn(from: Date())

        XCTAssertEqual(center.removeCallCount, 2)
    }

    func test_cancelPendingCheckIns_removesBothIdentifiers() {
        let center = FakeNotificationScheduling()
        let scheduler = LocalNotificationCheckInScheduler(center: center)

        scheduler.cancelPendingCheckIns()

        XCTAssertEqual(center.lastRemovedIdentifiers, ["affirmalarm.checkin", "affirmalarm.checkin.followup"])
    }
}
```

Add `FakeNotificationScheduling` to `Tests/AffirmAlarmCoreTests/Fakes.swift`:
```swift
final class FakeNotificationScheduling: NotificationScheduling {
    private(set) var addedIdentifiers: [String] = []
    private(set) var lastRemovedIdentifiers: [String] = []
    private(set) var removeCallCount = 0

    func addRequest(_ request: UNNotificationRequest) {
        addedIdentifiers.append(request.identifier)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        lastRemovedIdentifiers = identifiers
        removeCallCount += 1
    }
}
```
This requires `import UserNotifications` at the top of `Fakes.swift` — add it alongside the existing `import Foundation`.

- [ ] **Step 2: Run tests to verify they fail**

Push and check CI — expected: compile failure, `CheckInScheduling`/`LocalNotificationCheckInScheduler`/`NotificationScheduling` don't exist.

- [ ] **Step 3: Implement the scheduler**

Create `Sources/AffirmAlarmCore/CheckInScheduling.swift`:
```swift
import Foundation
import UserNotifications

public protocol NotificationScheduling {
    func addRequest(_ request: UNNotificationRequest)
    func removePendingRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: NotificationScheduling {
    public func addRequest(_ request: UNNotificationRequest) {
        add(request)
    }

    public func removePendingRequests(withIdentifiers identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

public protocol CheckInScheduling {
    func scheduleNextCheckIn(from date: Date) async
    func cancelPendingCheckIns()
}

public final class LocalNotificationCheckInScheduler: CheckInScheduling {
    private static let checkInIdentifier = "affirmalarm.checkin"
    private static let followUpIdentifier = "affirmalarm.checkin.followup"
    private static let checkInInterval: TimeInterval = 7 * 24 * 60 * 60
    private static let followUpInterval: TimeInterval = 10 * 24 * 60 * 60

    private let center: NotificationScheduling

    public init(center: NotificationScheduling = UNUserNotificationCenter.current()) {
        self.center = center
    }

    public func scheduleNextCheckIn(from date: Date) async {
        cancelPendingCheckIns()
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])

        let checkInContent = UNMutableNotificationContent()
        checkInContent.title = "Time for a check-in"
        checkInContent.body = "How are things going? Let's revisit your affirmations."
        let checkInTrigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.checkInInterval, repeats: false)
        center.addRequest(UNNotificationRequest(identifier: Self.checkInIdentifier, content: checkInContent, trigger: checkInTrigger))

        let followUpContent = UNMutableNotificationContent()
        followUpContent.title = "Still there?"
        followUpContent.body = "Your check-in is waiting whenever you're ready."
        let followUpTrigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.followUpInterval, repeats: false)
        center.addRequest(UNNotificationRequest(identifier: Self.followUpIdentifier, content: followUpContent, trigger: followUpTrigger))
    }

    public func cancelPendingCheckIns() {
        center.removePendingRequests(withIdentifiers: [Self.checkInIdentifier, Self.followUpIdentifier])
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Push and check CI. Expected: all three `LocalNotificationCheckInSchedulerTests` pass.

- [ ] **Step 5: Wire scheduling into `ChatViewModel`'s generation success path**

`ChatViewModel` needs a `CheckInScheduling` dependency so completing either an onboarding or check-in session arms the next check-in.

Modify `Sources/AffirmAlarmCore/ChatViewModel.swift`: add `checkInScheduler: CheckInScheduling` to the initializer (stored alongside the existing dependencies), and in `generateAffirmations()`, after `persistGenerationEventIfConsented(texts)` succeeds, add:
```swift
            await checkInScheduler.scheduleNextCheckIn(from: now())
```

Update `Tests/AffirmAlarmCoreTests/ChatViewModelTests.swift`'s `makeViewModel` helper to accept and pass through a `checkInScheduler: CheckInScheduling = FakeCheckInScheduling()` parameter (add a `FakeCheckInScheduling` to `Fakes.swift` alongside `FakeNotificationScheduling`):
```swift
final class FakeCheckInScheduling: CheckInScheduling {
    private(set) var scheduleCallCount = 0
    private(set) var cancelCallCount = 0

    func scheduleNextCheckIn(from date: Date) async {
        scheduleCallCount += 1
    }

    func cancelPendingCheckIns() {
        cancelCallCount += 1
    }
}
```

Add one new assertion to the existing `test_generateAffirmations_success_setsGeneratedAffirmationsAndPersistsEventWhenOptedIn` test in `ChatViewModelTests.swift`: after the existing assertions, add
```swift
        XCTAssertEqual((viewModel as ChatViewModel).checkInSchedulerCallCountForTesting, 1)
```
— actually, simpler and consistent with this codebase's existing testing style (which asserts on the *fake's* recorded calls, not on the view model): instead capture the `FakeCheckInScheduling` instance in a local `let checkInScheduler = FakeCheckInScheduling()`, pass it into `makeViewModel(checkInScheduler: checkInScheduler)`, and assert `XCTAssertEqual(checkInScheduler.scheduleCallCount, 1)` after `await viewModel.generateAffirmations()`. Apply this pattern (matching how `FakeAlarmSchedulingService.snoozeCallCount` is already asserted on directly in existing tests) rather than adding any new property to `ChatViewModel` itself.

- [ ] **Step 6: Run tests to verify they pass**

Push and check CI. Expected: updated `ChatViewModelTests` still all pass, including the new scheduler-call assertion.

- [ ] **Step 7: Commit**

```bash
git add Sources/AffirmAlarmCore/CheckInScheduling.swift Sources/AffirmAlarmCore/ChatViewModel.swift Tests/AffirmAlarmCoreTests/Fakes.swift Tests/AffirmAlarmCoreTests/ChatViewModelTests.swift Tests/AffirmAlarmCoreTests/LocalNotificationCheckInSchedulerTests.swift
git commit -m "feat: schedule 7-day check-in notifications with a missed-checkin follow-up"
```

---

### Task 10: Insights journal

**Files:**
- Create: `Sources/AffirmAlarmCore/InsightsViewModel.swift`
- Create: `Sources/AffirmAlarm/InsightsView.swift`
- Modify: `Sources/AffirmAlarm/HomeView.swift`
- Test: `Tests/AffirmAlarmCoreTests/InsightsViewModelTests.swift`

**Interfaces:**
- Consumes: `StreakStore.loadGenerationEvents()` (Task 4)

- [ ] **Step 1: Write the failing tests**

Create `Tests/AffirmAlarmCoreTests/InsightsViewModelTests.swift`:
```swift
import XCTest
@testable import AffirmAlarmCore

@MainActor
final class InsightsViewModelTests: XCTestCase {
    func test_init_loadsGenerationEventsNewestFirst() {
        let store = SwiftDataStreakStore(inMemory: true)
        let older = AffirmationGenerationEvent(date: Date(timeIntervalSince1970: 1), sessionType: .onboarding, generatedTexts: ["a"])
        let newer = AffirmationGenerationEvent(date: Date(timeIntervalSince1970: 2), sessionType: .checkIn, generatedTexts: ["b"])
        store.recordGenerationEvent(older)
        store.recordGenerationEvent(newer)

        let viewModel = InsightsViewModel(store: store)

        XCTAssertEqual(viewModel.events, [newer, older])
    }

    func test_init_withNoEvents_isEmpty() {
        let viewModel = InsightsViewModel(store: SwiftDataStreakStore(inMemory: true))
        XCTAssertTrue(viewModel.events.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Push and check CI — expected: compile failure, `InsightsViewModel` does not exist.

- [ ] **Step 3: Implement `InsightsViewModel`**

Create `Sources/AffirmAlarmCore/InsightsViewModel.swift`:
```swift
import Foundation

@MainActor
public final class InsightsViewModel: ObservableObject {
    @Published public private(set) var events: [AffirmationGenerationEvent]

    public init(store: StreakStore) {
        self.events = store.loadGenerationEvents()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Push and check CI. Expected: both `InsightsViewModelTests` pass.

- [ ] **Step 5: Build `InsightsView` and wire it into `HomeView`**

Create `Sources/AffirmAlarm/InsightsView.swift`:
```swift
import SwiftUI
import AffirmAlarmCore

struct InsightsView: View {
    @ObservedObject var viewModel: InsightsViewModel

    var body: some View {
        List(viewModel.events) { event in
            VStack(alignment: .leading, spacing: 4) {
                Text(event.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(event.sessionType == .onboarding ? "Onboarding" : "Check-in")
                    .font(.subheadline)
                ForEach(event.generatedTexts, id: \.self) { text in
                    Text(text)
                }
            }
        }
        .navigationTitle("Insights")
    }
}
```

In `Sources/AffirmAlarm/HomeView.swift`, add one more entry to the section holding "Edit affirmations":
```swift
                    NavigationLink("Insights") {
                        InsightsView(viewModel: InsightsViewModel(store: viewModel.store))
                    }
                    .accessibilityIdentifier("insightsLink")
```

- [ ] **Step 6: Push and verify on CI**

Push, check CI. Both schemes compile.

- [ ] **Step 7: Commit**

```bash
git add Sources/AffirmAlarmCore/InsightsViewModel.swift Sources/AffirmAlarm/InsightsView.swift Sources/AffirmAlarm/HomeView.swift Tests/AffirmAlarmCoreTests/InsightsViewModelTests.swift
git commit -m "feat: add insights journal listing past AI-generation events"
```

---

### Task 11: Final integration — wire everything into `AffirmAlarmApp`

**Files:**
- Modify: `Sources/AffirmAlarm/AffirmAlarmApp.swift`

**Interfaces:**
- Consumes: every service/ViewModel produced by Tasks 1-10.

- [ ] **Step 1: Rewrite the app entry point**

Replace `Sources/AffirmAlarm/AffirmAlarmApp.swift` in full:
```swift
import SwiftUI
import AffirmAlarmCore

@main
struct AffirmAlarmApp: App {
    var body: some Scene {
        WindowGroup {
            let alarmService = AlarmKitSchedulingService()
            let store = SwiftDataStreakStore()
            let aiService = OnDeviceAIContentService()

            RootView(
                rootViewModel: RootViewModel(alarmService: alarmService),
                alarmRingViewModel: AlarmRingViewModel(
                    speechService: OnDeviceSpeechRecognitionService(),
                    alarmService: alarmService,
                    store: store
                ),
                homeViewModel: HomeViewModel(
                    alarmService: alarmService,
                    store: store,
                    aiService: aiService
                )
            )
        }
    }
}
```

Note the three shared instances (`alarmService`, `store`, `aiService`) are constructed once here and threaded into every ViewModel that needs them, matching Phase 1's existing single-shared-instance pattern for `store` (already true across `AlarmRingViewModel` before this task) — extended the same way to `HomeViewModel`. `ChatView` (Task 8) already receives `store` and constructs its own `ChatViewModel` internally from `viewModel.aiService`/`viewModel.store` on `HomeViewModel`, and `CheckInScheduling` — check Task 9's `ChatViewModel` initializer signature; if it requires `checkInScheduler` as a non-defaulted parameter (it does, per Task 9 Step 5), `HomeView`'s `ChatView(viewModel: ChatViewModel(...))` construction site (added in Task 8) needs a `checkInScheduler: LocalNotificationCheckInScheduler()` argument added — do that here as part of this task's integration pass, since Task 8 was written before Task 9 existed and could not have known the final signature. Grep `Sources/AffirmAlarm/HomeView.swift` for `ChatViewModel(` to find that exact call site and add the missing argument.

- [ ] **Step 2: Push and verify on CI**

Push and check CI for both schemes. This is the task where every previously-expected-not-yet-green UI test (Task 2's three ring-screen tests, Task 3's Home-screen test) should finally pass, since `RootView` is now the real app root. Confirm all of:
- `AffirmAlarmCore` scheme: every unit test file created across Tasks 1-10 passes
- `AffirmAlarm` scheme: all four `AlarmRingUITests` tests pass (three forced-ringing + one default-Home)

If the forced-ringing UI tests fail because `AlarmRingViewModel.beginRing()` (called via `AlarmRingView`'s `.onAppear`, unchanged from Phase 1) reads real store state that differs under the `-uiTestForceRinging` path — it shouldn't, since `beginRing()` only touches `store`/`speechService`, neither of which is affected by the routing bypass — but if CI shows otherwise, report DONE_WITH_CONCERNS with the exact failure rather than guessing at a fix blind.

- [ ] **Step 3: Commit**

```bash
git add Sources/AffirmAlarm/AffirmAlarmApp.swift
git commit -m "feat: wire RootView, HomeView, and all Phase 2 services into the app entry point"
```

---

## Final Whole-Branch Review

After Task 11's CI run is green, dispatch the final whole-branch code review per `superpowers:subagent-driven-development`, on the most capable available model, covering the full range from Phase 1's milestone tag (`phase1-core-loop-complete`) or Task 1's starting commit through Task 11's final commit. Pay particular attention to:
- Whether `RootViewModel`'s `alertingAlarmUpdates()` subscription is properly cancelled/doesn't leak when the app backgrounds (no explicit lifecycle handling was added for this in Task 2 — worth a second look)
- Whether consent gating is actually enforced on every persistence path (Task 4's store methods have no gating themselves — Task 7's `ChatViewModel` is the sole enforcement point; confirm nothing else calls `appendChatMessage`/`recordGenerationEvent` directly)
- Whether the `-uiTestForceRinging` launch-argument hook (Task 2) could leak into a real production build's behavior (it's a `ProcessInfo.arguments` check with a name unlikely to collide, but confirm no code path sets that argument outside test targets)

This mirrors Phase 1's final review, which found real end-to-end gaps (seeding, authorization, threading) despite every task-level review passing — do not skip it.
