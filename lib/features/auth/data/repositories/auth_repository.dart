import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mooddare/features/user/data/repositories/user_repository.dart';

class AuthRepository {
  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final UserRepository _userRepository;
  AuthRepository({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
    UserRepository? userRepository,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn(),
       _userRepository = userRepository ?? UserRepository();

  Future<UserCredential?> signInWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null;
    final tokens = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: tokens.accessToken,
      idToken: tokens.idToken,
    );
    final current = _firebaseAuth.currentUser;
    final result = current?.isAnonymous == true
        ? await current!.linkWithCredential(credential)
        : await _firebaseAuth.signInWithCredential(credential);
    await _userRepository.upsertUser(result.user!);
    return result;
  }

  Future<void> signOut() async {
    // Firebase owns the app session. A provider cleanup failure must neither
    // prevent signing out nor report failure after Firebase has signed out.
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _firebaseAuth.signOut();
  }

  Future<UserCredential> signUpWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final current = _firebaseAuth.currentUser;
    final result = current?.isAnonymous == true
        ? await current!.linkWithCredential(
            EmailAuthProvider.credential(email: email, password: password),
          )
        : await _firebaseAuth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
    await _userRepository.upsertUser(result.user!);
    return result;
  }

  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final result = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _userRepository.upsertUser(result.user!);
    return result;
  }
}
