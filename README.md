# SipBuddy 💧

A friendly macOS menu bar companion that reminds you to drink water. It talks like a friend, not an alarm.

When it's time for a sip, the reminder covers every connected screen. **It stays there until the camera sees you drinking.** It counts your sips and closes after 5. The screen with the camera (the built-in display when the built-in camera is in use) shows the live camera view; other screens show the message and point you to it. A smaller corner card is available in Settings.

## Features

- **Menu bar popover:** a time-of-day greeting, a water drop that fills as you drink, a progress ring, automatic logging (no manual entry: each sip the camera counts adds about 25 ml), today's entries with edit and delete, and the next reminder with pause and snooze.
- **Closes when you drink:** Apple's Vision framework tracks your face, hands and posture on-device. Taking 5 sips from a bottle or cup closes the reminder (each lift to your mouth of at least 0.6 s is a sip, and steady gulping counts one sip every 1.5 s; a bottle, cup, mug, glass, jug, thermos or straw must be seen near your face, so resting your chin on your hand doesn't count), and so does clicking the ✕ in the top-right corner; the face is remembered while the glass covers it. Only the person closest to the camera counts, so people in the background are ignored. The camera runs only while a reminder is showing and turns off after 10 minutes, but the reminder stays. If the camera is unavailable or access is denied, a ✕ button appears so you're never stuck. You can also switch to standard macOS notifications, which have Log 250 ml and Snooze 15/30 min actions.
- **70 conversational messages** in 7 categories: friendly, funny, motivational, caring, work-break, goal, and minimal. The same message never appears twice in a row.
- **4 personalities:** Friendly Friend, Funny Buddy, Motivational Coach, Minimal Assistant.
- **Smart scheduling:** interval presets (30/45/60/90/120 min) or a custom interval, start and end times, working days, separate weekend hours, lunch break, sleep hours, stop-at-goal, and pause or snooze. Logging water pushes the next reminder out.
- **Statistics:** today, goal %, glasses, streak, 30-day average, best day, a weekly or monthly chart (click a bar to open that day), a month heatmap, and browsing and editing any past day.
- **Settings:** goal (default 2 L), glass size, units (ml / L / oz), sounds, daily summary notification, light, dark or system appearance, 6 accent colours, launch at login, hide the menu bar icon, reset today, and export to CSV.
- **Private:** everything is stored locally. There's no account and no network access.

## Requirements

- macOS 14 Sonoma or later (Apple Silicon or Intel)
- Xcode 16+ to build. Developed with Xcode 26.1.

## Build & run

```bash
open SipBuddy.xcodeproj        # then press ⌘R
```

Or from the terminal:

```bash
xcodebuild -project SipBuddy.xcodeproj -scheme SipBuddy -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/SipBuddy.app
```

Run the tests (covering scheduling, messages, stats, persistence and drinking detection):

```bash
xcodebuild -project SipBuddy.xcodeproj -scheme SipBuddy -derivedDataPath build test
```

On first launch, macOS asks for notification permission. The first reminder card asks for camera permission.

## Packaging

```bash
./scripts/package.sh
```

This creates `dist/SipBuddy.app`, `dist/SipBuddy.zip` and a drag-to-Applications `dist/SipBuddy.dmg` (universal binary, ad-hoc signed). Install by dragging SipBuddy into `/Applications`. Launch at login works most reliably from there.

To share with other Macs, sign with a Developer ID and notarize:

```bash
SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/package.sh
xcrun notarytool submit dist/SipBuddy.dmg --keychain-profile <profile> --wait
xcrun stapler staple dist/SipBuddy.dmg
```

## Architecture (MVVM)

| Component | Role |
|---|---|
| `SipBuddyApp`, `AppModel` | Entry point and composition root that wires the managers together |
| `MenuBarManager` | Status item, popover, Settings and Statistics windows |
| `HydrationManager` | Adding, undoing, editing and deleting entries, today's totals, goal celebration |
| `ReminderPlanner` | Pure scheduling rules (quiet hours, weekdays, snooze, pause, catch-up) |
| `ReminderScheduler` | Keeps exactly one reminder pending; handles sleep, wake and day changes |
| `NotificationManager` | Permission, categories and actions, the pending request, daily summary |
| `ReminderCardController`, `DrinkingDetector` | Full-screen or corner reminder plus camera and Vision drinking detection |
| `MessageLibrary` | Messages, personality weighting, greetings |
| `StatisticsManager`, `StatisticsViewModel` | Totals, streak, averages, best day, chart data |
| `SettingsManager` | All preferences (UserDefaults) |
| `PersistenceManager` | JSON history in Application Support, CSV export |
| `LaunchAtLoginManager` | `SMAppService` login item |

**No reminder pile-up after sleep.** Only one reminder is ever pending. It's cancelled when the Mac goes to sleep. On wake, the planner schedules a single catch-up reminder 5 minutes later instead of replaying the ones it missed. This also stays well under macOS's 64-pending-notification limit.

**History survives midnight.** "Today" is just a date filter, so nothing is deleted when the day changes.

Data lives at `~/Library/Containers/com.gopinath.SipBuddy/Data/Library/Application Support/SipBuddy/entries.json`.

## Debug helpers (Debug builds only)

`-debugOpen popover|stats|settings|card` opens a screen at launch, and `-debugSnapshot name.png` saves it into the app's sandbox `tmp` folder.

---

SipBuddy is a friendly reminder, not medical advice.
