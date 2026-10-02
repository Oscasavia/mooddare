# Personalized Moments — first version

For you ranks a bounded pool of the latest 120 unexpired posts (within the selected mood, when filtered). This is an explainable weighted recommender, not a trained machine-learning model or an engagement guarantee. Candidate retrieval still favors recent activity; a larger community will need paginated and interest-specific candidate sources before this can offer broad catalog discovery.

The default mixes freshness, mood affinity, creator affinity, followed accounts and exploration. A qualified view contributes 0.4, video completion 0.8, a like 3, a saved dare 4, and Not interested -5. Signals are booleans per post, so repeated taps, retries and loops do not accumulate unbounded scores; unlike removes that contribution. Interest decays with a seven-day half-life. Creator and mood contributions are capped, recent creator repetition is penalized, and every fifth position prefers a fresh unseen post. No popularity count determines ranking. This does not infer a person's mental health from a selected mood.

Learning occurs only on For you, for other members' posts. Photos require five seconds of visible loaded media. Videos require advancing playback, excluding buffering, seeks, paused/background time, covered routes and modal overlays. Completion requires reaching 85% of the timeline with at least 65% of the duration counted as playback. Full-screen viewing uses the same callback and per-post deduplication. Likes and saves record only after their real action succeeds. This first version does not collect comments, external shares, camera imagery, microphone data, or face geometry for recommendations.

Private storage:

- `users/{uid}/feedHistory/{postId}` contains author/mood IDs, bounded boolean signals, server update time and expiry. Rules validate the referenced post and ownership; other users cannot read or modify it. History does not affect public counts or other members' ranking.
- `users/{uid}/preferences/feed` stores `forYou` or `latest`. Latest pauses new activity learning. Reset deletes all private history, including older pages, without deleting likes, follows or saved dares.
- Ranking loads at most the most recent 200 records. Records older than 30 days are ignored immediately and physically removed by daily cleanup. Account deletion removes the owner's history and references to the deleted author in other histories.

Order stays stable during a browsing session; engagement snapshots and arriving posts do not reshuffle the current card. Refresh, mood changes or ordering changes create a new ranking. Deleted/expired/blocked/rejected posts disappear immediately and the current surviving post remains anchored. Read or write failures in recommendation storage do not prevent normal posting, viewing or liking; unavailable preference loading falls back to fresh moments after eight seconds.

The filter menu contains For you, Latest, Reset feed preferences and existing searchable moods. There are no new feed overlays or disruptive onboarding prompts.

Tests cover ranking cold starts, affinity, diversity, exploration, expiry, account isolation, repeated activity, unlike, learning opt-out, history bounds, reset, rules abuse, deletion cleanup, background/modal/stalled-video exclusions, seek handling, full-screen feedback, stable paging and existing feed gestures. Future work: tune with consenting testers, add successful comment/try-dare signals if useful, paginate retrieval, and measure recommendation quality without optimizing solely for watch time.
