import 'package:flutter_test/flutter_test.dart';
import 'package:waffer/core/sync/auth_errors.dart';

void main() {
  test('maps register and login API errors to Arabic copy', () {
    expect(
      describeAuthError(401, {'detail': 'Invalid email or password'}),
      'البريد أو كلمة المرور غير صحيحة',
    );
    expect(
      describeAuthError(400, {'detail': 'Email already registered'}),
      'هذا البريد مسجّل مسبقاً',
    );
    expect(
      describeAuthError(422, {
        'detail': [
          {'msg': 'value is not a valid email address'},
        ],
      }),
      'أدخل بريداً إلكترونياً صالحاً',
    );
  });
}
