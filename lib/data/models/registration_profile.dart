// Signup profile fields and validation before the account credentials step.

// Demographics collected during registration, sent with the auth request.
class RegistrationProfile {
  final String name;
  final DateTime birthDate;
  final String gender;
  final String country;
  final String city;
  final String street;

  const RegistrationProfile({
    required this.name,
    required this.birthDate,
    required this.gender,
    required this.country,
    required this.city,
    this.street = '',
  });

  // Flattened map for the signup API; omits empty street.
  Map<String, String> toAuthBody() {
    final address = street.trim();
    return {
      'name': name.trim(),
      'gender': gender,
      'birthdate': birthDate.toIso8601String(),
      'country': country.trim(),
      'city': city.trim(),
      if (address.isNotEmpty) 'street': address,
    };
  }
}

// Full years between birth and today (or [today] when testing).
int ageInYears(DateTime birth, [DateTime? today]) {
  final now = today ?? DateTime.now();
  var age = now.year - birth.year;
  final birthdayPassed = now.month > birth.month ||
      (now.month == birth.month && now.day >= birth.day);
  if (!birthdayPassed) age -= 1;
  if (age < 0) return 0;
  return age;
}

// True when the chosen birth date is not in the future.
bool isValidBirthDate(DateTime birth, [DateTime? today]) {
  final now = today ?? DateTime.now();
  final current = DateTime(now.year, now.month, now.day);
  final selected = DateTime(birth.year, birth.month, birth.day);
  return !selected.isAfter(current);
}

// Arabic error for the profile form, or null when everything looks fine.
String? registrationProfileError({
  required String name,
  required DateTime? birthDate,
  required String? gender,
  required String country,
  required String city,
  String street = '',
  DateTime? today,
}) {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) return 'أدخل الاسم';
  if (trimmedName.length > 100) return 'الاسم طويل جداً';

  if (birthDate == null) return 'اختر تاريخ الميلاد';
  if (!isValidBirthDate(birthDate, today)) return 'تاريخ الميلاد غير صالح';

  if (gender != 'male' && gender != 'female') return 'اختر الجنس';

  final trimmedCountry = country.trim();
  if (trimmedCountry.isEmpty) return 'أدخل الدولة';
  if (trimmedCountry.length > 80) return 'اسم الدولة طويل جداً';

  final trimmedCity = city.trim();
  if (trimmedCity.isEmpty) return 'أدخل المدينة';
  if (trimmedCity.length > 80) return 'اسم المدينة طويل جداً';

  if (street.trim().length > 160) return 'العنوان طويل جداً';
  return null;
}
