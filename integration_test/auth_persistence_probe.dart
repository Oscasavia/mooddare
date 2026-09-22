// Standalone native-session probe. Run with tooling/test_auth_persistence.py;
// it uses a named demo Firebase app and only the local Auth emulator.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = await Firebase.initializeApp(
    name: 'session-probe',
    options: const FirebaseOptions(
      apiKey: 'demo-api-key',
      appId: '1:123456789:android:abcdef012345',
      messagingSenderId: '123456789',
      projectId: 'demo-mooddare',
    ),
  );
  final auth = FirebaseAuth.instanceFor(app: app);
  await auth.useAuthEmulator('10.0.2.2', 9099);
  var status = 'SESSION_RESTORED';
  if (auth.currentUser == null) {
    await auth.createUserWithEmailAndPassword(
      email: 'session-${DateTime.now().microsecondsSinceEpoch}@mooddare.test',
      password: 'Local-emulator-only-42!',
    );
    status = 'SESSION_CREATED';
  }
  runApp(
    MaterialApp(
      home: _Probe(auth: auth, initialStatus: status),
    ),
  );
}

class _Probe extends StatefulWidget {
  final FirebaseAuth auth;
  final String initialStatus;
  const _Probe({required this.auth, required this.initialStatus});
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  late String status = widget.initialStatus;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(status),
          FilledButton(
            onPressed: () async {
              await widget.auth.signOut();
              if (mounted) setState(() => status = 'SESSION_SIGNED_OUT');
            },
            child: const Text('Sign out test account'),
          ),
        ],
      ),
    ),
  );
}
