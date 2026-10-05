# App and website analytics

Analytics has separate App and Website sections. Each remembers its own 7/30-day UTC range. App activity defaults to Production; Development & staff is a separate filter. The expandable earlier-tracking section uses the previous all-account, existing-content calculations and is explicitly labeled.

## New app measurements

- Daily/weekly/monthly active members: distinct signed-in members observed today / the last 7 / last 30 UTC days. Foreground activity is sampled on sign-in, resume and every five minutes, plus tracked feature actions. These windows do not change with the report range.
- Returning members: exact D1, D7 and D30 return rates, starting on first observation (including existing members), not installation. Each rate uses the selected number of fully observed eligible cohorts, offset by the return day. An immature cohort is excluded, not reported as zero retention.
- Registration attempts, successful registrations, login attempts/completions/failures, first profile setup, mood selection, dare views/shuffles, camera openings, posting attempts/success/failure and duration. First-step counters deduplicate member milestones; event totals are not a matched-user conversion funnel. Registration success depends on the updated client successfully reporting the completed registration.
- Published moments: server-side creation events counted once per post ID, including posts later deleted or moderated. Restoring the same post does not add a publication. Likes count additions, including an unlike followed by another like.
- Account deletions: registered Firebase Auth deletion events, including administrator removals. The deletion job retains the environment classification before erasing account state. This measures Auth removal, not completion of every cleanup stage.
- Shares: share-sheet openings, successful native share actions, and unavailable confirmation results. Only native success increments the server-owned public post share counter. Dismissal does not. This is not proof of message delivery or recipient views. Numeric like/comment/share counts hide at zero; action buttons remain visible.
- Reliability: upload/auth failure categories and app errors by platform/version, plus mean posting duration and attempts lasting at least ten seconds. Posting duration includes export and upload. Release crash traces are sent to Firebase Crashlytics, without deliberately setting account IDs or adding user content; debug collection is disabled.

New app events retain their original ID, timestamp, environment, version, platform and session in a bounded on-device queue (200 events, seven days). Only events belonging to the currently signed-in account are delivered; the server verifies the expected UID again. Anonymous sign-in attempts use a separate session scope. Permanent post/account restrictions are acknowledged without counting; temporary failures retry on subsequent events/resume. This is best-effort telemetry: disabled connectivity, a full/expired queue, unsupported old clients and uninstallation can lose data.

## Website measurements

First-party `/website-metrics` receives normalized page views, internal navigation, active store-download links, contact clicks, mood-demo interactions, screenshot openings, FAQ openings and video milestones. It excludes query strings, referrers, arbitrary links and individual moment IDs. It honors Do Not Track and Global Privacy Control. No advertising SDK or cross-site identifier is used.

Sessions are random browser-tab IDs stored in sessionStorage, not verified unique people. New sessions count on first observation. Requests are bounded and rate-limited; automated clients can still influence public telemetry. Events queue in memory for at most 24 hours, flush periodically/on backgrounding with keepalive and reuse IDs on retries; closing a tab while offline can lose events.

Video starts, 25/50/75% coverage, completion and errors deduplicate per tab session and video version. Coverage counts distinct played segments while visible; seeks and replays do not inflate coverage. Completion requires ending after at least 90% coverage. Portrait and landscape cuts of the same creative share one version.

When replacing a promo film, change `release.promoVideoId` in `website/config.js` and add the new ID to `analyticsConfig/current.webVideoIds` before deployment. Keep old IDs in the registry for cached pages; old aggregates stay separate. The initial ID is `launch-2026-10`.

## Storage, access and operation

The staff-only `/admin-api/analytics?days=7|30&environment=production|development` requires verified Google authentication and enabled `moderationStaff`, just like moderation. Firestore rules deny direct client access to all metric collections and writes to `posts.shareCount`. The portal receives aggregates, not account IDs or post content.

`analyticsConfig/current.productStartedAt` defines the new collection boundary; never reset it. `node tooling/analytics/manage.cjs --enable-product` initializes it once, creates a private rotating-IP-hash salt, and registers the initial video version. Existing legacy `startedAt` stays intact. Do not log the salt or OAuth tokens.

New stores: `productDaily`, `productCohorts`, `websiteDaily`, `analyticsPresence`, `analyticsVisits`, `analyticsTraffic`, `analyticsPublications`, plus account-scoped `users/{uid}/productMetrics` and receipts. Enabled `moderationStaff` or `analyticsExclusions/{uid}` routes incoming activity to development; release/debug build metadata also separates traffic. Exclusion is evaluated at receipt time, not retroactively. Post environment metadata classifies publication and likes; staff exclusions additionally apply to the actor. Older posts without metadata default to production.

Account-scoped state is erased with the account. Random-key presence summaries retain only environment/activity dates, expire after 35 days, and lose their account-to-key mapping on deletion. Daily aggregates remain; per-post publication hashes remain to prevent a later restore inflating historical totals. Receipt cleanup uses the existing 32/90-day jobs; anonymous app-attempt session receipts expire after nine days (longer than the offline queue); website session/rate-limit records expire after two days and the product cleanup job runs daily. IP buckets rotate every 15 minutes; raw IPs are not stored in analytics documents (infrastructure logs have their own retention).

Capacity is intentionally bounded: at most 2000 member events per UTC day, 500 events per public session receipt, 600 public batches per 15-minute network bucket, 20 events per request. Active-user reads cap at 20,000 presence documents per environment and fail visibly above that threshold instead of truncating totals. Plan a scheduled rollup/warehouse before approaching that scale. Raw infrastructure/Crashlytics costs and retention are managed in Firebase.

App changes require an updated installed build. Website changes start after Hosting deployment. New events cannot reconstruct activity before instrumentation. Test fixtures and emulator traffic never go to production.

## Earlier tracking definitions

### Legacy metrics

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
