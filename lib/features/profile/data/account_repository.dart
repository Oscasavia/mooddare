import '../../drafts/data/draft_repository.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mooddare/features/notifications/data/push_service.dart';
import 'recent_search_store.dart';

/// The server owns durable, retryable erasure. The phone only verifies intent,
/// clears its private drafts and signs out after the request is acknowledged.
class AccountRepository {
  final FirebaseAuth? auth;
  final Future<void> Function(String) deleteLocalDrafts;
  final Future<void> Function(String)? requestDeletion;
  final Future<void> Function()? detachPush;
  AccountRepository({
    this.auth,
    this.requestDeletion,
    this.detachPush,
    Future<void> Function(String)? deleteLocalDrafts,
  }) : deleteLocalDrafts = deleteLocalDrafts ?? clearLocalAccountData;

  static Future<void> clearLocalAccountData(String uid) async {
    await DraftRepository.instance.clear(uid);
    await RecentSearchStore.instance.clear(uid);
  }

  Future<void> _request(String uid) async {
    try {
      final response =
          await FirebaseFunctions.instanceFor(
            region: 'us-central1',
          ).httpsCallable('requestAccountDeletion').call<Map<String, dynamic>>({
            'confirm': 'DELETE',
            'expectedUid': uid,
          });
      if (response.data['accepted'] != true) {
        throw StateError(
          'Could not confirm account deletion. Please try again.',
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'failed-precondition' &&
          error.details is Map &&
          error.details['reason'] == 'requires-recent-login') {
        throw FirebaseAuthException(code: 'requires-recent-login');
      }
      rethrow;
    }
  }

  Future<void> deleteAccount() async {
    final auth = this.auth ?? FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final token = await user.getIdTokenResult(true);
    if (auth.currentUser?.uid != user.uid) {
      throw FirebaseAuthException(code: 'user-mismatch');
    }
    final signedIn = token.authTime;
    if (signedIn == null ||
        DateTime.now().difference(signedIn) > const Duration(minutes: 4)) {
      throw FirebaseAuthException(code: 'requires-recent-login');
    }
    await deleteLocalDrafts(user.uid);
    await (detachPush?.call() ??
        PushService.instance?.detach() ??
        Future<void>.value());
    if (auth.currentUser?.uid != user.uid) {
      throw FirebaseAuthException(code: 'user-mismatch');
    }
    await (requestDeletion?.call(user.uid) ?? _request(user.uid));
    // A lost connection after acceptance cannot stop the server's cleanup.
    if (auth.currentUser?.uid == user.uid) await auth.signOut();
  }
}
