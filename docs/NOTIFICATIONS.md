# Activity inbox and phone alerts

Android is the first delivery target. The bell on Moments opens a live inbox with
All/Unread, a read-all action, current usernames/avatars, relative timestamps and
links to profiles, moments/comments and the dare inbox. Notification settings are
also available from Settings. Categories apply to new activity; phone alerts can
be disabled independently of the inbox. Tap **Enable on this device** to request
OS permission. No permission prompt is shown during sign-in or camera use.

## Server events and data

Cloud Functions in `functions/` derive follows, post likes, comments, replies,
comment/reply likes and received dares from their existing Firestore documents.
There is no client notification creation API. Sources, account existence, both
block directions and category preferences are checked transactionally. A reply
alerts the addressed person and root commenter once each, excluding its author.
Stable event IDs suppress duplicate retries and repeated like/follow toggles.
No previous activity is backfilled when enabling the feature.

Inbox entries contain IDs, kind, timestamps and read state, not copies of comment
text or private account details. Post expiry removes a moment from the feed, not
its profile or notification destination. Deleted content has an unavailable state.
An inbox entry lasts up to 30 days, with daily cleanup. Blocks clear both sides'
existing activity entries. User deletion clears incoming entries and entries the
user generated elsewhere. Device registrations inactive for 60 days are removed.

Phone alerts use FCM notification payloads, the Mood-wink monochrome Android icon,
and the `mooddare_activity` channel. Lock-screen text is generic (no comment text).
The inbox is durable; push delivery is best-effort and claimed once before sending
because FCM does not offer exactly-once delivery. Foreground alerts are in-app
banners. Taps resolve an inbox ID for the currently signed-in recipient; external
URLs from payloads are never opened. Invalid registrations are removed.

A secret FCM registration token has one global account binding. Clients cannot
read/list tokens. Refresh replaces old bindings; sign-out unbinds before clearing
auth, with FCM token invalidation as fallback. The client retries registration on
app resume. Token permissions are tested in strict and compatibility rule files;
legacy wildcards explicitly exclude all notification collections.

## Deploy and verification

Use `firebase.compat.json` until the existing profile migration is complete:

```
firebase deploy --project mooddare --config firebase.compat.json --only firestore,functions:notifications --force
```

The force flag acknowledges retries for idempotent event functions. It must not be
used to approve unrelated resource deletions. Functions use Node 22, us-central1,
256 MiB, no warm minimum, and at most 3 instances per function. Cloud Functions,
Eventarc, FCM and the daily Scheduler require the corresponding project APIs and
billing. No public unauthenticated send endpoint is deployed.

Automated checks cover rules, backend transactions/concurrent replay, push payloads
and token cleanup, inbox/settings widgets, permission denial, cold/background/
foreground tap routing, token rotation and sign-out. Use the Android emulator for
integration tests; never use the Flutter integration runner on the personal phone
because it uninstalls the app. Rebuild the ordinary APK afterward and install with
`adb install -r` to retain data.

## Backlog: Apple push delivery

User chose Android first on 2026-09-29 because their Apple Developer membership
has expired. Renew membership, enable Push Notifications for the app's final
bundle ID, generate/upload an APNs authentication key in Firebase, and refresh
provisioning profiles. iOS entitlement/background capability groundwork is present;
it is **not evidence of working iPhone delivery**. Test development and TestFlight
builds, permission denial, foreground/background/terminated taps, token changes,
sign-out and multiple devices on physical iPhones before claiming support.

## Remaining device acceptance

Samsung background delivery and the Mood-wink status icon were confirmed by the
user on 2026-09-29 using a clearly labeled FCM test alert. Backend event and
recipient routing are emulator-tested. Continue multi-account physical acceptance
for taps into each activity type. Device-level Do Not Disturb, revoked
permissions, offline delivery and OS force-stop can suppress or delay alerts.

Deployment acceptance also verified an isolated follow event through production
Eventarc/Cloud Functions into the correct private inbox. Temporary test profiles,
follow documents and notification entries were removed after the check.
