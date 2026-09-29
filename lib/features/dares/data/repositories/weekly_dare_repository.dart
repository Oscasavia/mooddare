import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dare_library_repository.dart';

/// One shared, administrator-published challenge per Monday-to-Monday UTC week.
class WeeklyDare {
  final String id, title;
  final DarePrompt prompt;
  final DateTime startsAt, endsAt;
  const WeeklyDare({
    required this.id,
    required this.title,
    required this.prompt,
    required this.startsAt,
    required this.endsAt,
  });

  static DateTime weekStart(DateTime time) {
    final utc = time.toUtc();
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
    ).subtract(Duration(days: utc.weekday - DateTime.monday));
  }

  static String weekId(DateTime time) =>
      weekStart(time).toIso8601String().substring(0, 10);
  bool isActive(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(endsAt);

  static WeeklyDare? parse(String id, Map<String, dynamic>? data) {
    if (data == null) return null;
    final start = data['startsAt'], end = data['endsAt'], title = data['title'];
    if (data['dareText'] is! String ||
        data['moodId'] is! String ||
        data['moodName'] is! String) {
      return null;
    }
    final prompt = DarePrompt.fromMap(data);
    if (start is! Timestamp ||
        end is! Timestamp ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 80 ||
        !prompt.isValid ||
        prompt.moodId == null) {
      return null;
    }
    final from = start.toDate().toUtc(), until = end.toDate().toUtc();
    if (from != weekStart(from) ||
        id != weekId(from) ||
        until.difference(from) != const Duration(days: 7)) {
      return null;
    }
    return WeeklyDare(
      id: id,
      title: title,
      prompt: prompt,
      startsAt: from,
      endsAt: until,
    );
  }
}

class WeeklyDareRepository {
  final FirebaseFirestore? _db;
  final FirebaseAuth? _auth;
  WeeklyDareRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore,
      _auth = auth;
  bool get _available => _db != null || Firebase.apps.isNotEmpty;
  FirebaseFirestore get _firestore => _db ?? FirebaseFirestore.instance;

  Stream<WeeklyDare?> watch(DateTime now) {
    if (!_available) return Stream.value(null);
    return _firestore
        .collection('weeklyDares')
        .doc(WeeklyDare.weekId(now))
        .snapshots()
        .map((doc) => WeeklyDare.parse(doc.id, doc.data()));
  }

  Stream<bool> completed(String weekId) {
    if (!_available) return Stream.value(false);
    final uid = (_auth ?? FirebaseAuth.instance).currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return _firestore
        .collection('posts')
        .where('authorId', isEqualTo: uid)
        .where('weeklyDareId', isEqualTo: weekId)
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isNotEmpty);
  }
}
