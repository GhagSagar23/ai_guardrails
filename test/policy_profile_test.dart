import 'package:ai_guardrails/ai_guardrails.dart';
import 'package:test/test.dart';

void main() {
  group('PolicyProfile', () {
    test('healthcare builds without error', () {
      final guard = PolicyProfile.healthcare.toGuard();
      expect(guard.inputScanners, isNotEmpty);
      expect(guard.outputScanners, isNotEmpty);
      expect(guard.rules, isNotEmpty);
    });

    test('finance builds without error', () {
      final guard = PolicyProfile.finance.toGuard();
      expect(guard.inputScanners, isNotEmpty);
      expect(guard.rules, isNotEmpty);
    });

    test('education builds without error', () {
      final guard = PolicyProfile.education.toGuard();
      expect(guard.inputScanners, isNotEmpty);
    });

    test('enterprise builds without error', () {
      final guard = PolicyProfile.enterprise.toGuard();
      expect(guard.inputScanners, isNotEmpty);
      expect(guard.rules, isNotEmpty);
    });

    test('healthcare blocks PII', () async {
      final guard = PolicyProfile.healthcare.toGuard();
      final results = await guard.scanInput(
        'Patient email: patient@hospital.com, SSN: 123-45-6789',
      );
      expect(results.any((r) => !r.passed), isTrue);
    });

    test('finance blocks credit card numbers', () async {
      final guard = PolicyProfile.finance.toGuard();
      final results = await guard.scanInput(
        'Card number: 4111-1111-1111-1111',
      );
      final allFindings = [for (final r in results) ...r.findings];
      expect(allFindings.any((f) => f.type.contains('credit_card')), isTrue);
    });

    test('toGuardWith applies overrides', () {
      final guard = PolicyProfile.healthcare.toGuardWith({
        'failClosed': false,
      });
      expect(guard.failClosed, isFalse);
    });

    test('byName returns correct profile', () {
      expect(
          PolicyProfile.byName('healthcare'), same(PolicyProfile.healthcare));
      expect(PolicyProfile.byName('finance'), same(PolicyProfile.finance));
      expect(PolicyProfile.byName('education'), same(PolicyProfile.education));
      expect(
          PolicyProfile.byName('enterprise'), same(PolicyProfile.enterprise));
    });

    test('byName returns null for unknown', () {
      expect(PolicyProfile.byName('nonexistent'), isNull);
    });

    test('values contains all profiles', () {
      expect(PolicyProfile.values, hasLength(4));
    });

    test('education blocks dangerous URLs', () async {
      final guard = PolicyProfile.education.toGuard();
      final results = await guard.scanInput(
        'Click http://192.168.1.1/admin',
      );
      final allFindings = [for (final r in results) ...r.findings];
      expect(allFindings.any((f) => f.type.startsWith('url.')), isTrue);
    });

    test('enterprise blocks secrets', () async {
      final guard = PolicyProfile.enterprise.toGuard();
      final results = await guard.scanInput(
        'Key: AKIAIOSFODNN7EXAMPLE',
      );
      final allFindings = [for (final r in results) ...r.findings];
      expect(allFindings.any((f) => f.type.startsWith('secret.')), isTrue);
    });

    test('clean input passes all profiles', () async {
      for (final profile in PolicyProfile.values) {
        final guard = profile.toGuard();
        final results = await guard.scanInput('What is the weather today?');
        final hasBlock = results.any((r) => !r.passed);
        expect(hasBlock, isFalse,
            reason: '${profile.name} blocked clean input');
      }
    });
  });
}
