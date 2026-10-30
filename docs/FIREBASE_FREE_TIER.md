# Firebase on the free plan: how the next stage will work

**Status: Stage A (accounts) is written but not compiled or run – see FIREBASE_SETUP.md. Stage B (report sync) is plan only.** The app today stores everything
on the phone. This document is what you and I do next so that several phones share accounts and
reports, without paying or adding a card.

## What the free Spark plan gives (check the Firebase pricing page for current limits)

| Service | Free (Spark) | Used for |
|---|---|---|
| Authentication (email/password) | yes | Citizen and administrator sign-in, password-reset email, email verification |
| Cloud Firestore | yes, with daily read/write and 1 GiB storage quotas | Users, reports, status history, notifications, city updates, flood readings |
| Cloud Messaging (FCM) | yes | Push notifications **can be received**, but sending from your own logic needs a server |
| Cloud Storage | **not on Spark for new projects** (needs Blaze) | Not used |
| Cloud Functions | **Blaze only** | Not used |

So the brief's Storage and Functions items cannot be done without a billing account. The design
works around that:

- **Document Vault stays on the phone**, encrypted (AES-256-GCM, key in the Android Keystore).
  That is also the safer choice for ID documents: they never leave the device. The cost is that
  vault documents do not follow a person to a new phone.
- **Report photos** stay on the phone for now. Options later: shrink them and store a small
  thumbnail as text in Firestore (1 MiB document limit), or move to a free third-party host.
- **Notifications** become Firestore documents that the app listens to live. That gives in-app
  real-time updates while the app is open. True background push needs a sender (Cloud Functions or
  your own server), which is outside the free plan.
- **Server-side jobs** (deadline escalation, auto-close) keep running on the staff device when it
  is open, as today, because there is no scheduler on Spark.

## What you do (about 15 minutes, no card)

1. Go to <https://console.firebase.google.com>, **Add project**, name it `civinex-ai`. Turn Google
   Analytics off. Stay on the **Spark** plan.
2. **Build > Authentication > Get started > Email/Password > Enable.**
3. **Build > Firestore Database > Create database.** Choose a location near you (for example
   `asia-south1`, Mumbai) and **production mode**. Rules come next.
4. **Project settings > Your apps > Add app > Android.** Package name = the `applicationId` you set
   (Part 2, step 4 of `SETUP_GUIDE.md`). Download **`google-services.json`** and send it to me, or
   put it in `android/app/` yourself. It holds project identifiers, not passwords.
5. Create the **first administrator by hand**: Authentication > Users > **Add user** (email and
   password). Copy that user's UID. In Firestore create `users/<UID>` with
   `{ name, email, role: "admin", active: true, createdAt }`. Nobody can make themselves an
   administrator from the app, because the rules below forbid a client from writing `role`.
6. Install the Firebase CLI later only if you want to publish rules from the terminal; pasting the
   rules into the console (Firestore > Rules) works too.

## What changes in the app

The repositories (`AuthRepository`, `IncidentRepository`, `WorkflowRepository`, …) are the only code
that touches the database, so the screens do not change.

- **Sign-in:** `firebase_auth` replaces the local password check. The two entrances stay: after
  signing in, the app reads `users/{uid}` and refuses the wrong audience exactly as it does now.
  Firebase keeps the user signed in across restarts, which replaces `FileSessionStore`.
- **Forgot password and verification** become real: `sendPasswordResetEmail`,
  `sendEmailVerification`.
- **Roles** live in `users/{uid}.role` and `departmentId`. Only an administrator may write them.
- **Staff accounts:** an administrator creating an officer must not be signed out. This is done
  with a second `FirebaseApp` instance used only to create the account, then writing the
  `users/{uid}` document.
- **Data:** each SQLite table becomes a collection (mapping in `FIRESTORE_DESIGN.md`). Queries that
  join several tables (priority queue, analytics) are done in the app after fetching, which is fine
  at hackathon scale and has to be revisited for a real city.
- **Security rules:** drafted in `firebase/firestore.rules` (adapted so roles are read from `users/{uid}` instead of custom claims, which need Functions; the other collections' rules were not re-reviewed after that change). They must be tested with the Firebase
  Emulator before you trust them. I cannot run the emulator here.

## Honest limits of this plan

- Free-plan quotas are daily; a busy deployment could hit them.
- Without Functions, rules cannot enforce every business rule (for example "only the assigned
  officer may resolve"). Some checks will stay in the app, so a determined staff member with a
  modified app could do more than intended. Rules still protect citizens' data from other citizens.
- No background push while the app is closed.
- Account recovery for ID documents is impossible by design; the originals must be kept by the
  citizen.

## Order of work

1. You create the project and send `google-services.json`.
2. I add `firebase_core`, `firebase_auth`, `cloud_firestore`, and a Firebase implementation of
   `AuthRepository`, keeping the local one for tests.
3. Move incidents, then notifications and city updates, then flood readings.
4. Test rules in the emulator; only then use real data.
