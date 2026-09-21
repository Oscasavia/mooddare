import 'package:flutter/material.dart';
import '../../data/social_repository.dart';

class ReportUserSheet extends StatefulWidget {
  final String userId;
  final SocialRepository repository;
  const ReportUserSheet({
    super.key,
    required this.userId,
    required this.repository,
  });

  @override
  State<ReportUserSheet> createState() => _ReportUserSheetState();
}

class _ReportUserSheetState extends State<ReportUserSheet> {
  UserReportReason? _reason;
  bool _sending = false;
  String? _error;

  Future<void> _submit() async {
    if (_sending || _reason == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.repository.reportUser(widget.userId, _reason!);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Could not send your report. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Report user', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Why are you reporting this account? Your report is not shared with them.',
          ),
          const SizedBox(height: 12),
          for (final reason in UserReportReason.values)
            RadioListTile<UserReportReason>(
              contentPadding: EdgeInsets.zero,
              title: Text(reason.label),
              value: reason,
              groupValue: _reason,
              onChanged: _sending
                  ? null
                  : (value) => setState(() => _reason = value),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!, semanticsLabel: _error),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _sending || _reason == null ? null : _submit,
            child: Text(_sending ? 'Sending…' : 'Submit report'),
          ),
        ],
      ),
    ),
  );
}
