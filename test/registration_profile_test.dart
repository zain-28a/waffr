import 'package:flutter_test/flutter_test.dart';
import 'package:waffer/data/models/country.dart';
import 'package:waffer/data/models/registration_profile.dart';

void main() {
  final today = DateTime(2026, 9, 21);

  test('derives age from the selected birth date', () {
    expect(ageInYears(DateTime(2000, 9, 21), today), 26);
    expect(ageInYears(DateTime(2000, 9, 22), today), 25);
    expect(ageInYears(DateTime(2000, 1, 1), today), 26);
  });

  test('requires name, birth date and country', () {
    expect(
      registrationProfileError(
        name: '  ',
        birthDate: DateTime(2000, 1, 1),
        gender: 'male',
        country: 'سوريا',
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
        today: today,
      ),
      'تاريخ الميلاد غير صالح',
    );
    expect(
      registrationProfileError(
        name: 'أحمد',
        birthDate: DateTime(2000, 1, 1),
        gender: 'male',
        country: '',
        today: today,
      ),
      'اختر الدولة',
    );
  });

  test('gender, phone and address are optional', () {
    expect(
      registrationProfileError(
        name: 'أحمد',
        birthDate: DateTime(1998, 5, 12),
        gender: null,
        country: 'سوريا',
        today: today,
      ),
      isNull,
    );

    final profile = RegistrationProfile(
      name: 'أحمد',
      birthDate: DateTime.utc(1998, 5, 12),
      country: 'سوريا',
    );
    final body = profile.toAuthBody();
    expect(body.containsKey('gender'), isFalse);
    expect(body.containsKey('street'), isFalse);
    expect(body.containsKey('city'), isFalse);
    expect(body.containsKey('phone'), isFalse);
    expect(body['name'], 'أحمد');
    expect(body['country'], 'سوريا');
  });

  test('phone numbers drop the trunk zero and reject junk', () {
    expect(normalizePhoneNumber(''), '');
    expect(normalizePhoneNumber('0912 345 678'), '912345678');
    expect(normalizePhoneNumber('12'), isNull);
    expect(
      registrationProfileError(
        name: 'أحمد',
        birthDate: DateTime(1998, 5, 12),
        gender: 'female',
        country: 'سوريا',
        phone: '12',
        today: today,
      ),
      'رقم الهاتف غير صالح',
    );

    final body = RegistrationProfile(
      name: 'أحمد',
      birthDate: DateTime.utc(1998, 5, 12),
      gender: 'female',
      country: 'سوريا',
      phone: '+963 912345678',
    ).toAuthBody();
    expect(body['phone'], '+963 912345678');
    expect(body['gender'], 'female');
  });

  test('one address field splits into city and street at the first comma', () {
    expect(splitAddress('اللاذقية، المشروع الأول'), (
      city: 'اللاذقية',
      street: 'المشروع الأول',
    ));
    expect(splitAddress('المشروع الأول'), (city: '', street: 'المشروع الأول'));
    expect(splitAddress('  '), (city: '', street: ''));
  });

  test('country search folds hamza and matches calling codes', () {
    expect(
      Countries.search('الاردن').map((item) => item.iso),
      contains('JO'),
    );
    expect(
      Countries.search('+963').map((item) => item.iso),
      contains('SY'),
    );
    expect(Countries.byName('سوريا')?.dialLabel, '+963');
  });
}
