/// Smoke test to verify integration_test infrastructure works.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('smoke test: 1+1=2', (tester) async {
    expect(1 + 1, 2);
  });
}