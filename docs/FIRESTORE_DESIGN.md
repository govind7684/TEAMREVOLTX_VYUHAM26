# Optional Firebase backend (design and draft rules)

**Status: design only. Nothing here has been deployed, run or tested.** The app
you have runs entirely on a local SQLite database. This document is the plan
for moving the same data model onto Firebase, behind the repository classes.

## Why this is not wired in yet

- The first requirement of this project was *zero cost, no credit card*. Cloud
  Firestore, Firebase Authentication and Cloud Messaging have free usage tiers,
  but **Cloud Functions need the pay-as-you-go (Blaze) plan**, which requires a
  billing account, and Cloud Storage availability on the free plan has changed.
  Check the current Firebase pricing page before you commit.
- A Firebase project must be created by you (`flutterfire configure`). The
  generated `firebase_options.dart` contains project identifiers, not secrets,
  but it ties the app to your account, so it is not included.
- Server-side authorization in Firebase lives in **Security Rules** and Cloud
  Functions. Rules below are a draft; they must be tested with the Firebase
  Emulator before use.

## Mapping from the current tables

| Local table | Firestore collection | Notes |
|---|---|---|
| `users` | `users/{uid}` | Auth is Firebase Auth. `role` and `departmentId` are set **only** by an admin (custom claims via a Function or the Admin SDK), never by the client. |
| `departments` | `departments/{id}` | `name`, `active`. |
| `users` (officers) | `officers/{uid}` | `departmentId`, `active`, `openCaseCount` (kept by a Function). |
| `incidents` | `incidents/{id}` | All incident fields incl. `aiConfidence`, `slaDueAt`, `escalationLevel`, `duplicateGroupId`. |
| `duplicate_of_id`, supporters | `duplicateGroups/{parentId}` | `parentId`, `childIds[]`, `supporterUids[]`, `reporterCount`. |
| `assignments` | `assignments/{id}` | `incidentId`, `officerId`, `state`, `reason`. |
| `status_history` | `incidentHistory/{id}` | Append-only. |
| `notifications` | `notifications/{id}` | Delivered also through FCM. |
| `feedback` | `feedback/{incidentId}` | One per incident. |
| analytics snapshot | `analytics/{yyyy-mm-dd}` | Written by a scheduled Function. |

## Draft security rules

See `firebase/firestore.rules`. Key rules: citizens read only their own
incidents; officers read their department's; admins read all; clients can never
write `role`, `priority*`, `slaDueAt`, `assignedOfficerId` or history; history
and audit are append-only; feedback only by the reporter after resolution.

## Cloud Functions you would need (not written)

1. `onIncidentCreate`: classify text, find duplicates, compute priority, route,
   set SLA, write history. (Server-side so clients cannot forge priority.)
2. `scheduledEscalation` (every hour): escalate overdue incidents.
3. `onStatusChange`: notify reporter and linked reporters through FCM.
4. `setRole` (callable, admin only): sets custom claims.

The classifier would need to run server-side (for example a Python function
using the same training sample, or a hosted model). Running the Naive Bayes in
Dart on a device is fine for the app; **authoritative** values must come from
the server.

## Migration plan

1. Define abstract repository interfaces matching the current classes.
2. Add Firestore implementations next to the SQLite ones.
3. Choose the implementation in `providers.dart` by a build flag.
4. Keep SQLite as the offline/demo mode.
