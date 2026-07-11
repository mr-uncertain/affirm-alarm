# AffirmAlarm — v1 Design

## Summary
An iOS alarm app where the alarm will not fully stop until the user speaks their
daily affirmation(s) aloud, verified by on-device speech recognition. Inspired by
Erly (push-up alarm) but generalized to a spoken-affirmation unlock, with an
automatic streak-based intensity ramp and AI-assisted affirmation content.

## Core Alarm Flow
1. Alarm rings at the set time via Apple's Alarm Kit API (iOS 26+).
2. Screen shows two options: **Snooze** and a **press-and-hold-to-speak** button.
3. Pressing and holding:
   - Alarm volume lowers to slightly audible (not fully silenced) so the user can
     speak while retaining urgency.
   - The button glows while held.
   - The user speaks the current affirmation; on-device Speech framework verifies it.
   - Releasing before verification succeeds resets that attempt — press and hold
     again to retry the same affirmation.
   - On success, advances to the next affirmation if today's intensity requires
     more than one.
   - After the last affirmation is verified, the alarm fully stops.
4. Tapping **Snooze** delays the alarm by 9 minutes (iOS standard default); it
   returns to this same screen.
5. **Close** button: bypasses affirmation entirely, dismissing the alarm. Capped at
   3 uses per calendar month; disabled once the monthly allowance is used.

## Intensity Progression
- Starts small and automatically increases as the user's streak grows, ramping
  over time. Default schedule (tunable post-launch):
  - Days 1–6: 1 affirmation, said once.
  - Days 7–13: 1 affirmation, said twice (repeat).
  - Days 14–20: 2 affirmations, said once each.
  - Day 21+: 2 affirmations, said twice each.
  - (Pattern continues, alternating between adding affirmations and adding
    repeats, every 7 days.)
- A broken streak — a missed day, or using the Close button — resets intensity
  fully back to the Day-1 level.

## Affirmation Content
- Onboarding: an AI chat asks whether the user wants to write their own
  affirmations or have the AI generate them based on the conversation.
- Every 7–8 days, an AI check-in asks how things are going and can refresh or
  regenerate the affirmation set based on the user's answers.
- Users may edit or add their own affirmations at any time, regardless of source.

## Architecture (Approach C — fully on-device, no backend)
- **Platform:** Native iOS, Swift/SwiftUI, targeting iOS 26+.
- **Alarm:** Apple's Alarm Kit API for a reliable native alarm that survives
  background/locked state (same mechanism Erly uses).
- **Speech verification:** Apple's on-device Speech framework — free, offline,
  no network round-trip.
- **AI content generation:** The app calls an LLM API (OpenAI or Claude) directly
  for the onboarding chat and 7–8 day check-ins, using an API key bundled in the
  app.
- **Storage:** Local only, via Core Data / SwiftData — affirmations, streak state,
  current intensity level, and the Close-button usage counter (resets monthly).
- **Notifications:** Local notifications prompt the 7–8 day AI check-in.
- **Subscriptions:** RevenueCat for subscription management, Superwall for the
  paywall UI, matching Erly's stack.

### Accepted Trade-offs
The user explicitly chose this fully on-device approach over a backend-mediated
one, accepting:
- The LLM API key ships inside the app binary and is technically extractable by a
  determined attacker (possible cost-abuse risk).
- No server-side enforcement of the Close-button monthly cap or streak/intensity
  state — a user could tamper with local app data to cheat these mechanics.
- No cross-device sync or cloud backup — reinstalling the app loses all streak and
  affirmation history.

## Monetization
Free trial, converting to $9/month or ~$30/year, via RevenueCat + Superwall —
matching Erly's validated price point.

## Edge Cases
- Releasing mid-affirmation before verification: resets that attempt only; user
  retries the same affirmation.
- Streak break (missed day or Close used): intensity resets fully to the starting
  level.
- Close button: capped at 3 uses per calendar month; resets at the start of each
  month.
- Failed speech match (e.g., background noise): unlimited retries, no attempt cap.

## Out of Scope for v1
- Android support.
- Cross-device sync or cloud backup.
- Custom snooze intervals.
- Affirmation categories/library beyond AI-chat-generated or user-authored.
- Analytics dashboard.
- Social or sharing features.
