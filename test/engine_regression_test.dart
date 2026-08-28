import 'package:flutter_test/flutter_test.dart';
import 'package:cler_app/core/quality_loop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('engine regression fixtures (processChat)', () async {
    final report = await runRegression(useProcessChat: true);
    // Print failures for diagnosis
    // ignore: avoid_print
    print(report);
    expect(
      report.passRate,
      greaterThanOrEqualTo(0.7),
      reason: 'Expected ≥70% fixture pass rate.\n$report',
    );
  });

  test('engine regression fixtures (resolveMove only)', () async {
    final report = await runRegression(useProcessChat: false);
    // ignore: avoid_print
    print(report);
    expect(report.passRate, greaterThanOrEqualTo(0.7));
  });
}
