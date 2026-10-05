# Admin analytics

The staff-only Analytics tab loads `/admin-api/analytics?days=7|30` through the
same verified Google identity and enabled `moderationStaff` authorization as the
moderation tools. Browser clients cannot read or write analytics Firestore
collections directly. The portal receives aggregates, never user identifiers,
post text, email addresses, media, or private For you history.

## What the numbers mean

| Metric | Definition |
| --- | --- |
| Mood selections | Explicit opening of an available mood in Discover, signed in, in the updated app. Previews, rebuilds and filter changes do not count. Best effort online delivery; offline events are not replayed. |
| Signups | New `users/{uid}` profile creations after tracking began, counted once per Firestore creation event. This includes guest/legacy profiles if created; it is not a count of logins or verified emails. |
| Account deletions | Registered Firebase Auth accounts deleted after tracking began, including administrator removals. Anonymous Auth cleanup does not count. Auth removal is distinct from completion of the later cleanup sweep. |
| Current profiles | All existing Firestore profiles now, independent of the selected date range. Includes guest and staff profiles. |
| Published moments | Existing, non-deleting posts created within the selected range. |
| Unique creators | Distinct authors of those posts. |
| Likes on these moments | Current distinct likes per post, summed across those posts. Not the number of like events during the selected range. |
| Community participants | Distinct authors of existing posts with a stable `weeklyDareId`, deduplicated across all dares. Publishing is not proof of physically completing a dare. |
| Community moments | Existing posts linked to a weekly dare. |

Staff and test accounts are included; there is no inferred exclusion. Existing
content provides historical context, but content totals decrease when posts or
accounts are removed. Restoration returns a post to its original creation-date
period. Each row includes a currently available mood even if its selection count
is zero. Retired moods with recorded selections remain visible. Weekly dares
whose schedule overlaps the range appear even with zero participants.

Ranges are exactly 7 or 30 UTC calendar days including today's partial day.
`analyticsConfig/current.startedAt` marks the collection boundary. Mood selections,
signups and deletions have no invented historical backfill. The UI displays this
coverage and its limitations. Updated Android/iOS clients are needed for mood
selection counts; server metrics also work with older clients.

## Collection and retention

`recordMoodSelection` accepts only `eventId` and `moodId`, validates the server
catalog, authenticated non-anonymous membership, account restrictions and pending
deletion. In one transaction it checks the receipt/rate limit, writes a receipt,
and increments the anonymous daily mood total. Duplicate event IDs count once;
limit is one selection per two seconds and at most 500 per account per UTC day.
These limits mean counts describe accepted selections, not every rapid tap.
Analytics errors never block navigation. No offline queue is created.

Account-linked receipts contain only an expiry; the rate record contains daily
count and last receipt time, not a mood. They live below `users/{uid}` and expire
after 32 days. The existing recursive account-deletion stage removes them without
changing deletion checkpoint indices. Daily cleanup removes expired receipts and
rate records. Lifecycle event receipts use hashed Cloud event IDs (no UID), expire
after 90 days, and prevent duplicate trigger delivery. Daily aggregate totals
contain no account identifiers and are retained after account deletion. Privacy
copy in the app and website describes this first-party collection.

## Snapshot contract

Version 2 retains version 1's `status`, `rangeDays`, `generatedAt`, `startDate`,
`endDate`, `moods:[{id,name,selections}]` and
`communityDares:[{id,title,participants,moments}]`. It adds ISO
`trackingStartedAt` and metrics `signups`, `accountDeletions`, `currentProfiles`,
`posts`, `creators`, `likes` alongside `moodSelections`, `communityParticipants`,
`communityMoments`. Counts must be nonnegative safe integers; sums, distinct
participant bounds, coverage and date ranges are validated before rendering.
Version 1 remains accepted for older fixtures, with unavailable new metrics shown
as dashes. Not-configured, loading, unavailable and measured zero remain distinct.

The endpoint counts profiles using Firestore count aggregation and reads only
required fields of recent posts, overlapping weekly schedules, catalog and daily
aggregate documents. It refuses to present truncated results beyond 20,000 posts
or schedules or 500 display rows. Before that scale, move content calculations
to scheduled rollups with explicit refresh timestamps. Current results reflect
separate live reads, not a single transactionally frozen database snapshot.

## Operations

Deploy `moderationApi`, `recordMoodSelection`, `countNewProfile`,
`eraseDeletedAuthAccount` and `expireAnalyticsReceipts`, plus the analytics
collection-group expiry indexes. Refresh the Firebase CLI login if needed, then:

```sh
node tooling/analytics/manage.cjs --enable
node tooling/analytics/manage.cjs
npm run build --prefix tooling/admin
npm test --prefix tooling/admin
```

Enable creates the collection boundary once; it never resets counters. Run only
with the project owner's credentials. The helper prints aggregates only. The
source module unit/emulator tests cover authorization inputs, restrictions,
duplicates, rate limits, lifecycle coverage, deletion, counts and catalog zeros.
Rules tests verify both rule files deny client access. Browser tests cover both
contract versions, coverage, mobile layout, desktop-only sign-out padding,
loading/failure and stale requests. Flutter tests verify explicit instrumentation
and failure isolation. No production fake events are used for smoke tests.
