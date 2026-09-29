import 'package:integration_test/integration_test.dart';
import '../test/moderation_test.dart' as checks;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  checks.main();
}
