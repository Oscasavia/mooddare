import 'package:flutter/material.dart';
import '../data/settings_repository.dart';

enum LegalDocument { terms, privacy }

class LegalSection {
  final String title;
  final String body;
  const LegalSection(this.title, this.body);
}

const legalUpdated = 'September 22, 2026';

const termsSections = <LegalSection>[
  LegalSection(
    'Welcome to MoodDare',
    'MoodDare helps you choose a mood, try a dare, capture a moment and connect with other people. These Terms of Use explain the rules for using the app. By creating an account or using MoodDare, you agree to these terms. If you do not agree, do not use the service.',
  ),
  LegalSection(
    'Who can use MoodDare',
    'MoodDare is currently for people aged 18 or older. By using the app, you confirm that you meet this requirement and can enter into these terms under the laws that apply to you. The minimum age does not permit sexual or otherwise prohibited content.',
  ),
  LegalSection(
    'Your account',
    'Keep your sign-in details secure and provide accurate account information. Do not impersonate another person, use someone else’s account without permission, or misrepresent your identity. Contact us if you believe your account has been accessed without permission.',
  ),
  LegalSection(
    'Dare thoughtfully',
    'Every dare is optional. Use your judgment and skip anything that is unsafe, unlawful, uncomfortable or unsuitable for your surroundings. Never trespass, distract yourself while driving, pressure someone to participate, or put yourself or others at risk. Get permission before filming or sharing other people.',
  ),
  LegalSection(
    'Respect the community',
    'Do not post or promote harassment, threats, hate, pornography, sexualized content, sexual exploitation, non-consensual intimate content, dangerous activity, scams, spam or illegal content. Do not expose someone’s private information or infringe their copyright or other rights. Use the report and block options to flag concerns, or contact us. We may remove content or restrict accounts to address violations and protect the community.',
  ),
  LegalSection(
    'Your content stays yours',
    'You keep ownership of the content you create. You must have the rights and permissions needed to upload it. You give MoodDare a non-exclusive, worldwide, royalty-free license to host, store, process and display your content, and to make it available through the app’s sharing and download features, solely to operate the service. This permission ends when the content is removed from our systems, subject to service-provider backup cycles, legal obligations and copies others have already saved or shared.',
  ),
  LegalSection(
    'Sharing and visibility',
    'Your profile and posted moments are visible to other signed-in members. People can save or share posted media; anyone with a shared media link may view that media. A moment leaving the feed after 24 hours is not the same as deletion. Only share content you are comfortable making available in this way. Respect other creators: downloading a post does not transfer ownership or grant permission for unrelated reuse.',
  ),
  LegalSection(
    'Using the app fairly',
    'Do not misuse the service, bypass access controls, interfere with other people’s accounts, scrape personal information or overload the app. MoodDare’s name, mascot and original interface belong to their respective rights holders. Third-party software is covered by the notices in Settings → Licenses.',
  ),
  LegalSection(
    'Availability and future features',
    'Features may change or become unavailable, and the app may contain errors. Premium mood packs are currently previews; viewing them does not make a purchase or start a subscription. If paid features are introduced, their price and purchase terms will be shown before you pay. To the extent allowed by law, the service is provided as available without a guarantee of uninterrupted or error-free operation. Nothing in these terms removes rights or protections that cannot legally be excluded.',
  ),
  LegalSection(
    'Leaving MoodDare',
    'You can stop using the app at any time and request account deletion from Settings → Delete account. You may need to verify your identity. Keep the app open until deletion finishes; if it fails, retry or contact us. See the Privacy Policy for information about retention, backups and copies saved by other people.',
  ),
  LegalSection(
    'Changes and questions',
    'We will update the date on this page when these terms change. Material changes will be brought to your attention in the app or by another appropriate method before they take effect. If you do not accept revised terms, stop using the service. Questions, content reports and rights concerns can be sent to the MoodDare team at ${SettingsRepository.supportEmail}.',
  ),
];

const privacySections = <LegalSection>[
  LegalSection(
    'About this policy',
    'This policy explains how MoodDare handles information when you use the app. It covers account access, creative tools and community features. Contact the MoodDare team at ${SettingsRepository.supportEmail} with privacy questions or requests.',
  ),
  LegalSection(
    'Information you provide',
    'We process your account identifier, email address and sign-in information to manage your account. If you use Google sign-in, Google also provides basic profile information such as your name and profile picture. We store profile details you choose to add, including your username, name, bio and avatar; photos and videos you post, including recorded audio; selected moods and dares; and your comments, replies, likes, follows, blocks and reports. We also receive information you send when you contact support.',
  ),
  LegalSection(
    'Information on your device',
    'The app keeps sign-in state, cached content and working photo or video files on your device to provide its features. Find people stores recent searches locally for your account; you can remove individual searches or clear them from that screen. Service providers may process technical information, including IP addresses, device or app details and security logs, to authenticate requests, deliver content and protect the service.',
  ),
  LegalSection(
    'Camera, microphone and face effects',
    'Camera access lets you take photos and videos. Microphone access lets you record sound. Photo-library or media permissions are used when you select or save media. You can manage these permissions in your device settings; disabling them may limit the related feature. Face detection and beauty effects process images and face landmarks on your device. MoodDare does not use these landmarks to identify you or upload them as a face template. Edited photos or videos may contain your face and are uploaded when you choose to post; a profile photo is uploaded when you save it to your profile.',
  ),
  LegalSection(
    'How we use information',
    'We use information to provide accounts, profiles, capture and editing tools, posting, discovery and social features; handle support requests and reports; protect accounts and the community; and meet applicable legal obligations. The current app does not include advertising or a separate advertising-tracking SDK. If these practices change, we will update this policy and seek permission where required.',
  ),
  LegalSection(
    'What other people can see',
    'Other signed-in members can view your profile, posts and social interactions such as comments, likes and follower or following lists. Users can save and share posted photos and videos. Anyone who receives a shared media link may be able to view the media without signing in. Blocking controls what appears in parts of the app; it does not recall downloaded copies or make previously shared links private. Please avoid posting sensitive information or material you do not want others to retain.',
  ),
  LegalSection(
    'Service providers and disclosures',
    'MoodDare uses Google Firebase Authentication, Cloud Firestore and Cloud Storage for sign-in, database and media hosting, and Google sign-in when you choose it. These providers process information to deliver and secure those services. Information may be processed in countries other than where you live. Sharing through your phone’s share menu sends the content you select to the service or person you choose. We may also disclose information when required by law or when necessary to address fraud, abuse or threats to people’s safety.',
  ),
  LegalSection(
    'Retention and deletion',
    'Moments leave the feed after 24 hours, but this does not delete the post or its media. Your posts remain available through your profile until deleted. You can delete your own posts and comments and request account deletion in Settings. Account deletion removes the profile, uploaded media, posts and associated account data handled by the deletion process. Interrupted deletion may leave data until you retry or contact us. Some records may remain in service-provider logs or backups for their retention periods, or where legally required. Copies downloaded or shared by others are outside our control. Local cached files may remain until cleared by the app, operating system or removal of the app.',
  ),
  LegalSection(
    'Your choices and requests',
    'You can edit your profile, delete your content, clear recent searches, manage device permissions, sign out or delete your account. Depending on where you live, you may have rights to access, correct, receive a copy of, delete or restrict use of your information, or to object to certain processing. Send requests to ${SettingsRepository.supportEmail}; we may need to verify your identity. You may also contact your local privacy regulator. Signing out alone does not delete your account or posted content.',
  ),
  LegalSection(
    'Age requirement',
    'MoodDare is currently intended for adults aged 18 or older. If you believe someone under 18 has provided personal information through the app, contact the MoodDare team at ${SettingsRepository.supportEmail} so we can investigate and address the account and related information. An age requirement is not a claim that we have verified every user’s age.',
  ),
  LegalSection(
    'Security',
    'We use authentication and access rules to limit access to account data and media. No app, network or storage system can promise absolute security. Keep your device and sign-in credentials secure, and contact us if you suspect unauthorized access.',
  ),
  LegalSection(
    'Policy updates',
    'We will update the date on this page when our practices change. We will bring material changes to your attention in the app or by another appropriate method and request any additional consent required by law.',
  ),
];

class LegalScreen extends StatelessWidget {
  final LegalDocument document;
  const LegalScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final privacy = document == LegalDocument.privacy;
    final sections = privacy ? privacySections : termsSections;
    return Scaffold(
      appBar: AppBar(title: Text(privacy ? 'Privacy Policy' : 'Terms of Use')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: SelectionArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                children: [
                  Text(
                    privacy
                        ? 'Your privacy matters.'
                        : 'A little respect goes a long way.',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Last updated $legalUpdated',
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 28),
                  for (final section in sections) ...[
                    Semantics(
                      header: true,
                      child: Text(
                        section.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      section.body,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.65,
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
