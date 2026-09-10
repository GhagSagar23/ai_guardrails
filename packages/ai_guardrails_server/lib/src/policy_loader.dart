import 'dart:convert';
import 'dart:io';

import 'package:ai_guardrails/ai_guardrails.dart';

/// Loads an [AiGuard] from a JSON policy file.
///
/// The JSON format matches [AiGuard.fromConfig]:
/// ```json
/// {
///   "failClosed": true,
///   "inputScanners": [{"type": "pii", "action": "redact"}],
///   "outputScanners": [{"type": "repetition"}]
/// }
/// ```
///
/// Optionally accepts a `"profile"` key to start from a [PolicyProfile]:
/// ```json
/// {"profile": "healthcare"}
/// ```
class PolicyLoader {
  PolicyLoader._();

  static AiGuard fromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw ArgumentError('Policy file not found: $path');
    }
    final content = file.readAsStringSync();
    return fromJson(content);
  }

  static AiGuard fromJson(String json) {
    final config = jsonDecode(json) as Map<String, dynamic>;
    return fromMap(config);
  }

  static AiGuard fromMap(Map<String, dynamic> config) {
    final profileName = config['profile'] as String?;
    if (profileName != null) {
      final profile = PolicyProfile.byName(profileName);
      if (profile == null) {
        throw ArgumentError('Unknown policy profile: $profileName');
      }
      final overrides = Map<String, dynamic>.from(config)..remove('profile');
      if (overrides.isEmpty) return profile.toGuard();
      return profile.toGuardWith(overrides);
    }
    return AiGuard.fromConfig(config);
  }
}
