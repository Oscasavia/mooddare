# Account deletion and abandoned uploads

The app sends `requestAccountDeletion` after confirmation and recent reauthentication. The callable derives the target from the verified Firebase ID token and checks `expectedUid` to reject an account switch. No client can choose another account to erase.

Acceptance creates a private `accountDeletions/{uid}` job and an `accountRestrictions/{uid}` write barrier in one transaction. The phone clears account-scoped drafts/search history and signs out after acceptance. A server worker disables Authentication, revokes sessions, and performs checkpointed, repeatable cleanup. A ten-minute scheduler recovers interrupted workers; leases prevent concurrent workers from racing. Individual Auth deletions through older apps or the Firebase console also enqueue cleanup. Firebase bulk `deleteUsers` does not emit individual Auth deletion events: enqueue jobs explicitly if using a bulk administrative removal.

Cleanup includes:

- Own posts and all their comments/replies; own comments on other posts and their reply threads; own replies elsewhere.
- The user's IDs in post/comment/reply likes and reply mentions, including moderation archives. Other people's surviving text and likes are preserved.
- Saved dares, invitations in both directions, notifications, push tokens, username reservations, follows/followers/blocks (including broken legacy pairs), profile and nested profile documents.
- Reports involving deleted content/the account, the user's reports, related moderation archives/actions/reviews/locks, staff membership and restrictions.
- Posted, archived and unfinished media under the account's Storage prefixes, nested objects, and legacy avatar object names.
- The Firebase Authentication account, after the primary data/media cleanup succeeds.

A minimal deletion receipt and write barrier remain for two hours to outlive stale ID tokens and in-flight uploads. A final sweep removes late arrivals before deleting the receipt and barrier. The UI says deletion is requested and continues in the background; it does not claim instantaneous completion. An active session on another device observes deletion, clears its local drafts/history and signs out. Offline devices cannot be remotely erased; they are checked when they reconnect. Copies other people already downloaded are outside MoodDare's control.

## Storage recovery retention

The production bucket was inspected on 2026-10-01. It has **seven-day soft-delete recovery retention**. Deleting an object removes it from normal app/download access; Google retains its recoverable copy until that policy expires. The implementation does not change the bucket's recovery policy or claim immediate physical deletion from provider backups. No bucket versioning or retention lock was returned at inspection.

## Unfinished uploads

An hourly, paginated sweep considers only post media older than seven days. It preserves all published posts (including expired feed posts still shown on profiles) and moderation archives. For unreferenced media, a Firestore transaction first reserves the old post ID in `moderationPosts` with an `abandoned-upload` marker. Existing rules then prevent late publishing or overwriting that path. The worker deletes the inspected object generation. New clients follow the stable replacement post ID when retrying an old draft, preserving idempotency. Older clients must start a fresh post if their week-old unfinished upload has been reclaimed. Deleting an account also removes its replacement markers.

## Verification and operations

- Emulator suites: `npx --yes firebase-tools@14.14.0 emulators:exec --project demo-mooddare --only auth,firestore,storage 'npm --prefix tooling/rules-tests test && npm --prefix functions test'`.
- The deletion suite checks real Auth/Storage emulators, cross-account preservation, nested/orphan documents, archived references, delayed events, every checkpoint interruption, storage failure, leases, final-sweep recovery and request forgery.
- `integration_test/account_lifecycle_test.dart` is an explicit opt-in **live** two-account test. Run only on a disposable emulator with `--dart-define=RUN_LIVE_ACCOUNT_QA=true`. It creates synthetic QA accounts and requests their deletion in `finally`; synthetic UIDs are logged for cleanup if the device stops unexpectedly. Do not run integration runners on personal phones because Flutter reinstalls the app.
- Inspect pending/retry jobs and function errors after deployment. Errors in job documents are generic; no email, comment text or media URLs are stored there. Deploy required indexes before enabling cleanup. Jobs must not be manually deleted to hide a failure.

## Verification record — 2026-10-01

- 473 Flutter tests passed; 88.18% Dart line coverage; static analysis clean.
- 83 Firestore/Storage rules tests and 45 backend tests passed, with no skipped backend tests.
- Live Android emulator walkthrough passed using two separate authenticated Firebase app instances: persistent account-private draft, idempotent JPEG upload, shared-link resolution from the other account, mutual follows, post/comment likes, comments and replies to replies, saved/sent dare with duplicate suppression, received invitation/read state, real server-generated notifications and notification-to-profile route selection, then server account deletion with the surviving account intact.
- Independent administrator read-only audit checked all four synthetic accounts from both live test runs: no Auth account, public profile, live Storage objects, authored content, liker references, reply targets, invitation references, notification references or queried moderation references remained. All cleanup jobs reached `complete`; the two-hour receipt/barrier was intentionally retained. No real user account was deleted.
- Deployed all required indexes, rules and backend functions, including the Auth deletion trigger and recovery/orphan-upload schedules.
