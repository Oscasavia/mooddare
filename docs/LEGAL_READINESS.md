# Policy screens and public-launch work

The in-app Terms of Use and Privacy Policy are a first draft for the current
app, dated September 22, 2026. They are available offline from Welcome,
email/Google authentication screens and Settings. The contact label is
“MoodDare team” with the existing support email. No business incorporation,
address, governing law or jurisdiction has been invented.

The initial wording is 18+, following the owner's tentative preference for an
adult launch while moderation and teen safeguards are developed. This is an
eligibility statement, **not implemented age verification**. These changes do
not add a consent audit record, accept on the user's behalf, change Firebase
rules, or retroactively obtain agreement from existing users.

Before public distribution, have the actual operator and qualified counsel
review the policies for the launch markets. Confirm operator identity/contact
disclosures, minimum age and an appropriate age assurance process, treatment
of minors, lawful bases/rights and transfers where applicable, provider
retention periods and actual deletion behavior. Set up a real process to act
on privacy requests, copyright concerns and content reports. An 18+ label does
not replace moderation, objectionable-content controls or abuse response.

Also publish stable public policy URLs for store listings, decide how to
record and version acceptance where needed, and implement notice of material
policy updates before changing these documents. The current local UI does
not provide an acceptance log or policy-update notification mechanism.

Data disclosures were checked against `pubspec.yaml`, authentication/profile,
recent-search, post and account-deletion repositories and native camera code.
The policies distinguish feed expiry from deletion, explain shared-link and
download access, disclose on-device face effects and local caches, and avoid
promising instant erasure from backups or copies saved by other people.

References reviewed:

- [FTC mobile app disclosures](https://www.ftc.gov/business-guidance/resources/marketing-your-mobile-app-get-it-right-start)
- [Firebase privacy and service data](https://firebase.google.com/support/privacy)
- [FTC COPPA FAQ](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions)
- [Apple user-generated-content requirements](https://developer.apple.com/app-store/review/guidelines/#user-generated-content)
