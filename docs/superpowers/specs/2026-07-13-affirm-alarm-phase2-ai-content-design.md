# AffirmAlarm — Phase 2 Design: AI-Assisted Content, Alarm-Setting & Insights

## Summary

Phase 1 shipped the core "speak to dismiss" alarm loop with no way to actually
set an alarm and a hardcoded default affirmation set. Phase 2 adds: a real
Home screen with alarm-setting, an on-device AI chat for onboarding and
periodic check-ins that writes affirmations for the user, manual affirmation
editing, consent-gated conversation history, and a lightweight insights
journal. This also corrects two AlarmKit API issues discovered in Phase 1
against real Apple documentation (not available during Phase 1's original
implementation).

Monetization (RevenueCat/Superwall) remains out of scope — that's Phase 3.

## Background: AlarmKit Corrections From Phase 1

Phase 1's `AlarmSchedulingService.swift` was written against training-data
knowledge of AlarmKit, which is newer than the assistant's training cutoff.
Real Apple documentation (supplied by the user directly, since AlarmKit's
docs are JS-rendered and unfetchable by available tools) surfaced two
corrections, applied as part of Task 1 below since that task already
rewrites this file for real scheduling:

1. `AlarmPresentation.Alert(title:stopButton:secondaryButton:secondaryButtonBehavior:)`
   is deprecated (iOS 26.0–26.1 only). The current initializer is
   `init(title:secondaryButton:secondaryButtonBehavior:)` — no `stopButton`
   parameter, because the system now always provides one automatically.
   Deployment target moves to iOS 26.1.
2. `AlarmManager.AlarmConfiguration` supports a `stopIntent:` parameter
   Phase 1 omitted (compiled fine via its default `nil`). Wiring it lets the
   app sync its own locally-generated ringtone (`GeneratedTonePlayer`) if the
   system Stop button is tapped while the app happens to be foregrounded.

### Accepted Trade-off: The System Stop Button

AlarmKit's real, system-rendered alert always includes an automatic,
app-uninterceptable "Stop" button — confirmed by Apple's docs: *"The system
provides a stop button automatically."* There is no documented AlarmKit
mechanism to prevent, gate, or hide it. This means a real AffirmAlarm alarm
firing on a locked/backgrounded device always has a one-tap way to bypass
the "speak your affirmation" mechanic entirely.

This is accepted as an inherent platform constraint of building on AlarmKit,
in the same spirit as the local-data-tampering trade-off already accepted in
the v1 spec for the Close-button cap and streak state. AffirmAlarm's actual
mechanism of behavior change is making the correct path (tapping "Open" into
the app's own ring screen) the natural, prominent one — not technical
enforcement against a determined user working around their own alarm.
No further engineering effort should be spent trying to suppress or
intercept the system Stop button; it is not solvable within AlarmKit.

## Scope

**In scope:**
- Real Home screen + alarm-setting UI (Phase 1 shipped with none)
- AlarmKit corrections above
- On-device AI chat (Apple Foundation Models, `FoundationModels.LanguageModelSession`) for onboarding and periodic check-ins
- Manual affirmation editing (add/edit/delete/reorder)
- Consent-gated persistence of AI chat history
- Lightweight insights journal (chronological list, not a dashboard)

**Out of scope (unchanged from v1, still deferred to Phase 3+):**
- Monetization (RevenueCat/Superwall)
- Cloud LLM providers (OpenAI/Anthropic) — architecture allows swapping later, not built now
- Real OS-level snooze via `Alarm.CountdownDuration(postAlert:)` — requires a
  Widget Extension target; current local-silence-only snooze (Phase 1)
  is kept as-is. Revisit if it becomes a real user complaint.
- Analytics dashboard / charts / trends — insights stays a plain list
- Android, cross-device sync, custom snooze intervals (unchanged from v1)

## Architecture

### 1. App Shell, Navigation & Alarm-Setting

**Routing.** On launch, and while foregrounded via
`AlarmManager.shared.alarmUpdates`, check `AlarmManager.shared.alarms` for
any entry with `state == .alerting`. If found, route directly to the
existing `AlarmRingView`. Otherwise, route to the new `HomeView`.

**`HomeView`** (new) is the app's real root screen:
- Shows the currently scheduled alarm time, or "No alarm set"
- A time picker to set/edit the alarm time, wired to
  `AlarmSchedulingService.scheduleAlarm(at:)`
- Current streak/day (existing `StreakStore` data, unchanged)
- Entry points: "Chat with AI" (onboarding or check-in, see Section 3),
  "Edit affirmations" (Section 4), "Insights" (Section 5)

**Scheduling becomes properly async.** Phase 1's `scheduleAlarm(at:)` fires
into a detached `Task {}` and swallows errors because there was no
synchronous UI caller to report them to. With a real time-picker button tap,
`AlarmSchedulingService`'s protocol method becomes `async throws`, and
`HomeView`'s save action awaits it directly, surfacing scheduling failures
(e.g. authorization denied) as an inline error.

**AlarmKit corrections** (from Background section above) land here since
this file is already being substantially rewritten for real scheduling:
migrate to the current `AlarmPresentation.Alert` initializer, add
`secondaryButton` + `secondaryButtonBehavior: .custom` (the "Open" action
that launches the app from a backgrounded alarm's system alert into
`AlarmRingView` — necessary regardless of the Stop button, since the fired
alert itself is system-rendered, not app UI), and wire `stopIntent`.

### 2. AI Content Service Architecture

```swift
public protocol AIContentService: AnyObject {
    func sendMessage(_ message: String, history: [ChatMessage]) async throws -> String
    func generateAffirmations(from history: [ChatMessage]) async throws -> [String]
}

public enum AIContentError: Error {
    case unavailable       // Apple Intelligence disabled, or ineligible device/region
    case generationFailed
}
```

`OnDeviceAIContentService` (the sole concrete implementation for Phase 2)
wraps `FoundationModels.LanguageModelSession`. `generateAffirmations` uses
`@Generable` guided generation (structured output) rather than parsing the
model's freeform prose reply — the reliable way to get a clean `[String]`
back from an on-device model.

Before any chat UI appears, `HomeView`'s "Chat with AI" entry point checks
`SystemLanguageModel.default.availability`. If unavailable (ineligible
device, region, or user has Apple Intelligence disabled), the app skips
straight to manual affirmation editing (Section 4) with a short explanatory
message — no dead-end chat screen is ever shown.

The protocol boundary exists specifically so a future cloud provider
(OpenAI/Anthropic) can be swapped in later without touching call sites —
not built now, since on-device avoids all API-key storage and per-message
cost concerns for a Phase 2 that's otherwise fully local per the v1
architecture's "Approach C" (see v1 spec).

### 3. Chat Flows

One shared `ChatViewModel`, parameterized by a `ChatSessionType` enum
(`.onboarding` / `.checkIn`), backs both flows to avoid duplicating chat
UI/logic.

**Onboarding**: triggered from `HomeView` on first use (no affirmations
customized yet) or any time via "Chat with AI". Freeform back-and-forth via
`sendMessage`. A "Generate my affirmations" button enables after the first
exchange; tapping it calls `generateAffirmations(from:)` with the full
transcript and routes into the review/edit screen (Section 4), pre-filled
with the AI's output — the user edits before it's saved.

**Check-in**: triggered by tapping "Check in" on `HomeView`, or by a local
notification (`UNUserNotificationCenter`) scheduled 7 days after the last
completed check-in. Completing a check-in reschedules the next one 7 days
out. If a check-in notification is missed (dismissed/ignored), a follow-up
notification re-fires a few days later rather than repeating daily. Same
freeform-chat → "Generate" flow as onboarding; if the user has consented to
history persistence (Section 5), prior transcripts are included as context
so the AI has real continuity across check-ins rather than starting cold
each time.

### 4. Manual Affirmation Editing

One screen, `AffirmationEditView`: lists current affirmations (from
`StreakStore.loadAffirmations()`) with add/edit/delete/reorder, saved via
the existing `StreakStore.save()` (already full-replace semantics — no
schema change needed here). This same screen doubles as the post-generation
review step for both chat flows: AI-generated text pre-fills the list, and
the user's edits (or lack thereof) are what actually gets saved — the AI
never writes directly to the store.

### 5. Consent, Persistence & Insights

**Consent gate.** The first time any chat session would start (onboarding
or check-in), a consent screen appears before any message is sent:

> "Save our conversations? This helps me remember what matters to you next
> time, and gives you a simple journal of your own reflections. Nothing
> leaves your device."

Two equal-weight buttons — "Yes, save my conversations" / "No thanks, don't
save" — no pre-checked box, no button visually favored over the other.
Declining still lets that session's chat function normally in-memory for
the duration of that session; nothing is written to disk, no cross-session
AI continuity, no insights entry is created. The choice is revisited any
time later from a Settings/Privacy screen (new, minimal — a single toggle
mirroring this same copy).

**Data model additions** (SwiftData, alongside the existing `Affirmation`
model):

```swift
enum ChatRole: String, Codable { case user, assistant }
enum ChatSessionType: String, Codable { case onboarding, checkIn }

@Model
final class ChatMessage {
    var role: ChatRole
    var text: String
    var timestamp: Date
    var sessionType: ChatSessionType
}

@Model
final class AffirmationGenerationEvent {
    var date: Date
    var sessionType: ChatSessionType
    var generatedTexts: [String]
}

@Model
final class ConsentRecord {
    var hasOptedIn: Bool
    var decidedAt: Date
}
```

`ChatMessage` rows persist only when `ConsentRecord.hasOptedIn == true`;
they feed AI continuity context in Section 3's check-in flow.
`AffirmationGenerationEvent` — one row per "Generate my affirmations" tap —
is the entire Insights journal: a plain chronological list (date,
which kind of session produced it, and the resulting affirmation texts),
per the earlier decision to keep insights lightweight rather than build
analytics. `ConsentRecord` is a singleton row, created on first decision.

**AI failure UX.** Any `AIContentError` (or thrown error from
`sendMessage`/`generateAffirmations`) surfaces as an inline error banner
with a "Retry" action. If retry also fails, or the model was `.unavailable`
from the pre-flight check, a "Continue without AI" button routes directly to
`AffirmationEditView` (Section 4) with an empty/current list — the user is
never stuck on a broken chat screen.

## Testing Strategy

Follows Phase 1's established pattern: `AffirmAlarmCore` protocols
(`AIContentService`, and the now-`async throws` `AlarmSchedulingService`)
get fake implementations in `Tests/AffirmAlarmCoreTests/Fakes.swift`
(extending the existing `FakeSpeechRecognitionService` pattern) so
`ChatViewModel` and `HomeView`'s scheduling logic are unit-testable without
touching real `FoundationModels` or `AlarmKit` APIs — neither of which can
run in CI's `macos-15` runner outside of compiling against the real
frameworks (same constraint Phase 1 hit with `AlarmKitSchedulingServiceTests`,
which tests only the local-ringtone side-effects, not real AlarmKit
scheduling).

New unit test coverage needed:
- `ChatViewModelTests`: message send/receive via fake, "Generate" enablement
  after first exchange, generation success routes to edit review, generation
  failure surfaces retry/fallback, consent gate blocks/allows persistence
  correctly via a fake/in-memory store
- `StreakStoreTests` additions: `ChatMessage`/`AffirmationGenerationEvent`
  persistence respects `ConsentRecord.hasOptedIn`
- `AlarmKitSchedulingServiceTests` additions: async `scheduleAlarm` error
  path (unauthorized) surfaces to caller rather than being swallowed

As with Phase 1, real on-device model behavior and real AlarmKit scheduling
can only be verified by running the app on-device or in a simulator with
Apple Intelligence enabled — outside CI's reach. No new test attempts to
mock `LanguageModelSession` or `AlarmManager` directly.

## Edge Cases

- Declining consent mid-relationship (after previously opting in): existing
  `ChatMessage`/`AffirmationGenerationEvent` rows are not deleted
  automatically — turning persistence off stops new writes, it isn't a
  right-to-erasure control. (Out of scope: a "delete my history" action —
  candidate for Phase 3 settings work if requested.)
- Check-in notification fires while a chat session is already open: the
  existing session continues; the notification is dismissed without
  starting a second session.
- AI generates fewer affirmations than the current intensity tier requires
  (e.g., 1 when day-14+ needs 2): `AffirmationEditView` still opens with
  whatever was generated; the user must add at least enough to satisfy the
  tier before saving is allowed, using the same validation `IntensityEngine`
  already implies (not currently enforced anywhere — new validation, folded
  into `AffirmationEditView`'s save action).
- Apple Intelligence becomes unavailable mid-session (e.g., user disables it
  in Settings while the app is backgrounded): next `sendMessage`/
  `generateAffirmations` call throws `.unavailable`, handled by the same
  retry/fallback UX as any other AI failure.

## Out of Scope for Phase 2 (explicit)

- Real OS-level snooze (requires Widget Extension — deferred)
- Cloud LLM providers
- Deleting persisted chat history / insights entries
- Settings screen beyond the single consent toggle
- Monetization (Phase 3)
