# Membership design and rollout

Status: development prototype, September 29, 2026. No store products, prices,
purchase SDK, billing backend or paid entitlements have been implemented.

## Review the prototype

Build with `flutter build apk --debug --target-platform android-arm64
--dart-define=MOODDARE_MEMBERSHIP_PREVIEW=true` (one command). Open Settings →
Membership preview, or open a locked mood and select Preview membership ideas.
Select Free/Daring/Epic and Monthly/Yearly. These choices are temporary UI state;
they cannot charge, persist a subscription, or unlock a mood or camera lens.

The flag defaults to false. Both entry points also require `kDebugMode`, so even
an opted-in release/profile build cannot show them. Ordinary builds sent to
friends should omit the flag. There is no public named route to the prototype.
Keep billing unavailability visible in any development screenshots or demos.

## Proposed benefits, subject to validation

| Plan | Proposed value |
| --- | --- |
| Free | Everyday/seasonal moods, weekly community dare, current lenses (including Golden Hour and current AR), My look, saved dares, core social features |
| Daring | Free plus Daring mood collections, regular new Daring dares and a future exclusive beauty-lens collection |
| Epic | Daring plus Epic mood collections, regular new Epic dares, future AR collections and additional profile color collections |

These are concepts, not shipped features or launch commitments. Existing camera
controls, lens definitions, favorites, custom-look settings, profiles, community
features and premium-lock behavior are untouched. New premium lenses must add
something distinct rather than silently converting existing free favorites.
Do not imply premium beauty means people need to fix their appearance. Keep
helpful everyday/wellbeing dares free; make creative variety the premium value.

Start with monthly and yearly billing if/when subscriptions launch. No numeric
prices, fabricated discounts, trials, “best value” or popularity claims yet.
A yearly plan would be one yearly payment, not a monthly instalment plan.
Weekly, quarterly and half-yearly plans are deferred to avoid ten paid choices
across two tiers and unnecessary switching complexity.

## Rollout gates

1. Review the design and distinguish the tiers clearly. Gather returning-user
   feedback and validate interest in the proposed additions. Ship the first
   public version free with existing Coming soon mood previews.
2. Decide the actual recurring benefit/content schedule and prices. Consider
   starting with one paid tier if Epic is not sufficiently different at launch.
3. Implement store products and purchase validation. The backend, not this UI,
   must decide access from verified purchases. Never use a profile field or
   debug flag as proof of payment. Keep private paid content behind proper
   server permissions; current client locks are not a billing security system.
4. Implement restoration, account association, duplicate purchase prevention,
   upgrades/downgrades, renewal, cancellation, grace/account-hold states, expiry,
   refunds/revocations and store reconciliation. Fetch localized prices from
   the store. Provide manage-subscription and restore-access flows that work.
5. Test sandbox purchases, reinstall/device changes, sign-out/account switches,
   offline/failed/pending payments and every access transition before enabling
   public purchase buttons. Verify the free experience remains usable.
6. Submit the integrated build and products for review. Android can be first;
   Apple work also requires the owner's renewed developer membership.

Store approval of a free app is not a prerequisite for developing billing.
Apple requires the first subscription submission to accompany a new app version.
Both stores support the proposed monthly/yearly durations and expect clear
renewal terms. Google requires sustained or recurring subscription value.

References checked September 29, 2026:
- https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase
- https://developer.apple.com/app-store/subscriptions/
- https://support.google.com/googleplay/android-developer/answer/9900533
- https://support.google.com/googleplay/android-developer/answer/140504

## Regression checks

`flutter test test/membership_preview_test.dart` checks ordinary-build visibility,
tier/cadence selection, navigation, narrow/large-text layouts and unchanged lens
settings. Repeat with `--dart-define=MOODDARE_MEMBERSHIP_PREVIEW=true` to exercise
both development entry points. Existing mood tests retain locked-access checks.
