# Mood Wink personality opportunities

Reviewed against the current app on 2026-09-22. These are proposals, not a record
of implemented changes. Existing behavior, labels, and recovery actions should
remain clear; the face is a supporting illustration.

| Existing place | Proposed expression | Use |
| --- | --- | --- |
| Moments: “The first moment could be yours” | Encouraging smile, bright open eyes | Invite the first shared dare. |
| Moments filtered to an empty mood | Thinking, raised eyebrow | Suggest another mood without implying an error. |
| Discover mood search and the feed mood-filter sheet | Thinking | Consistent meaning for “no matching moods”; use a smaller illustration in the sheet. |
| Profile: “Your story starts here” | Hopeful smile | Give an empty moments grid an inviting introduction. |
| Comments: “Start the conversation” | Talking face, small open mouth | Invite a first comment above the composer. |
| Followers/following: “No people here yet” | Friendly smile or waving face | Encourage connection; keep copy neutral on someone else's profile. A filtered list with no matches gets Thinking instead. |
| Post likes: “No likes to show yet” | Gentle smile with a tiny blush | Keep the tone welcoming, without making zero likes feel like a failure. |
| Successful post in the capture preview flow | Delighted smile with a small sparkle | A brief acknowledgement only after posting succeeds. No added navigation delay. |
| Profile stats and earned badges | Starry eyes | Celebrate “Your first moment,” “Making memories,” and “Spreading good energy.” Reserve celebration for earned badges. |
| Reset password: “Check your inbox” | Reassuring wink beside an envelope | Acknowledge the request while preserving the existing neutral account-existence wording. |
| Daring/Epic locked mood previews | Confident wink for Daring; starry eyes for Epic | Supporting tier artwork; retain the lock and “Coming soon” status. |
| Help & support landing content | Attentive face, slight head tilt | Add warmth without distracting from contact details and help actions. |

Implementation locations inspected:

- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/dares/presentation/screens/dares_screen.dart`
- `lib/features/feed/presentation/widgets/mood_filter_sheet.dart`
- `lib/features/profile/presentation/widgets/my_dares_grid.dart`
- `lib/features/feed/presentation/widgets/comments_sheet.dart`
- `lib/features/profile/presentation/screens/connections_screen.dart`
- `lib/features/feed/presentation/widgets/post_likes_sheet.dart`
- `lib/features/feed/presentation/screens/preview_screen.dart`
- `lib/features/profile/presentation/widgets/stats_and_badges.dart`
- `lib/features/auth/presentation/screens/forgot_password_screen.dart`
- `lib/features/dares/presentation/widgets/mood_preview.dart`
- `lib/features/settings/presentation/help_screen.dart`

Start with the empty feed, mood searches, empty profile, and comments; they have
clear space for a small illustration. Keep destructive confirmations, reporting,
blocking controls, and compact field-validation errors focused on their text
and functional icons. Do not replace loading progress with a no-results face.
