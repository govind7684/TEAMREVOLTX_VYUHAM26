# Firebase (Stage A accounts + Stage B report sync): what is built and what you do

**Built but not compiled or run by me.** Stage A moves *accounts* to Firebase (free Spark plan).
Reports, photos, notifications and the Document Vault stay on each phone. Reports are **not** shared
between phones until Stage B.

## What Stage A gives
- Real email + password accounts in Firebase Authentication; sign in on any phone.
- Forgot password: an emailed reset link (login screens).
- Email verification: sent at citizen sign-up; resend/check under More → Settings.
- Roles (citizen / officer / administrator), department and active flag live in Firestore `users/{uid}`.
- An administrator adds officers/admins in the app (they stay signed in), disables accounts, changes
  roles, and can email a reset link to someone.
- If `google-services.json` is missing or Firebase cannot start, the app falls back to the old
  on-phone accounts. Nothing else changes.

## Console steps (all free; if anything asks for a card or "Upgrade to Blaze", stop)
1. **Authentication → Sign-in method → Email/Password → Enable.**
2. **Firestore Database → Create database** → location `asia-south1` → production mode.
3. **Firestore → Rules** → paste `firebase/firestore.rules` → Publish.
4. **First administrator** (the app never offers admin setup in cloud mode):
   - Authentication → Users → Add user (email + password, 8+ chars, letters and numbers).
   - Copy that user's **UID**.
   - Firestore → Start collection `users` → Document ID = the UID → fields:
     `name` (string), `email` (string, same email, lowercase), `role` = `admin` (string), `active` = true (boolean).

## On your PC
1. Unzip over `C:\Users\AJAYAKUMAR\civinex_ai`.
2. Put `google-services.json` in the project folder (or `android\app\`).
3. `powershell -ExecutionPolicy Bypass -File tools\fix_android.ps1` – sets `applicationId` to
   `com.civinex.civinex_ai`, adds the Google services Gradle plugin, copies the JSON.
4. Uninstall the old app from the phone, then `flutter clean`, `flutter pub get`, `flutter analyze`,
   `flutter test`, `flutter run`.

If the Gradle step reports it could not edit `settings.gradle.kts`, add inside `plugins { }`:
`id("com.google.gms.google-services") version "4.5.0" apply false`, and in
`android/app/build.gradle.kts` `plugins { }`: `id("com.google.gms.google-services")`.

## Known limits
- Sign-in needs internet. A session stays signed in offline.
- Staff list/officer picker shows people the phone has seen or can fetch; offline it uses the last copy.
- Disabling an account takes effect at that person's next sign-in or app start (no push revoke).
- Passwords are checked by Firebase; the app stores none for cloud accounts.
- `firebase/firestore.stageB.draft.rules` is the unreviewed draft for report sync.


## Stage B: reports shared between phones
**Built, not compiled or run by me.** After you re-publish `firebase/firestore.rules` (it now covers
reports) the phones share, through Firestore:
- reports with their history, assignments, supporters and feedback (citizen: own reports; officer: own
  department; administrator: all)
- staff-only notes and resource requests, notifications, city updates, and the services directory

Stays on each phone: photos (other phones see the report without the photo), the Document Vault,
RoadVision repair photos and road details, FloodGuard readings.

How conflicts work: reports are merged, not overwritten. History lines, notes, assignments, supporters and
resource requests from both phones are combined; plain fields (status, priority) come from the newer copy.
City updates and services are last-write-wins.

Merging reports: a new report that matches an older one (same category, close location, similar text) is
linked automatically on the administrator phone and marked awaiting confirmation. In a report's staff tools,
staff can Confirm, Unlink, or Merge into another report by hand.

Automatic routing: runs on an administrator's phone while the app is open (and on a timer after each
change). Switch on the admin dashboard. If no administrator phone is open, new reports wait.

Limits to expect: Nearby and duplicate detection on a citizen phone only see that citizen's own synced
reports. Uploads happen about 2 s after a change and every 25 s; downloads are live. Needs internet.
Free-plan quotas apply; a demo with three phones is far below them.

### Re-publish the rules
Firebase console > Firestore Database > Rules > replace everything with `firebase/firestore.rules` > Publish.
Also, officers' accounts need `departmentId` in `users/{uid}` (the app writes it when an administrator
creates or promotes an officer).

### Services directory
Anyone can search a city (OpenStreetMap, free, may be incomplete). An administrator allots an officer with
Manage > Users > Allot services access; that officer (or an administrator) adds or corrects places under
City services > Manage. Staff places are marked and shown first.
