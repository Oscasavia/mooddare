import 'package:flutter/material.dart';
import 'auth_form_screen.dart';

class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});
  @override
  Widget build(BuildContext context) => const AuthFormScreen(signUp: true);
}
