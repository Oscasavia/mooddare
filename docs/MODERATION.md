# MoodDare community care

The private staff dashboard is `/admin/` on the MoodDare Firebase Hosting site.
It uses Google sign-in and a separate session scoped to that browser tab/session.
The approved initial account is oscasavia@gmail.com. No passwords or privileged
credentials are embedded in the website. Public visitors can load the login page;
all reports, previews and actions require a verified Google Firebase ID token,
revocation verification and enabled membership in server-only `moderationStaff`.
Mutations require sign-in within the last hour. Sign out/in when prompted.

## Review workflow

1. Open Reports, select a report and review the reason and content. Media loads
   only when requested. Search and status filters cover the currently loaded
   page(s); use Load more for older reports. Newest reports appear first.
2. Remove or restore content, dismiss the report, suspend its author for seven
   days, ban the account indefinitely, or lift its restriction. Every action
   requires a reason and confirmation. Staff cannot restrict themselves or other
   enabled staff accounts. User reports can restrict an account; content reports
   can additionally remove that particular post/comment/reply.
3. Action history records the initiating staff UID, action, reason, time and
   completion status. Failed/interrupted operations remain visible and can be
   retried. Do not assume a removal finished until its action says done.
4. Account restrictions display their reason and support/appeal email in the app.
   Account bans do not automatically remove every historical post: review those
   separately. Appeals are handled through support email in this first version.

There is no automatic ban based on report volume, permanent account erasure,
warning notification, automated image/video filtering or appeals dashboard in
this release. Those are separate follow-up work. Moderators must actually review
reports and respond promptly; this tool alone is not proof of App Store compliance.

## Enforcement and recovery

`accountRestrictions/{uid}` is writable only by the backend. Firestore and Storage
rules check restrictions for authenticated access, including existing ID tokens.
A ban is indefinite; suspension expiry is checked against server time. Refresh
tokens are revoked for restrictions. Authentication itself remains available so
users can see the restriction reason/support route. The app guard wraps the
navigator, covering an already-open camera or detail route; it releases expired
suspensions and reinstated accounts. Token unbinding remains allowed on sign-out.
Old app versions still encounter server permission denials.

Post removal privately archives its document, adds a server-only write lock,
deletes the public document and revokes the file's Firebase download tokens.
Storage rules prevent app SDK reads or overwrites of locked media. The full-screen
viewer listens for removal; feed/profile streams lose the removed document.
Comments/replies keep a text placeholder with original text and likes stored only
in the private archive. Removed text cannot be edited/liked from the app.

Restoration uses the archived data, retains original expiry/thread metadata, and
rotates the media download token. A restored expired post remains outside the
24-hour feed. Deleted accounts/comments or missing parent posts cannot be
resurrected through restoration. Previously downloaded/cached copies on other
people's devices cannot be remotely recalled. Existing content URLs are bearer
links; banning a user cannot erase links or copies they already received.

Operations use stable request IDs, transactional target locks and renewable-on-
retry processing leases. A retry resumes partial work without overwriting the
original archive or rotating an already-restored link. Firestore and Storage do
not share a transaction: failed media work is explicitly incomplete in History.
A permanently unrecoverable operation (for example an author deleting their
account during restoration) requires trusted operator review of its record and
lock; do not repeatedly retry without reviewing the cause.

Archive snapshots and action records are private and retained for review/appeals.
There is no automated archive purge in this release. Establish a bounded evidence
retention policy and trusted deletion tooling before a broad public launch; handle
account erasure requests that involve archived evidence through the support
process. Do not grant extra staff or expose evidence publicly to work around this.

## Deployment and access administration

Deploy `firebase.compat.json` while the existing profile migration gate remains.
It now includes Storage rules. Cross-service Storage rules require the Firebase
Storage service agent to read Firestore; the Firebase CLI checks this dependency.
Deploy the moderation API and rules before granting any staff record, because the
legacy compatibility allowance must first exclude all moderation collections.

```
npm ci --ignore-scripts --prefix tooling/admin
npm run build --prefix tooling/admin
firebase deploy --project mooddare --config firebase.compat.json --only firestore:rules,storage,functions:notifications:moderationApi
firebase deploy --project mooddare --config firebase.landing.json --only hosting
python3 tooling/moderation/grant-staff.py oscasavia@gmail.com
```

The grant script uses the project owner's saved Firebase CLI OAuth login; it
resolves exactly one verified existing Google account and never prints credentials.
Granting/revoking staff is deliberately not available in the browser dashboard.
To revoke access, trusted project administration sets that UID's staff `enabled`
field to false; the next API request is denied. Protect the Google account with
Google's two-step verification. No action is authorized by email text from the
browser or by editable public profile fields.

Dashboard code lives in `tooling/admin/`; the reproducible bundled assets are in
`website/admin/`. Hosting rewrites `/admin-api/**` to the authenticated API. Admin
HTML/JS/API responses use no-store, and the page is excluded from indexing. The
public marketing site retains its original policy; only admin routes permit the
Firebase Google sign-in dependencies. The dashboard does not initialize analytics.

## Validation

Backend tests cover access roles/recent authentication, self/staff protection,
malformed inputs, duplicate/concurrent requests, media failure recovery,
restoration retries, deleted-account protection and thread preservation. Rules
are tested in strict and compatibility modes, including direct SDK bypass attempts,
private evidence/staff records, banned sessions and removed media. Browser tests
use isolated authentication/API fixtures for the full UI workflow and unsafe-text
handling; they do not substitute for real Google popup acceptance. App tests cover
reporting, live removal, restrictions/reinstatement and narrow/large-text layouts.
Use Android integration tests on the emulator only, then rebuild the ordinary APK
and install on the personal phone with `adb install -r`.


## Deployment acceptance — 2026-09-29

The approved owner signed in through the real Google popup and confirmed that
reports workspace access works. Production admin assets return no-store and the
intended CSP; the unauthenticated reports API returns 401. The updated ordinary
APK was installed on Samsung in place after all six Android emulator checks.

Live acceptance also verified post removal, original download-token revocation,
restoration with a new working media link, and continued rejection of the original
link against production Firestore/Storage using isolated temporary content. All
test media, reports, archive and audit records were cleaned up. No real user post
was changed. The owner confirmed successful real Google dashboard sign-in.
