# PawDone — Product Spec (v1)

**Status:** Final for v1 · **Last updated:** 13 Oct 2026

---

## 1. Summary

PawDone is an iPhone app where pet owners set a daily care schedule for their pet, tick off each task as it happens (with an optional photo as proof), get reminders when tasks are due, and see a day-by-day report of what was done and what was missed.

Paying owners can invite up to 2 family members or helpers. They can see the pet's daily updates and mark tasks done, so the pet is covered while the owner is away.

**Problem we solve:** "Did anyone feed Bruno?" — missed meals, double feeding, forgotten medicine, and no visibility when you're away from home.

| | |
|---|---|
| Name | **PawDone** |
| App Store title | PawDone: Pet Care Tracker |
| Tagline | Fed yet? Walked yet? Now you'll know. |
| Icon | White paw with a check on a coral gradient ([design/](../design)) |
| Platform | iPhone only (iOS 17+) |
| Language | English |
| Market | Global from launch |
| Marketing | Organic, starting with X/Twitter (no paid budget) |

---

## 2. Plans & pricing

**No free trial.** The Free plan is free forever; Premium is paid from day one.

| | **Free** | **Premium** |
|---|---|---|
| Price | Free forever | India: ₹199/month, ₹499/3 months<br>Other countries: $3.99/month, $9.99/3 months |
| Pets | 1 | 1 (multiple pets in v2) |
| Schedules, check-offs, reminders | ✅ | ✅ |
| Reports | ✅ Unlimited history | ✅ Unlimited history |
| Photo proof (optional) | Stored on the phone only | Stored in the cloud, visible to everyone in the household |
| Invite family / helpers | ❌ | Up to 2 people |
| Devices | 1 phone at a time | All of the owner's Apple devices |

### Subscription rules
- Purchases go through the App Store, managed with RevenueCat. The paywall has **Restore purchases** and a link to **Manage subscription**.
- Premium unlocks immediately after purchase.
- Tapping **Invite** on Free opens the paywall.

### When Premium ends (cancelled or expired)
- **Members** lose access to the owner's pet. They stay listed as "paused" and get access back automatically if the owner resubscribes.
- **Owner** keeps all data and history.
- Photos already in the cloud stay viewable. New photos are saved on the phone.
- The one-phone rule applies again.

---

## 3. Users & roles

There are two roles: **Owner** (the person who adds the pet) and **Member** (a family member or helper invited by a Premium owner).

| Action | Owner | Member |
|---|:---:|:---:|
| Add / edit / delete pet | ✅ | ❌ |
| Create / edit schedule | ✅ | ❌ |
| See today's checklist | ✅ | ✅ |
| Mark a task done (+ optional photo and note) | ✅ | ✅ |
| Undo their own check-off (same day) | ✅ | ✅ |
| View reports | ✅ | ✅ |
| Invite / remove members | ✅ | ❌ |
| Manage subscription | ✅ | — |

- Members sign up with their own free account. They don't pay anything.
- A member can belong to more than one owner's household (e.g. a dog walker working for several families).
- A member can also add their own pet as an owner, on their own Free or Premium plan.

---

## 4. Features

### 4.1 Sign-in & account
- **Sign in with Apple** (primary) and **Sign in with Google**. No passwords, no SMS codes.
- **Onboarding:** sign in → your name → add your pet → add first tasks from suggestions (Morning food, Evening food, Walk, Water refill, Medicine) or create your own.
- **Settings:** profile, notification preferences, subscription, privacy policy, terms, log out, **delete account**.
- **Delete account** (required by Apple): deletes all of the user's data and household memberships, and reminds them to cancel any App Store subscription.

### 4.2 One phone per account
- Each app install creates a device ID, stored in the iPhone Keychain so it survives reinstalling the app.
- **Free accounts** (including all members) can be signed in on only one phone at a time.
- Signing in on a new phone shows: *"You're signed in on another iPhone. Continue here? You'll be signed out there."* On confirm, the old phone is signed out. When it's opened next, it shows *"Signed in on another device."*
- **Premium owners** have no device limit. Apple requires subscriptions to work on all of the user's devices (App Store guideline 3.1.2a).
- Free users' photos are stored on the phone, so they don't move to a new phone unless the user restores an iPhone backup (see 4.6).

### 4.3 Pets
| Field | Required | Notes |
|---|:---:|---|
| Name | ✅ | |
| Species | ✅ | Dog, Cat, Bird, Rabbit, Fish, Other |
| Breed | | |
| Date of birth | | |
| Gender | | |
| Photo | | |
| Notes | | e.g. allergies, vet's phone number |
| Timezone | ✅ | Defaults to the owner's phone timezone. All task times use this. |

- **1 pet per owner on both plans in v1.** Multiple pets come in v2.
- Deleting a pet deletes its schedule and history, after a confirmation dialog.

### 4.4 Schedule (tasks)
| Field | Required | Notes |
|---|:---:|---|
| Title | ✅ | e.g. "Morning food" |
| Category | ✅ | Food, Water, Walk, Medicine, Grooming, Play, Clean-up, Other (each has an icon) |
| Time | ✅ | e.g. 08:00, in the pet's timezone |
| Repeat | ✅ | Every day, or selected weekdays |
| Reminder | | On / off (default on) |
| Instructions | | e.g. "1 cup kibble + half tablet". Shown to members, which is useful for helpers. |

- Editing or deleting a task changes **today's pending task and future days only**. Past history keeps what was scheduled at the time.

### 4.5 Today (daily checklist) — home screen
Shows today's tasks for each pet, sorted by time. Each task has one status:

| Status | Meaning |
|---|---|
| **Pending** | Not done yet. Labelled **Overdue** once its time has passed, but it can still be marked done. |
| **Done** | Shows who did it, at what time, and the photo and note if added. |
| **Missed** | Nobody marked it by the end of the day (midnight in the pet's timezone). |

- **Mark done:** tap the task → optionally take a photo → optionally add a note → Save.
- **Live updates:** as soon as anyone marks a task done, everyone in the household sees it. This prevents double feeding.
- **Undo:** the person who marked a task done can undo it the same day.
- Tasks can only be marked for **today**. No back-filling of past days and no marking future days, so reports stay honest.

### 4.6 Photo proof
- Optional on every check-off.
- **Camera only:** photos are taken with the in-app camera, not picked from the photo library, so they're real proof of that moment.
- Photos are resized (about 1600px, ~300 KB) and their location data is removed before saving.
- **Free:** saved on the phone only. They're included in the user's iPhone/iCloud backup.
- **Premium:** uploaded to the cloud and visible to everyone in the household. On upgrading, photos already on the phone upload in the background.

### 4.7 Notifications
| Notification | Who gets it | When |
|---|---|---|
| **Task reminder** | Owner and all members (each person can turn reminders off per pet) | At the task's scheduled time, **only if it isn't done yet** |
| **Task completed** | Everyone in the household (owner and members) | When anyone marks a task done, with a photo thumbnail if one was added |

- Nobody gets notified about their own actions.

### 4.8 Reports
- **Calendar view:** each day shows a completion score (e.g. "4/5 done") with a green / amber / red indicator.
- **Day detail:** every task for that day with its result:
  - ✅ **Done**: who, what time, photo, note
  - ❌ **Missed**
- Unlimited history on both plans.
- Visible to the owner and members.

### 4.9 Household & invites (Premium)
- Owner taps **Invite someone** and shares an 8-character code (e.g. *K7P2 QX9M*) via iMessage, WhatsApp, etc. A tap-to-join link can come later, once there's a website.
- The code works once and expires after 7 days. Case and spaces don't matter when typing it.
- The helper installs the app, signs in, chooses **Join a household**, enters the code and sees *"Join Sam's household?"* → **Join**.
- Up to 2 members per owner. Pending invites count toward the limit.
- The owner can remove a member, and a member can leave at any time.
- Someone who helps with other pets, or has their own, switches between them from Today or Account.
- When the owner's Premium ends, helpers see the household as paused; it comes back when Premium is renewed.

---

## 5. Technical approach

| Layer | Choice |
|---|---|
| iOS app | SwiftUI, iOS 17+, Swift concurrency. Local cache so the app works offline; check-offs made offline sync when back online. |
| Backend | **Supabase:** Auth (Apple, Google), Postgres with Row Level Security, Storage (photos, private bucket with signed URLs), Realtime (live checklist), Edge Functions + pg_cron (scheduled jobs) |
| Push notifications | Apple Push Notification service (APNs), sent from Supabase Edge Functions |
| Payments | StoreKit via **RevenueCat**. A RevenueCat webhook updates an `entitlements` table so the server knows who is Premium. |

### 5.1 Data model (first draft)

| Table | Key columns |
|---|---|
| `profiles` | id, name, avatar_url, created_at |
| `devices` | id, user_id, device_id, apns_token, is_active, last_seen_at |
| `entitlements` | user_id, is_premium, product_id, expires_at, updated_at |
| `pets` | id, owner_id, name, species, breed, birth_date, gender, photo_path, notes, timezone, created_at |
| `tasks` | id, pet_id, title, category, time_of_day, weekdays, reminder_enabled, instructions, created_at, archived_at |
| `task_occurrences` | id, task_id, pet_id, date, scheduled_at (UTC), status (pending / done / missed), completed_by, completed_at, note, photo_path · unique(task_id, date) |
| `household_members` | owner_id, member_id, joined_at |
| `invites` | id, owner_id, token, expires_at, accepted_by, accepted_at |
| `notification_prefs` | user_id, pet_id, reminders_enabled |

### 5.2 How the key parts work
- **Daily task list:** a scheduled job creates each day's `task_occurrences` ahead of time (e.g. 2 days out), based on each pet's timezone. Editing a task regenerates only pending occurrences from today onward, so past reports never change.
- **Missed tasks:** after midnight in the pet's timezone, a job marks any still-pending occurrences as `missed`.
- **Reminders:** pg_cron runs every minute and finds pending occurrences that are due now with reminders on. An Edge Function then sends a push to the household's devices. Tasks that are already done are skipped.
- **Completion notification:** when anyone marks an occurrence `done`, an Edge Function sends a push to everyone else in the household.
- **Access control (Row Level Security):** a user can access a pet's data if they are the owner, **or** they are a member of the owner's household **and** the owner's Premium is active. Members can only update completion fields on occurrences, not pets or tasks.
- **One-phone rule:** on sign-in the app calls `register_device`. For Free accounts, the server marks other devices inactive and signs out their other sessions. The app re-checks device status on launch and when it returns to the foreground.
- **Time:** all times are stored in UTC and shown in the pet's timezone.

---

## 6. Privacy & App Store requirements
- Sign in with Apple, including "Hide My Email".
- Account deletion inside the app.
- Privacy policy and terms, linked in the app and on the App Store listing.
- App Store privacy labels: name, email, photos (user content), device ID. No tracking, so no tracking permission prompt.
- GDPR: honour data export and deletion requests.
- Location data removed from all photos.
- Paywall shows price, billing period and renewal terms clearly, plus Restore purchases (Apple guideline 3.1.2).

---

## 7. Not in v1 (later)
- Multiple pets per owner (v2)
- Android app, or a web link for caretakers on Android
- Shareable "pet's week" photo collage for social media (free marketing; recommended for v1.1)
- Yearly plan
- Assigning a task to a specific person
- "Still not done after 30 minutes" alerts
- Health records: vaccines, vet visits, weight
- Home-screen widgets, Apple Watch
- Other languages
- Food reorder / affiliate revenue

---

## 8. Competition
- **Pawlo – Pet Care Tracker** (iOS, launched 2026) is the closest match: a shared household pet-care checklist with live sync and who-did-what.
  - **Free plan:** 1 pet, unlimited household members, 3 daily tasks.
  - **Premium:** $2.99/month or $24.99/year.
  - Sharing is free there, while it's our paid feature.
- **PawProof** (iOS) is a pet vaccine and health-records app. It owns the "PawProof" name.
- **Our angle:** photo **proof** of care, and a clear report of what was missed. Best for owners who rely on helpers, sitters or walkers. Marketing should lead with "know it was really done", not just "shared checklist".

---

## 9. Setup checklist (before building)
These need the owner's own identity and payment details:
- [ ] Join the Apple Developer Program ($99/year)
- [ ] Sign the Paid Apps agreement in App Store Connect and add bank and tax details (needed for subscriptions, even in testing)
- [ ] Reserve **PawDone** in App Store Connect; check the domain, X handle (@pawdone) and trademark databases
- [ ] Create free Supabase and RevenueCat accounts
- [ ] Get a domain and publish privacy policy and terms pages

---

## 10. Build order (proposed)
1. **Setup:** Xcode project, Supabase project, sign-in (Apple + Google), one-phone rule.
2. **Free plan core:** pets, schedule, Today checklist, photos on the phone, missed-task job.
3. **Reports.**
4. **Reminders** (push notifications).
5. **Premium:** RevenueCat paywall, households and invites, cloud photos, live updates, completion notifications, downgrade handling.
6. **Launch prep:** account deletion, privacy policy, App Store listing, TestFlight beta with ~20 people from X, then submit.
