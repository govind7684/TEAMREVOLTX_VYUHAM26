# CIVINEX AI: complete step-by-step guide

From a zip file to an APK on your phone, plus the website and a presentation script.

**Read this first.** The code was written without being compiled (no Flutter SDK was
available where it was written). Expect to fix a few compile errors the first time.
Steps 4 and 5 show how, and what to send back so they can be fixed quickly.

---

## Part 1. Install the tools (about 45 minutes, free)

1. **Flutter SDK** (3.33 or newer): follow https://docs.flutter.dev/get-started/install for your OS.
   Unzip it somewhere permanent (for example `C:\src\flutter`), add `flutter\bin` to your PATH.
2. **Android Studio** (https://developer.android.com/studio). On first launch install the
   Android SDK, then in *Settings > Languages & Frameworks > Android SDK > SDK Tools* tick
   **Android SDK Command-line Tools**.
3. Accept licences and check the setup:
   ```bash
   flutter doctor --android-licenses
   flutter doctor
   ```
   Fix every red cross for **Android toolchain** before going on. (Visual Studio is only needed
   for Windows desktop builds, not for the APK.)
4. **A phone or emulator.**
   - Real phone: *Settings > About phone*, tap *Build number* 7 times, then *Developer options > USB debugging*.
     Connect by USB and accept the prompt. `flutter devices` should list it.
   - Emulator: Android Studio > Device Manager > Create device (a Pixel with a recent Android image).
5. A code editor: VS Code with the Flutter extension, or Android Studio.

## Part 2. Set up the project

1. Unzip `civinex_ai.tar.gz` (on Windows use 7-Zip) and open a terminal in the `civinex_ai` folder.
2. Generate the platform folders. This keeps `lib/`, `pubspec.yaml` and `assets/`:
   ```bash
   flutter create . --platforms=android
   ```
   (Add `,windows` or `,linux` or `,macos` if you also want to run on a computer. Do **not** add `web`:
   the database does not support it yet.)
3. **Android permissions (easiest way).** Run this once from the project folder. It adds the
   internet and location permissions and the app name, and is safe to run again:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\fix_android.ps1
   ```
   Without these lines, "Use my location" always fails. After running it, **reinstall** the app
   (`flutter run` again). The manual way is below if you prefer it.

   **Android permissions (by hand).** Open `android/app/src/main/AndroidManifest.xml` and put these
   lines inside `<manifest>`, above `<application>`:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
   <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
   ```
   Also set `minSdk = 24` in `android/app/build.gradle(.kts)` and make `MainActivity` extend
   `FlutterFragmentActivity` (see Part 2b). In the manifest file change `android:label="civinex_ai"` to `android:label="CIVINEX AI"`.
4. **Application id.** Open `android/app/build.gradle` (or `build.gradle.kts`) and change
   `applicationId "com.example.civinex_ai"` to something of yours, for example
   `in.yourteam.civinex`. Also change `userAgentPackageName` in
   `lib/features/map/osm_map.dart` to the same value (OpenStreetMap asks for an identifying
   user agent).
5. **Team name.** Edit `lib/core/constants/brand.dart`: check the spelling of the event names and
   add your team name and members. They appear on the About screen.

## Part 2b. Android setup and first use

Run `powershell -ExecutionPolicy Bypass -File tools\fix_android.ps1` once (after `flutter create`).
It adds the INTERNET, location and USE_BIOMETRIC permissions, sets the app name, sets
`minSdk 24` (the encrypted vault needs Android 7.0 or newer) and makes `MainActivity` extend
`FlutterFragmentActivity` (the fingerprint dialog needs it). If it cannot find `MainActivity`,
open `android/app/src/main/kotlin/.../MainActivity.kt` and change `FlutterActivity` to
`FlutterFragmentActivity` (import `io.flutter.embedding.android.FlutterFragmentActivity`).
Then `flutter clean`, `flutter pub get`, and **uninstall the old app from the phone** before
`flutter run`, because permissions and the database format changed.

There is no demo mode and no sample data. A new install is empty.

1. **First launch.** Swipe through three intro pages (shown once). The welcome page offers
   **Citizen Login** and **Administrator Login**.
2. **First administrator.** Tap **Administrator Login**, then **First-time setup**. That button only
   appears while no administrator exists. Create a second administrator soon as a spare, because a
   lone administrator who forgets their password cannot be recovered.
3. **Officers.** Sign in as administrator, open **Manage > Users > Add staff account**. Each officer
   belongs to one department. Administrators and officers cannot self-register.
4. **Citizens** tap **Citizen Login > New here? Create a citizen account**.
5. **Forgotten password.** On this build an administrator opens **Manage > Users**, taps the person's
   menu and **Reset password**, and gives them a temporary one. Email reset needs the cloud stage.
6. **Stay signed in.** Everyone stays signed in on that phone, even after the app or the phone is
   restarted, until they log out (**More > Log out**; administrators: tap the avatar at the top
   right). **Settings > App lock** optionally asks for fingerprint, face or phone PIN on opening.
7. **Entering data by hand (for now).**
   - *City updates* (megaphone icon at the top): officers and the administrator tap **Post update**
     to publish a reading, advisory, alert or notice. Everyone signed in can read them. An **Alert**
     also sends an in-app notification to everyone.
   - *FloodGuard*: staff tap **Enter a reading** (rainfall mm, water level cm). The estimate updates.
8. **Later, automatic.** Every update stores where it came from (`manual` today). An importer can
   write the same rows with source `feed`. That importer needs a server and is not built.
9. **Document Vault (citizens).** Home > Documents, or More > Document Vault. First time: choose a
   4 to 8 digit PIN. Add a document (file or camera photo), pick its type, optionally an expiry date.
   It is encrypted before it is saved. Documents cannot be recovered if the app is uninstalled.
10. **Reporting.** Report tab: choose a category (optional), describe the problem, then the app asks
    your phone for its GPS position and shows latitude and longitude; the address is looked up on
    OpenStreetMap (internet needed) and you can correct it or pick the spot on the map.

Data stays on each phone: a citizen's phone does not receive what an officer types on another
phone until the Firebase sync is built (`docs/FIREBASE_FREE_TIER.md`). When presenting, show every
role on one phone.

## Part 3. Logo, app icon and launch screen

The logo is already in `assets/brand/` and wired into the app:

| File | Used for |
|---|---|
| `logo_full.png` | Launch screen (`BrandLogo`) |
| `mark.png` | The "C" mark in headers, sign-in and About (`BrandMark`) |
| `app_icon.png` | Launcher icon |
| `app_icon_foreground.png` | Android adaptive-icon foreground |
| `splash_mark.png` | Native launch screen shown before the app starts |

Generate the launcher icons and the native splash (needs `flutter pub get` first):
```bash
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```
Run these after `flutter create` (they write into `android/`). If you ever change the logo, replace
the files in `assets/brand/` and run the two commands again.

## Part 4. Check that it compiles

```bash
flutter pub get
flutter analyze
flutter test
```
- `flutter analyze` must finish with no **errors**. Warnings and hints are fine for now.
- `flutter test` runs about 120 tests. On Linux the database tests need `sudo apt install libsqlite3-dev`.
- **If anything fails**, copy the full red output (file name, line, message) and send it back.
  Most first-run problems are small: a missing import or a changed package API. The two files most
  likely to need a touch are `lib/features/map/osm_map.dart` and `lib/services/location_service.dart`.

## Part 5. Run it

```bash
flutter run
```
Use a **fresh install** (uninstall the app first, or *Clear storage*) the first time after
updating from an older version.

First launch: see Part 2b. Use a real password (8+ characters, letters and numbers).

## Part 6. Five-minute presentation script

1. **Citizen** (phone A or sign out/in): *Report*. Type "Big pothole in the middle of the road near the bus stand". Move to the location step: GPS, latitude/longitude and the address fill in. Go back, attach a photo, choose what the photo shows, then **Review**. Point at the **percentage and the key words**, and say it is a small model trained on examples. **Submit**.
2. **Second citizen** reports almost the same thing at the same spot. Show the message that both are now counted together.
3. **Officer** (Roads): the report is at the top of the queue. Open it: AI analysis card, priority reasons, deadline, lifecycle panel. **Accept** the assignment, move it **In progress**, add a **before** photo and an internal note.
4. **Administrator**: *Insights* tab: city summary, department performance, heat map, recurring faults, overdue list. Download the CSV. Show **Admin > Audit log**.
5. Officer resolves it with a note and an **after** photo. **Citizen** opens the report: before/after photos, rates it, taps **Yes, it is fixed**. The report closes.
6. Finish on **Home > City modules** to show all nine services on one database, and on the About screen's honest-status text.

Say clearly what is real and what is not (the guide's Part 10 is your cheat sheet). Judges notice honesty.

## Part 7. Build the APK

```bash
flutter build apk --release                  # one fat APK
flutter build apk --release --split-per-abi  # smaller per-CPU APKs (arm64-v8a is the one for most phones)
```
Result: `build/app/outputs/flutter-apk/app-release.apk`.

- **Install on a phone:** copy the APK over, open it, allow "install unknown apps". Or `flutter install`.
- **Signing.** Out of the box a release build is signed with the debug key. That installs fine for a
  hackathon. For the Play Store, create an upload keystore and follow
  https://docs.flutter.dev/deployment/android#sign-the-app. Keep the keystore and passwords out of Git.
- **App size** is mostly from bundled assets. The logo files are about 1 MB together.

## Part 8. The website

`website/` is a static, single-page site (no build step, no external libraries) using the same logo.

1. Open `website/index.html` in a browser to preview it.
2. Host it free: **GitHub Pages** (put the `website` folder contents in a repo, enable Pages), **Netlify** or **Cloudflare Pages** (drag the folder in).
3. Put the APK somewhere downloadable (for example a **GitHub Release**), then in `index.html` replace the two `href="#"` links in the "Get the app" section.
4. In the `<head>`, the social-card image path is relative. After you know your site URL, change `og:image` to the full address so link previews work.
5. The "Honest status" section on the page matches the app. Keep it accurate if you change features.

## Part 9. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `flutter doctor` red cross for Android licences | `flutter doctor --android-licenses`, answer `y` to all |
| Gradle or "SDK location not found" | Open the `android` folder once in Android Studio so it writes `local.properties`; check `flutter config --android-sdk` |
| Map is grey | No internet or the tile server refused the app. Check the `userAgentPackageName` change and connectivity; markers and the list still work |
| "Use my location" fails | Run `tools\fix_android.ps1`, then **uninstall and reinstall** the app (the permission lines only take effect on a fresh install). Allow location when asked ("While using the app"), switch Location on, and on Xiaomi/Redmi also set the app's Location permission to "Allow while using". Indoors, go near a window. On the emulator set a location in its extended controls. The message now names the real cause |
| Photo picker fails | Try a JPG/PNG under 5 MB. Photos over 5 MB are refused on purpose |
| Test errors about `sqlite3` | Linux: `sudo apt install libsqlite3-dev` |
| App asks to create an administrator again | You cleared app data or installed a new copy: data is local to each install |
| Fingerprint prompt never appears or the app crashes when it should | `MainActivity` must extend `FlutterFragmentActivity` and the phone needs a screen lock or fingerprint set up |
| Build error about `minSdkVersion` | Set `minSdk = 24` in `android/app/build.gradle(.kts)` (the script does this) |
| Vault says a document "could not be decrypted" | The file was damaged or the phone's secure key was reset (for example after a factory reset or uninstall). It cannot be recovered; delete it and upload again |
| "Open PDF" says no viewer | Install any PDF viewer (Google Drive, Adobe Reader, Files) or use *Save a copy* |
| Address shows "could not look up" | No internet, or the free OpenStreetMap service refused the request. Type the address yourself |
| Logo missing in the app | `assets/brand/` must be listed in `pubspec.yaml` (it is) and you must run `flutter pub get`; do a full restart, not hot reload |
| Icons did not change | Run `dart run flutter_launcher_icons` after `flutter create`, then uninstall and reinstall the app |

## Part 10. What is real and what is not (say this out loud)

**Real, working code:** local accounts and roles with checks in the repositories, separate citizen and administrator sign-in, optional app lock, a 3-step report wizard with GPS, reverse-geocoded address and photo, an AES-256 encrypted Document Vault, a Naive Bayes text classifier with probabilities, duplicate linking, explainable priority, department routing, assignment with accept/reject, deadlines and escalation, feedback and reopening, maps with groups and heat, performance numbers, CSV export, audit log, nine module views.

**Not real, and labelled so in the app:**
- The classifier is tiny and trained on examples written for this project. Its percentage is not a measured accuracy.
- Priority is a scoring rule, not machine learning.
- No image model is installed. A person says what a photo shows.
- Daily summaries and "maintenance insights" are templates and statistics, not AI predictions.
- Data lives on one device. There is no shared city backend, so two phones do not see each other's reports. (This is the largest gap against the full brief; see `docs/FIREBASE_FREE_TIER.md`.)
- No live sensors or feeds. Nothing is deployed anywhere.
- Not an emergency service.

## Part 11. What to build next (in this order)

1. Fix whatever Part 4 turns up.
2. **Local notifications** (`flutter_local_notifications`): free, works offline, fits the current single-device design.
3. **Photo model:** train an image classifier with Teachable Machine (free), export TFLite, add `tflite_flutter` (see `docs/IMAGE_MODEL.md`).
4. **Shared backend** so several phones work together: follow `docs/FIREBASE_FREE_TIER.md` (Auth and Firestore on the free Spark plan).
