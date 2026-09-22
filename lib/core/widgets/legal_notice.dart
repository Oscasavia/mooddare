import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mooddare/features/settings/presentation/legal_screen.dart';

/// Local policy routes work before sign-in and without a network connection.
class LegalNotice extends StatefulWidget {
  final String lead;
  const LegalNotice({super.key, this.lead = 'By continuing, you agree to our'});

  @override
  State<LegalNotice> createState() => _LegalNoticeState();
}

class _LegalNoticeState extends State<LegalNotice> {
  final _terms = TapGestureRecognizer();
  final _privacy = TapGestureRecognizer();

  void _open(LegalDocument document) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => LegalScreen(document: document)),
    );
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'For ages 18 and up. '),
          TextSpan(text: '${widget.lead} '),
          TextSpan(
            text: 'Terms of Use',
            style: linkStyle,
            recognizer: _terms..onTap = () => _open(LegalDocument.terms),
          ),
          const TextSpan(text: ' and acknowledge our '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: _privacy..onTap = () => _open(LegalDocument.privacy),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, color: Colors.white60, height: 1.6),
    );
  }
}
