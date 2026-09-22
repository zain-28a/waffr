import 'package:flutter_test/flutter_test.dart';
import 'package:waffer/data/models/registration_profile.dart';

void main() {
  final today = DateTime(2026, 9, 21);

  test('derives age from the selected birth date', () {
    expect(ageInYears(DateTime(2000, 9, 21), today), 26);
    expect(ageInYears(DateTime(2000, 9, 22), today), 25);
    expect(ageInYears(DateTime(2000, 1, 1), today), 26);
  });

  test('requires name, birth date, gender, country, and city', () {
    expect(
      registrationProfileError(
        name: '  ',
        birthDate: DateTime(2000, 1, 1),
        gender: 'male',
        country: 'سوريا',
        city: 'اللاذقية',
        today: today,
      ),
      'أدخل الاسم',
    );
    expect(
      registrationProfileError(
        name: 'أحمد',
        birthDate: null,
        gender: 'male',
        country: 'سوريا',
        city: 'اللاذقية',
        today: today,
      ),
      'اختر تاريخ الميلاد',
    );
    expect(
      registrationProfileError(
        name: 'أحمد',
        birthDate: DateTime(2027, 1, 1),
        gender: 'female',
        country: 'سوريا',
        city: 'اللاذقية',
        today: today,
      ),
      'تاريخ الميلاد غير صالح',
    );
    expect(
      registrationProfileError(
        name: 'أحمد',
        birthDate: DateTime(2000, 1, 1),
        gender: null,
        country: 'سوريا',
        city: 'اللاذقية',
        today: today,
      ),
      'اختر الجنس',
    );
    expect(
      registrationProfileError(
        name: 'أحمد',
        birthDate: DateTime(2000, 1, 1),
        gender: 'male',
        country: '',
        city: 'اللاذقية',
        today: today,
      ),
      'أدخل الدولة',
    );
    expect(
      registrationProfileError(
        name: 'أحمد',
        birthDate: DateTime(2000, 1, 1),
        gender: 'male',
        country: 'سوريا',
        city: ' ',
        today: today,
      ),
      'أدخل المدينة',
    );
  });

  test('street is optional and a complete profile has no error', () {
    expect(
      registrationProfileError(
        name: 'أحمد',
        birthDate: DateTime(1998, 5, 12),
        gender: 'male',
        country: 'سوريا',
        city: 'اللاذقية',
        today: today,
      ),
      isNull,
    );

    final profile = RegistrationProfile(
      name: 'أحمد',
      birthDate: DateTime.utc(1998, 5, 12),
      gender: 'male',
      country: 'سوريا',
      city: 'اللاذقية',
    );
    final body = profile.toAuthBody();
    expect(body.containsKey('street'), isFalse);
    expect(body['name'], 'أحمد');
    expect(body['gender'], 'male');
    expect(body['country'], 'سوريا');
    expect(body['city'], 'اللاذقية');
  });
}
