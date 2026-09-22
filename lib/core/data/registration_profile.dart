/// Profile collected during account creation, before credentials exist.
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

/// Completed years from [birth] until [today].
int ageInYears(DateTime birth, [DateTime? today]) {
  final now = today ?? DateTime.now();
  var age = now.year - birth.year;
  final birthdayPassed = now.month > birth.month ||
      (now.month == birth.month && now.day >= birth.day);
  if (!birthdayPassed) age -= 1;
  if (age < 0) return 0;
  return age;
}

bool isValidBirthDate(DateTime birth, [DateTime? today]) {
  final now = today ?? DateTime.now();
  final current = DateTime(now.year, now.month, now.day);
  final selected = DateTime(birth.year, birth.month, birth.day);
  return !selected.isAfter(current);
}

/// Arabic validation for the account-creation profile step.
/// Returns `null` when the profile can continue.
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
