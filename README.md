# CIVINEX AI

One City. One Community. One Intelligent Future.

A free-to-run Flutter app for reporting and resolving civic faults in Kerala: potholes, flooding,
waste, water leaks, streetlights and more. Built for Digital University Kerala, Vyuham 26, Agent
Forge Hackathon. It starts empty: there is **no demo mode and no sample data**.

## Status: what has and has not been verified

- **Nothing in this project has been compiled or run by the author.** The code was written in an
  environment without the Flutter SDK, so `flutter pub get`, `flutter analyze` and `flutter test`
  have not been executed. Expect a few compile or lint errors on first run and report them.
- The newest changes (version 5 of the app: new sign-in flow, redesign, Document Vault, report
  wizard with GPS address lookup) are the least checked. Packages used for the first time:
  `local_auth`, `flutter_secure_storage`, `cryptography`, `file_picker`, `open_filex`, `http`.
  If a package API differs from what the code expects, the fix will be small and local to
  `lib/services/app_lock.dart`, `lib/services/vault_crypto.dart` or `lib/features/vault/`.
- No Firebase project is connected. Everything runs on this phone's database. See
  "Not done, and why".
- No APK has been built here. Build it yourself (below).
- Requires a recent Flutter (3.33 or newer).

## What is built

| Area | Included |
|---|---|
| Auth | Two separate entrances: **Citizen Login** (with registration) and **Administrator Login** (no self-registration; staff accounts are created by an administrator). A citizen account cannot sign in on the administrator screen and the reverse. First-run administrator setup appears only while no administrator exists. Stay signed in across restarts until you tap Log out. Optional app lock with fingerprint, face or phone PIN. Administrators can reset a forgotten password; change password in Settings. Local salted, iterated SHA-256 hashes |
| Roles | Citizen, Officer (limited to one department), Administrator; enforced in repositories, not just the UI |
| Citizen | Home (own totals: total, pending, in progress, resolved; search; quick actions; city updates), 3-step report wizard (issue, location, review) with automatic GPS, latitude/longitude and address lookup, optional photo, triage preview, My reports with search and status filter, timeline, withdraw while still "Submitted", in-app notifications, nearby problems, City updates board |
| Triage engine | `AiProvider` interface; default is a small Naive Bayes text model (see AF-21 table), with the **rule-based** keyword provider as fallback; explainable priority score (Low/Medium/High/Critical, configurable thresholds), duplicate suggestions (category + distance + age + text overlap), human-review flags |
| Officer | Department-scoped priority queue, status changes with notes, resolve/reject rules, override of category/priority (reason required and logged) |
| Admin | Dashboard from real records (total, pending, critical, resolved, overdue, by department), complaint list, map, insights, user/role management (cannot change own role), password reset, departments, audit log |
| Document Vault | Citizens only. Upload PDF or photo (up to 10 MB) for Aadhaar, Voter ID, Driving Licence, PAN, Passport, Student ID, Ration Card, property papers, bills or other. Files are **AES-256-GCM encrypted on this phone**, the key lives in the Android Keystore, metadata in the local database. Vault PIN (and optional fingerprint), five wrong PINs lock entry for five minutes. Preview images, open PDFs, rename, save a copy, delete, search, filter, expiry dates with in-app reminders at 30 days, 7 days and on expiry. Only the owner can open a document; administrators cannot. ID numbers are never read, shown or sent anywhere |
| Map | OpenStreetMap map of open reports (role and department limited, priority-coloured pins, tap for details, Pins/Groups clustering for everyone, Heat for staff), status filter chips, a "my location" button with a blue dot, list underneath that also works when tiles fail to load, Nearby problems, pin must be inside Kerala |
| Analytics | Staff-only screen: open/resolved/overdue tiles, open reports by priority, 14-day trend, category and department workload bars, plain-language summary from fixed rules (labelled as not AI). Numbers respect department limits. Resolution time is approximate |
| FloodGuard | Flood risk **estimate** (Normal/Watch/Warning/Severe) from rainfall and water-level readings plus recent open flood reports; thresholds editable by admin (defaults are illustrative, not calibrated); manual staff entry; suggested actions; in-app alert to drainage officers and admins when the level rises to Warning or above; list of flood/drain reports the user may see |
| RoadVision | Road damage priority list (priority score, then severity, then age), damage type (pothole, damaged surface, obstruction, uncertain) and severity from **keyword rules on the report text, labelled as such; photos are not analysed**, officer override with logged reason, duplicate suggestions with a human "close as duplicate" action, assignment to a department officer, before/after repair photos. Roads officers and admins only |
| Data | SQLite with migrations (schema v6), foreign keys, indexes, transactions |
| Look | Teal and navy following the supplied mockup, light and dark themes (Settings), campus photo hero, onboarding shown once |

## AF-21 / CIVINEX AI 2.0 additions (built on the same project)

Everything below works on the local database and reuses the existing repositories.
**None of it has been compiled or run** (see Status above).

| AF-21 requirement | What exists | Honest label |
|---|---|---|
| NLP complaint classification, confidence, explanation | `NaiveBayesProvider`: multinomial Naive Bayes trained on-device from ~118 hand-written example complaints (`training_corpus.dart`). Shows probability, two alternatives, and the words that drove the decision. Falls back to the keyword rules (with no percentage) when it knows none of the words | A **real statistical model**, but tiny and trained on examples written for this project. The percentage is the model's own estimate, not a measured accuracy. A scripted check of the same algorithm got 9/9 on my own held-out sentences; expect worse on real complaints |
| Image analysis (YOLO) with human verification | `ImageAnalyzer` interface, `UnavailableImageAnalyzer` default, photo-finding fields, "what does the photo show?" picker, staff confirm/correct with audit | **No image model is installed.** Nothing is labelled "AI detected". `docs/IMAGE_MODEL.md` explains how to plug in a YOLO/TFLite model you supply |
| Duplicate detection, parent incident, reporter count | Score >= 0.75 (category, distance <= 150 m, 14 days, word overlap) links the new report under the earlier one automatically; staff confirm or unlink; lower scores stay suggestions. Reporter count = first reporter + linked reporters + supporters. Children follow the parent's status and notifications | The score is a similarity score, not a probability |
| Clustering, heatmap, repeated locations | `GeoClusterer` (greedy 250 m), Pins / Groups / Heat map modes for staff, recurring-fault detection (100 m, 180 days), "busiest areas" list | Heat = density of reports (priority-weighted). Not a forecast |
| Urgency prediction with explanation, audited override | Additive score from severity, safety risk, people affected, **location importance** (keyword heuristic), duplicate/reporter count, **recurrence**, age. Each point is listed. Overrides need a reason, are audited and are not undone by later reporters | An **explainable rule-based score, not machine learning**. Thresholds are illustrative |
| Routing, officer assignment, acceptance, reassignment | Category -> department; assign / auto-assign to least-loaded officer; officer accepts or rejects with a reason (admins notified); reassignment keeps history; admin can re-route to another department | |
| SLA deadlines, overdue escalation, department performance | Deadline by priority (24 h / 3 d / 7 d / 14 d, illustrative). Housekeeping runs when staff open the app: sets missing deadlines, auto-assigns, escalates overdue reports (level 1, level 2 at twice the window), auto-closes unanswered resolved reports after 7 days. Performance: response time, resolution time, on-time share, overdue, ratings | Runs while the app is open on a device; there is no server clock job |
| 10-step lifecycle with history | Lifecycle panel on every report, full timeline with actors | |
| Citizen: support reports, nearby, before/after, feedback | "Problems near me" (limited view: no text, names or photos; location rounded to ~100 m), "I see this too", before/after photos, rating + "fixed / not fixed" (not fixed reopens) | |
| Officer: accept/reject, internal notes, resources, escalate, SLA | My assigned cases, notes (staff only), resource requests (admins approve or decline), escalate with reason | |
| Admin: departments, officers, heatmap, recurring, overdue, performance, downloads | Admin > Departments (add, rename, move officers); Insights tabs; CSV export of incidents and performance (no reporter names or free text; formulas neutralised; each export audited) | |
| Recurring faults, risk heatmaps, predictive-maintenance insights | Recurring list, heat view, trend and "average gap" projections | Labelled **statistical trend** or **simple projection**. No forecasting model is trained, so there are **no AI predictions** here |
| AI daily city summary | Fixed text templates over today's figures | **Not written by a language model**, and says so on screen |
| Nine modules on one engine | FloodGuard, RoadVision, TrafficMind, WasteWise, AquaSense, LumenCity, Emeroute, AccessCity, CoolCity: each a filtered view of the same incident table (Home > City modules) | No live sensors or feeds are connected to any of them. Emeroute lists safety-flagged, critical and escalated reports and holds no emergency numbers |

### Not done, and why

- **Firebase (Auth, Firestore, Storage, FCM, Cloud Functions):** **not wired in yet.** It needs a Firebase project created by you (free Spark plan, no card), and untested cloud sign-in stacked on an untested redesign would be hard to debug. The plan is in `docs/FIREBASE_FREE_TIER.md` (Auth and Firestore on the free plan; ID documents stay encrypted on the phone because Cloud Storage and Cloud Functions need the paid Blaze plan). Until then accounts and data are local, so **officers and citizens on different phones cannot see each other's data**. This is the biggest gap against the brief.
- **Email password reset and account verification:** need a server to send mail, so they arrive with Firebase. On this build an administrator resets a forgotten password.
- **Server-side authorization:** enforced in the repositories on this device only. A rooted device with the database file can bypass it.
- **YOLO / image model:** not included. No photo is analysed, and nothing is labelled "AI detected". `docs/IMAGE_MODEL.md` explains how to plug one in.
- **Not built in this round:** Malayalam and Hindi, voice reports, QR reporting, chatbot, offline queue with sync, push notifications (in-app only), PDF/Excel export (CSV export exists), repair-completion photo upload by admins beyond the existing before/after photos, live weather feed.
- **Release APK:** not built here. Build it yourself (below).

## Build an APK

```bash
flutter create . --platforms=android      # once; keeps lib/ and pubspec.yaml
powershell -ExecutionPolicy Bypass -File tools\fix_android.ps1   # permissions, minSdk 24, MainActivity
flutter pub get
flutter analyze && flutter test
flutter build apk --release               # build/app/outputs/flutter-apk/app-release.apk
```

A release build signed with the debug key installs for testing. For distribution, create an upload
keystore and configure `android/key.properties` as in the Flutter Android deployment guide.
Set a real `applicationId` (it is `com.example...` after `flutter create`).

## Setup

Full step-by-step: **`docs/SETUP_GUIDE.md`** (install, icons, run, APK, website).

```bash
flutter create . --platforms=android,web,windows,linux,macos   # generates platform folders (keeps lib/ and pubspec.yaml)
flutter pub get
flutter run -d windows   # or linux / macos / android
```

Notes:
- **Map needs internet for tiles** (public OpenStreetMap server). After setup everything else
  works offline (address lookup excepted); with no connection the map shows a notice and the list below still works.
  The public tile server is for light use only (valid User-Agent, visible attribution).
  For real traffic, self-host tiles. Attribution "© OpenStreetMap contributors" is shown on
  every map.
- **Android setup (done by `tools/fix_android.ps1`):** permissions INTERNET, ACCESS_FINE_LOCATION,
    ACCESS_COARSE_LOCATION and USE_BIOMETRIC in `AndroidManifest.xml`; `minSdk 24` (the encrypted
    vault needs Android 7.0 or newer); `MainActivity` extends `FlutterFragmentActivity` (needed
    by the fingerprint dialog).
  - **Address lookup** uses the free OpenStreetMap Nominatim service when you detect or pick a
    location (needs internet; one request per tap, as its usage policy requires). If it fails you
    type the address.
  - iOS: add `NSLocationWhenInUseUsageDescription` to `Info.plist`.
  - Desktop: geolocator is limited there; the app shows a message and you can use "Pick on map".
  - Location is read only when the person taps the button, and is stored only in that report.
- Android/desktop use SQLite. **Flutter Web is not supported yet** (sqflite has no web backend
  here); use a desktop or Android target for now.
- For gallery photo picking on Android, no extra permission setup is needed on recent versions;
  on iOS you would add the photo-library usage description.

## Branding and event identity

The interface carries the project's event identity as part of the product design, not as a banner:
an animated launch screen, a split-screen sign-in with a branded panel, a slim header on every
signed-in screen with an "Agent Forge · Vyuham 26" badge, a hero card on Home, and an About screen
with the full "Built for Vyuham 26 · Agent Forge Hackathon · Digital University Kerala" line.

- **Look:** teal/cyan on dark navy (the CIVINEX logo colours) with a light theme too, following
  the supplied mockup. The campus photo, cropped from your mockup because the original photo is small and carries a caption overlay,
  sits behind the launch screen, sign-in banner,
  Home hero and website hero. Red appears only for critical items and errors. Headlines use Inter
  Display Black (SIL Open Font License, `assets/fonts/Display-Black.otf`). Colours live in
  `lib/core/theme/app_theme.dart`.
- **Sessions:** the app remembers which account is signed in (the id only, never the password)
  and reopens straight to it until the person signs out.
- All text lives in `lib/core/constants/brand.dart`. Check the spelling of the event names there
  and add your team name and members to show them on the About screen.
- The CIVINEX AI logo (supplied by the project owner) lives in `assets/brand/` and is used for the
  launcher icon, native splash, launch screen, headers and the website. No event or host logos are
  bundled; add one only if you have permission. Regenerate icons with
  `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`.
- A static project website is in `website/`. Full walkthrough: `docs/SETUP_GUIDE.md`.
- The app says it is a hackathon project and not an official product of the event or its host.
  Keep that line.

## First use

There is no demo mode. A new install is empty.

1. Open the app, swipe through the three intro pages, choose **Administrator Login**, then
   **First-time setup** to create the first administrator. (This option disappears once one exists.)
2. As administrator: **Manage > Users > Add staff account** for each officer, and
   **Manage > Departments** if you need more departments. Staff post flood readings, advisories and
   alerts under **City updates**.
3. Citizens choose **Citizen Login > Create a citizen account**, then report issues from the
   Report tab.
4. Sign in stays on until **More > Log out** (administrators: avatar > Log out).

Automated tests use fixture accounts from `test/support/demo_seeder.dart`. Those are not part of
the app.

## Tests

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test                      # all unit + widget tests
flutter test test/data            # repository / permission tests
flutter test test/services        # triage, naive Bayes, clustering/recurrence, analytics and flood-risk tests
```

Database tests use in-memory SQLite through `sqflite_common_ffi`, which needs the native
SQLite library on Linux (`sudo apt install libsqlite3-dev`).

## FloodGuard limits

- The estimate is a handful of threshold rules. It is **not** a forecast, not an official warning,
  and rainfall alone cannot predict flooding. Follow official alerts.
- Default thresholds are placeholders. Set them from local knowledge before relying on anything.
- Rain is summed per station over 3 hours assuming one reading per hour per station.
- No live rainfall or water-level feed is connected. Staff type readings in; the source column
  (`manual` / `feed`) is ready for an automatic feed later.

## RoadVision limits

- Classification reads the text only. A photo does not change the result. Say so when you present it.
- Duplicate suggestions use category, distance (150 m), age (14 days) and word overlap. They are not
  confidence scores. "Close as duplicate" rejects the later report with a reason and notifies the
  reporter, and critical reports can only be closed by an administrator.

## Account limits

- There is no email password reset or verification yet (needs the cloud stage). An administrator
  resets a citizen's or officer's password in Manage > Users. If the **only** administrator forgets
  their password there is no recovery: create a second administrator early, or reinstall (data is
  lost).
- Disabling an account or changing a role takes effect at that person's next sign-in.
- Accounts exist only on this device.

## Security and privacy limitations

- Local authentication is for a single-device build. A real deployment needs a server-side
  identity provider, rate limiting on sign-in, and a memory-hard password hash.
- A local database gives no multi-device sync and no central municipal access.
- The database and report photos are **not encrypted at rest**. Only Document Vault files are
  encrypted. The vault key is in the Android Keystore; if the phone's secure storage is reset or
  the app is uninstalled, **vault documents cannot be recovered**. Keep the originals.
- "Save a copy" and "Open PDF" write a **decrypted** copy outside the vault (opened PDFs go to a
  temporary file that is deleted when you leave the vault, saved copies stay where you put them).
- The vault PIN guards the screen; the encryption key is the Keystore key, not derived from the PIN.
- Photos are copied to the app's private folder with random names (JPG/PNG/WebP under 5 MB).
- Retention settings and full data export are not implemented.
- This is not an emergency dispatch system. No emergency phone numbers are included except a
  line telling people to call 112.

## Design notes

- Authorization lives in `core/security/permissions.dart` and is called from
  `IncidentRepository` / `AuthRepository` on every operation. Unknown or unauthorized incident
  IDs both return "not found".
- AI never acts alone: it only suggests category, priority and review flags. Rejection requires a
  human reason, and critical reports can only be rejected by an administrator.
- The text model is `NaiveBayesProvider`. To use a different model, implement `AiProvider` and swap it in `aiProviderProvider`.
  Do not label output as model-generated unless a model actually ran.
- Cost: all dependencies are free and open source (Flutter, Riverpod, sqflite, sqflite_common_ffi,
  path_provider, image_picker, uuid, crypto, intl, http, local_auth, flutter_secure_storage, cryptography, file_picker, open_filex). No API keys are used. Check current licenses
  before redistribution.

## Suggested next steps

1. Run `flutter pub get`, `flutter analyze`, `flutter test`, then the app on your phone, and send
   me anything that fails.
2. Create a free Firebase project and follow `docs/FIREBASE_FREE_TIER.md` so accounts and reports
   are shared between phones.
3. Supply the original, uncaptioned campus photo and the DUK / Vyuham logos if you want them in the
   hero images (only with permission).

## Firebase (Stage A, free Spark plan)
Accounts (sign-in, email reset, verification, roles) can run on Firebase Authentication + Firestore.
Reports still stay on each phone until Stage B. Setup: `docs/FIREBASE_SETUP.md`. Not yet compiled or run.

## AI assistant (optional, Claude via the hackathon key)
`server/` holds the key and runs on a laptop; the app only sends report text or aggregate counts to it.
Adds "Suggest with Claude" in the report form and an AI briefing on the admin dashboard. The app works
without it. Setup: `server/README.md`. Prototype only; not compiled or run by me.

## Stage B (report sync) and city services
Reports, assignments, notes, notifications, city updates and the services directory are shared between
phones through Firestore (free plan). Automatic officer routing runs on an administrator's phone.
City services: search a city; OpenStreetMap places plus places added by staff (officers an administrator
allotted). Setup and limits: `docs/FIREBASE_SETUP.md`. Not compiled or run by me.

## Photo reports, photo check and civic points

- **Camera first.** "Report" opens the phone camera. The location is read automatically at the same time, and if the AI assistant is set up the photo is analysed and the category and description are pre-filled. Everything stays editable; the citizen confirms on the review step.
- **Is the photo AI-generated?** No app can reliably prove that. CIVINEX records (a) whether the photo was taken live in the app, (b) when, and whether GPS was available, and (c) an AI model's *opinion* (real photo / photo of a screen / illustration or generated). A questionable result never rejects a report; it flags it for human review and shows staff a warning. Gallery photos are allowed but labelled "not verified as live". Without the assistant there is no AI opinion and it says so.
- **Civic points.** Counted from the citizen's own reports (nothing stored, so nothing to edit): +10 report (3 a day), +5 live unflagged photo, +10 city takes it up, +15 resolved, +5 confirmed same-problem, +3 feedback. Rejected or withdrawn reports earn nothing. Points have no cash value.
- **Logo.** Run `tools\apply_logo.ps1` once (launcher icon and start-up screen), then uninstall the old app and reinstall.
