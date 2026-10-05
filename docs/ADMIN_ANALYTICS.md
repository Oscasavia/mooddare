# Admin analytics integration

The admin portal has a responsive Analytics view with 7-day and 30-day ranges,
selection totals, sortable mood bars (most/least selected), and participation by
community dare. The current production adapter returns `not-connected`.
**This change does not collect events, enable Firebase Analytics, or deploy an
analytics API.** Empty placeholders are not measured zeros. Connected examples
exist only in browser-test fixtures, never in the production bundle.

## Integration boundary

`tooling/admin/analytics-source.js` exports `loadAnalytics({rangeDays, api})`.
Replace its stub with a call through the injected authenticated API client once a
server-side aggregate pipeline is available. For example, a future
`analytics?days=30` route could return the contract below. That route does not
exist today. It must enforce the same enabled staff membership as moderation
routes, independently of whether the navigation is visible. Do not query raw
user activity directly from the browser or trust client-provided aggregate totals.

The view module validates version, date range, nonnegative integer counts,
unique IDs and consistent totals before rendering. Loading, unavailable,
not-connected and measured-zero states are distinct. Requests are invalidated
on view changes, range changes and sign-out. The production portal initializes
Firebase Auth only; it does not initialize an analytics SDK.

## Snapshot contract, version 1

This is an illustrative schema example, not live MoodDare activity:

```json
{
  "status": "ready",
  "schemaVersion": 1,
  "rangeDays": 7,
  "generatedAt": "2026-10-05T12:00:00Z",
  "startDate": "2026-09-29T00:00:00Z",
  "endDate": "2026-10-06T00:00:00Z",
  "metrics": {
    "moodSelections": 12,
    "communityParticipants": 3,
    "communityMoments": 4
  },
  "moods": [
    {"id": "creative", "name": "Creative", "selections": 12},
    {"id": "chill", "name": "Chill", "selections": 0}
  ],
  "communityDares": [
    {"id": "stable-week-id", "title": "An illustrative dare", "participants": 3, "moments": 4}
  ]
}
```

- `startDate` is inclusive and `endDate` exclusive, both UTC. Return exactly
  `rangeDays` calendar days, including the current partial UTC day. `generatedAt`
  is the time the aggregate was produced. A historical or partial collection
  window must not be presented as a complete period; extend the versioned contract
  with coverage metadata before enabling such reporting.
- Include all moods available in the period, including zero-selection moods.
  Omitting zero rows makes “least selected” misleading. The sum of the mood rows
  must equal `metrics.moodSelections`.
- Include community dares available in the period, including zero-participation
  dares. `moments` counts qualifying published posts in the period.
- `participants` is distinct authors per dare within the period. The total
  `communityParticipants` is distinct authors across all listed dares, not the
  sum of those rows. `communityMoments` equals the sum of per-dare moments.
- Return complete aggregate lists, at most 500 rows of each kind. This UI does
  not support truncated or paginated analytics snapshots; add explicit paging
  and completeness information before exceeding that bound.
- Return `{ "status": "not-connected" }` when collection is not configured.
  Once collection is working, zero counts are actual measurements. Errors must
  reject the request, not silently return zeros or stale data as fresh.

## Future collection plan

| Signal | When it happens | Identity and counting |
| --- | --- | --- |
| `mood_selected` | A person explicitly selects a mood in Discover | Stable event ID per interaction, stable mood ID, server receipt time; deduplicate network retries. Do not count screen rebuilds, default selections or Moments filters. |
| `community_dare_started` | A person explicitly begins a community dare | Stable event ID and weekly dare ID; useful for a later start-to-publish funnel, not yet displayed as participation. |
| `community_moment_published` | Backend confirms a new post for a valid community dare | Deduplicate by post ID; count distinct authenticated authors for participants. Failed uploads, retries and edits must not count as new participation. |

The app already associates community posts with `weeklyDareId`; use that stable
relationship rather than matching displayed prompt text. Count published
participation honestly: posting does not independently prove a person physically
completed a dare. Mood selection is a choice in the app, not an inferred health
or emotional condition.

Before collection, decide and implement the event retention period, deletion
behavior, consent/opt-out handling and appropriate privacy/store disclosures.
Keep raw event records restricted; return only aggregates to the portal. Avoid
free-text comments, report contents, photos, email addresses or device advertising
IDs in analytics events. Prefer an authenticated server-side identity for distinct
counts, and exclude owner/test accounts from production metrics through an
explicit server-side rule. Define how removed posts, deleted accounts, late
arrivals and historical corrections affect aggregates; recompute consistently
rather than decrementing counters ad hoc.

Do not reuse private For you preference history as a general analytics source.
Its purpose, collection rules and lifetime are different. Moderation counts are
also separate: portal queue summaries cover only loaded reports/actions and are
not global community metrics.

## Verification

Run from the repository root:

```sh
npm run build --prefix tooling/admin
node --test tooling/admin/analytics.test.mjs tooling/admin/browser.test.mjs
```

Browser fixtures cover disconnected, connected, empty, zero, invalid, error and
recovery states; sorting; period changes; mobile layout; unsafe labels; and
responses arriving after navigation or sign-out. Fixture screenshots are written
to ignored `test-results/admin/`, with `fixture` in connected-analytics filenames.
