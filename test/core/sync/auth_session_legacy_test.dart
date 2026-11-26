// AuthSession.forgetLegacyPassword: the plaintext password very old builds
// kept in prefs is deleted at start-up, and nothing else is touched.

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/sync/auth_session.dart';

import '../../helpers/store_harness.dart';

void main() {
  test('the legacy password is deleted and the rest stays', () async {
    final prefs = await setUpStores();
    await prefs.setString(AuthSession.legacyPasswordKey, 'old plain password');
    await prefs.setString(AuthSession.accountEmailKey, 'owner@example.com');

    await AuthSession.instance.forgetLegacyPassword();

    expect(prefs.containsKey(AuthSession.legacyPasswordKey), isFalse);
    expect(prefs.getString(AuthSession.accountEmailKey), 'owner@example.com');
  });

  test('nothing to delete is fine', () async {
    final prefs = await setUpStores();
    await AuthSession.instance.forgetLegacyPassword();
    expect(prefs.containsKey(AuthSession.legacyPasswordKey), isFalse);
  });
}
