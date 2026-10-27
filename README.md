<p align="center">
  <img src="assets/logo.png" alt="CareHold" width="420">
</p>

<p align="center">
  An iOS app that connects patients with their doctors and care providers.<br>
  Appointments, medications, treatment plans and messages in one calm, easy place.
</p>

---

## Why

After a visit, patients often leave with a list of instructions: medicines and when to take them, exercises, the date of the next appointment. That list ends up on a piece of paper or inside a web portal that is hard to use, especially for people who are not comfortable with technology.

CareHold puts the plan in their pocket and answers one question at a time. On **Today** it answers "what do I do now?". **Visits** shows when the next appointment is and what the provider said last time. **Messages** connects them with their care team.

## Features

### For patients

- **Today:** the day's medicines, exercises and instructions, grouped into morning, afternoon and evening. A large check marks each one as done.
- **Ask a question:** type or dictate questions like "What do I take today?" or "When is my next appointment?". Answers come only from the patient's own care plan.
- **Visits:** upcoming appointments, requests for a new one, and past visits with the provider's notes and what was prescribed.
- **Messages:** a conversation with the care provider, plus reminders the provider sends that stay on Today until acknowledged.
- **Read aloud:** on every instruction and note.
- **Reminders:** local notifications when it's time. The lock screen never shows the name of a medicine.

### For care providers

- **Schedule:** today's appointments, the next two weeks, and patients' visit requests waiting for a time.
- **Patients:** each patient's plan, how much of it they completed this week, their visits and unread messages.
- **One-sentence entry:** type "Ibuprofen 400 mg twice a day for 5 days with food" and the form fills itself. The provider always reviews before saving.
- **Visit notes:** what the patient should remember, shown under that visit together with what was prescribed.
- **Patient code:** a 6-letter code patients type once to connect.

## On-device intelligence

CareHold uses AI only where it makes things clearer, and everything stays on the iPhone.

| | Every iPhone | With Apple Intelligence (iOS 26+) |
|---|---|---|
| Common patient questions | Rule-based answers from the care plan | Same |
| Other patient questions | "Send this question to your care provider" | Answered by Apple's on-device model, using only the care plan |
| Notes in simpler words | Not shown | "Explain in simpler words" |
| Provider's one-sentence entry | Rule-based parser | Parser first, on-device model when the rules can't read it |

Guardrails:
- Questions that sound like an emergency always show **Call 911**.
- The assistant never diagnoses or changes a dose. When the plan doesn't answer a question, it offers to send the question to the provider.

## Design

- Warm vanilla background with white cards. A sage tone marks primary actions.
- Soft pastel tints tell things apart: peach for medicines, sage for exercises, lavender for instructions, sky for visits, butter for reminders. Color always comes with an icon and a word.
- Built for everyone, including people with low vision or tremors:
  - Dynamic Type, one step larger than the iOS default
  - 56 pt tap targets
  - VoiceOver labels
  - one clear action per card

## Security

- Supabase Postgres with **row level security on every table**.
  - A patient only sees their own data.
  - A provider only sees the patients linked to them.
  - Anonymous users see nothing.
- Composite foreign keys to the care link stop anyone from attaching data to a patient they are not linked to.
- Column-level update grants keep ids and owners immutable.
- pgTAP tests check that one user cannot read or write another's data.
- The app ships only the publishable key. The session lives in the Keychain (`AfterFirstUnlockThisDeviceOnly`).

## Architecture

```
Packages/Core/        Pure Swift: models, daily plan, assistant rules, plan parser, repository protocols.
                      Tested on Linux with Swift Testing.
Sources/CareHold/     App: composition root, patient and provider screens (SwiftUI + @Observable),
                      on-device AI, local reminders.
Sources/Data/         Supabase repositories and Keychain session storage.
Sources/DesignSystem/ Design tokens and components.
supabase/             Migrations and pgTAP tests.
scripts/              Config, demo data and brand asset generators.
assets/               Logos and design sources.
```

Screens depend only on the protocols in `Core`. Only the composition root knows about Supabase, so the backend or the sign-in method can change without touching the UI.

## Tech stack

- Swift 6 (strict concurrency), SwiftUI, Observation. iOS 18+, iPhone only.
- [Supabase](https://supabase.com): Postgres, Auth, Row Level Security.
- Apple Foundation Models, weak-linked and used only on iOS 26+ devices with Apple Intelligence.
- Built and installed from Linux with [xtool](https://github.com/xtool-org/xtool).

## Getting started

Requirements: Swift 6.4, xtool with the Darwin SDK, Node.js and Docker (for a local Supabase), Python 3 with Pillow.

```sh
# 1. Configuration: copy and fill in (publishable key only, never a secret key)
cp .env.example .env
python3 scripts/config-gen.py        # writes the git-ignored AppConfig.swift

# 2. Local backend with demo data
npx supabase start
python3 scripts/seed-gen.py          # demo accounts use the passwords from .env
npx supabase db reset

# 3. Tests
swift test --package-path Packages/Core
npx supabase test db

# 4. Build, or install on a connected iPhone
xtool dev build
xtool dev
```

For a hosted project:
- Link it with `npx supabase link`.
- Push the schema and demo data with `npx supabase db push --linked --include-seed`.
- Turn off "Confirm email" in Authentication, because the demo accounts sign in with a password.

## Status

CareHold is an early prototype built to explore the idea with real care providers. The following are not built yet:
- push notifications (the app refreshes every 30 seconds while it is open)
- sign-in with email codes or Sign in with Apple
- verification of provider accounts
- translations beyond English
