# App Store listing

Everything to fill in on App Store Connect for TailTick 1.0, ready to copy. Character limits
are in brackets.

## Upload a build

Each upload needs a new build number. It's `CURRENT_PROJECT_VERSION` in `ios/project.yml`
(the version shown in the App Store, `MARKETING_VERSION`, stays `1.0.0`). After changing it,
run `xcodegen` in `ios/`, then in Xcode pick **Any iOS Device**, **Product → Archive**, and
**Distribute App → App Store Connect**.

## Screenshots

Upload `design/app-store/screenshots/*.jpg`, in order, to the **iPhone 6.9" Display** slot.
App Store Connect scales them down for smaller iPhones. TailTick is iPhone-only, so no iPad
screenshots are needed.

They contain no prices: prices differ by country and Apple rejects screenshots that show them.

To retake them after a UI change:

1. Boot the iPhone 17 Pro Max simulator, set light mode and a clean status bar:
   `xcrun simctl status_bar booted override --time 9:41 --batteryState discharging --batteryLevel 100 --wifiBars 3 --cellularBars 4 --operatorName ""`
2. Build the Debug app and launch it with `-PawDoneScreenshots`, which starts signed in to a
   ready-made account: Bruno the dog, two helpers, Premium and a month of history. Today's
   tasks before the current time are done, so take them during the day.
3. Save each screen with `xcrun simctl io booted screenshot design/app-store/raw/<name>.png`
   (`today`, `family`, `reports`, `task`, `premium`, `schedule`). Reports has the 14th
   selected; `task` is Joint supplement opened from Schedule.
4. In `design/app-store/`, run `swift make-screenshots.swift`. Captions are set in that file.

### Subscription review screenshot

Each subscription's **Review Information** needs a screenshot of where it's sold: upload
`design/app-store/subscription-review-paywall.png` to both. To retake it, launch with
`-PawDoneScreenshots -PawDoneFreePlan` (the same account without Premium) and open the
Premium tab. Only App Review sees it, so the prices on it don't matter.

## Subscriptions

| Field | Value |
|---|---|
| Subscription group display name | TailTick Premium |
| Monthly | `com.abhaysingh.pawdone.premium.monthly` |
| 3 months | `com.abhaysingh.pawdone.premium.quarterly` |

The product IDs keep the app's old working name; customers never see them.

## App Information

| Field | Value |
|---|---|
| Name [30] | TailTick |
| Subtitle [30] | Pet care schedule & reminders |
| Primary category | Lifestyle |
| Secondary category | Productivity |
| Content rights | No, it doesn't contain, show or access third-party content |
| Privacy Policy URL | https://abhay244.github.io/PawDone/privacy/ |

### Age rating

Answer **None** or **No** to every question. The result should be **4+**.

- *User-generated content*: **No**. Photos and notes are only seen by the owner and the
  people they invite with a code. Nothing is public and strangers can't find or contact
  anyone.
- *Medical or treatment information*: **No**. Medicine tasks are reminders the owner writes
  for their pet, not health advice.
- *Unrestricted web access*, *messaging*, *advertising*, *parental controls*: **No**.

## Version 1.0 page

### Promotional text [170]

Can be changed any time without a new review.

```
Share your pet's daily care with family and helpers. See what's done, who did it and what was missed, with reminders and photo proof.
```

### Description [4000]

```
TailTick keeps your pet's daily care on track, even when several people share it.

Set up your pet's routine once: walks, meals, fresh water, medicine, grooming and play. TailTick shows today's list, reminds you when something is due, and records who did each task and when.

TODAY AT A GLANCE
• Every task for the day, and what's still left
• Mark a task done in one tap, with an optional note
• Add photo proof, taken with the camera there and then
• A reminder when a task is due and not done yet

REPORTS
• A calendar of every day, showing what was done and what was missed
• Tap a day to see each task, who did it and when
• Tasks left unfinished are marked missed at the end of the day

SCHEDULE
• Every day, or only on the days you pick
• A time and a reminder for each task
• Instructions for helpers, like "half a tablet with food"

PREMIUM: SHARE THE CARE
• Invite up to 2 family members, pet sitters or dog walkers with a code
• Helpers see your pet's day and mark tasks done; only you can change the schedule
• Photo proof is shared with everyone in the household
• Everyone gets a notification when a task is done
• Use TailTick on all your devices at the same time

The free plan is free forever: one pet, the full schedule, reminders, photo proof on your phone and reports, on one iPhone.

Premium is an auto-renewing subscription, billed monthly or every 3 months. Payment is charged to your Apple Account when you confirm the purchase. It renews automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel it in your App Store account settings.

Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://abhay244.github.io/PawDone/privacy/
```

The Terms of Use link is required for apps with subscriptions (guideline 3.1.2). TailTick uses
Apple's standard licence agreement, so leave the custom EULA field in App Information empty.

### Keywords [100]

Words already in the name and subtitle (pet, care, schedule, reminders) count anyway, so
they aren't repeated.

```
dog,cat,puppy,kitten,feeding,walk,tracker,routine,family,sitter,medicine,log,daily,planner,chores
```

### URLs and other fields

| Field | Value |
|---|---|
| Support URL | https://abhay244.github.io/PawDone/support/ |
| Marketing URL | https://abhay244.github.io/PawDone/ |
| Version | 1.0.0 |
| Copyright | 2026 Abhay Singh |
| Build | The latest TestFlight build |
| In-App Purchases and Subscriptions | Add both Premium subscriptions (monthly and 3 months) |
| Version release | Manually release this version |

The subscriptions are reviewed together with this first version. They must be attached
here, or the app is reviewed without them and the paywall shows no plans.

### App Review information

Untick **Sign-in required**: TailTick only offers Sign in with Apple and Google, so there's no
demo username and password. The notes explain how to get in.

Notes:

```
Sign in with Apple (or Google) using any account; no demo account is needed. A new account goes through a short setup: your name, your pet, then suggested daily tasks.

Free plan:
- One pet, used on one phone. Signing in with the same account on a second device (for example an iPad) asks to move the account there and signs out the first device. Premium removes this limit.
- Photo proof uses the camera only, on purpose, so the photo is taken at the time of care. On a device without a camera the app says so.
- Reminders are push notifications sent by our server at each task's time if it isn't done yet.

Premium (auto-renewing subscription, monthly or 3 months):
- Premium tab > choose a plan. Restore purchases is on the same screen.
- Adds inviting up to 2 people, shared photo proof, notifications when someone finishes a task, and use on several devices.

Inviting a helper needs a second Apple Account on a second device:
1. On the first device, with Premium: Account > Family & helpers > Invite someone. This shows an 8-character code.
2. On the second device, sign in with another account and choose "Join someone's household instead" during setup (or Account > Join a household), then enter the code.
The helper can mark tasks done but can't change the schedule.

Deleting an account: Account > Delete account. This deletes the account, the pet, its history and photos, and revokes Sign in with Apple.
```

Contact information: your name, phone number and email, used only by App Review.

## App Privacy

**Data collection**: Yes, TailTick collects data. For every type below, answer: used for
**App Functionality** only, **linked to the user**, **not used for tracking**.

| Category | Type | What it is |
|---|---|---|
| Contact Info | Name | The name you enter, shown to your helpers |
| Contact Info | Email Address | From Sign in with Apple or Google |
| User Content | Photos or Videos | Photo proof, when shared with the household (Premium) |
| User Content | Other User Content | Pet details, tasks, notes |
| Identifiers | User ID | Your account ID |
| Identifiers | Device ID | A random ID per install, for the one-phone rule, and the push token |
| Purchases | Purchase History | Your subscription, via RevenueCat |

No tracking, no ads, no analytics. This matches `ios/PawDone/Resources/PrivacyInfo.xcprivacy`;
change both together.

## Pricing and Availability

- **Price**: Free (Premium is sold in the app).
- **Availability**: all countries, except **China mainland**. Apps there need a government
  ICP filing number, which TailTick doesn't have.
- **EU Digital Services Act**: App Store Connect asks whether you're a trader. Someone
  selling subscriptions usually is, and traders' address, phone and email are shown on the
  EU App Stores. If you'd rather not publish those, remove the EU countries from
  Availability.

## After approval

With manual release, the app waits in **Pending Developer Release** until you press
**Release This Version**. Check that the live paywall shows local prices (₹199 and ₹499 in
India, $3.99 and $9.99 in the US) before telling people about it.
