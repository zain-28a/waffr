import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waffer/data/models/country.dart';
import 'package:waffer/data/models/registration_profile.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/screens/offline/user_info/country_picker_sheet.dart';
import 'package:waffer/widgets/button/ani_pri_button.dart';
import 'package:waffer/widgets/dialogs/waffer_date_picker.dart';

// Collects name, birth date, optional gender, country with an optional phone
// number, and one optional address line for RegistrationProfile.

enum Gender { male, female }

class UserInfoScreen extends StatefulWidget {
  final ValueChanged<RegistrationProfile> onContinue;
  final VoidCallback? onBack;

  const UserInfoScreen({
    super.key,
    required this.onContinue,
    this.onBack,
  });

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  Gender? _selectedGender;
  DateTime? _birthDate;
  CountryInfo? _country;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  String? get _genderValue {
    if (_selectedGender == Gender.male) return 'male';
    if (_selectedGender == Gender.female) return 'female';
    return null;
  }

  // Tapping the chosen option again clears it; gender stays optional.
  void _toggleGender(Gender gender) {
    setState(() {
      _selectedGender = _selectedGender == gender ? null : gender;
    });
  }

  String? get _formError {
    return registrationProfileError(
      name: _nameController.text,
      birthDate: _birthDate,
      gender: _genderValue,
      country: _country?.arabicName ?? '',
      address: _addressController.text,
      phone: _phoneController.text,
    );
  }

  bool get _isFormValid => _formError == null;

  Future<void> _pickBirthDate() async {
    FocusScope.of(context).unfocus();
    final picked = await showWafferDatePicker(
      context: context,
      title: 'تاريخ الميلاد',
      initialDate: _birthDate,
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
      startWithYear: true,
    );

    if (picked != null && mounted) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _pickCountry() async {
    FocusScope.of(context).unfocus();
    final picked = await showCountryPickerSheet(context, selected: _country);
    if (picked != null && mounted) {
      setState(() => _country = picked);
    }
  }

  void _continue() {
    final error = _formError;
    if (error != null) {
      showAppSnackBar(context, error);
      return;
    }

    final birthDate = _birthDate;
    final country = _country;
    if (birthDate == null || country == null) return;

    final digits = normalizePhoneNumber(_phoneController.text) ?? '';
    final address = splitAddress(_addressController.text);

    widget.onContinue(
      RegistrationProfile(
        name: _nameController.text.trim(),
        birthDate: birthDate,
        gender: _genderValue,
        country: country.arabicName,
        city: address.city,
        street: address.street,
        phone: digits.isEmpty ? '' : '${country.dialLabel} $digits',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.onBack != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: IconButton(
                    icon: Icon(Icons.arrow_forward_ios_rounded, color: textPrimary),
                    onPressed: widget.onBack,
                  ),
                )
              else
                const SizedBox(height: 40),

              Text(
                "الملف الشخصي",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "هذه المعلومات تساعد في تقديم تجربة افضل",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: textSecondary),
              ),

              const SizedBox(height: 48),

              _FieldLabel(text: 'الاسم', color: textPrimary),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textAlign: TextAlign.right,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: textPrimary, fontSize: 16),
                decoration: _fieldDecoration(
                  hint: 'الاسم الكامل',
                  fillColor: surface,
                  textSecondary: textSecondary,
                ),
              ),

              const SizedBox(height: 24),

              _FieldLabel(text: 'تاريخ الميلاد', color: textPrimary),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickBirthDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _birthDate != null ? formatDate(_birthDate!) : 'DD/MM/YYYY',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: _birthDate != null
                              ? textPrimary
                              : textSecondary.withValues(alpha: 0.6),
                          fontSize: 16,
                        ),
                      ),
                      Icon(Icons.calendar_today_outlined, size: 20, color: accent),
                    ],
                  ),
                ),
              ),
              if (_birthDate != null) ...[
                const SizedBox(height: 8),
                Text(
                  'العمر ${ageInYears(_birthDate!)} سنة',
                  style: TextStyle(color: textSecondary, fontSize: 13),
                ),
              ],

              const SizedBox(height: 24),

              _FieldLabel(text: 'الجنس (اختياري)', color: textPrimary),
              const SizedBox(height: 4),
              Row(
                children: [
                  _GenderRadio(
                    label: 'ذكر',
                    selected: _selectedGender == Gender.male,
                    accent: accent,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    onTap: () => _toggleGender(Gender.male),
                  ),
                  const SizedBox(width: 28),
                  _GenderRadio(
                    label: 'أنثى',
                    selected: _selectedGender == Gender.female,
                    accent: accent,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    onTap: () => _toggleGender(Gender.female),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              _FieldLabel(text: 'الدولة', color: textPrimary),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickCountry,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _country?.arabicName ?? 'اختر الدولة',
                          style: TextStyle(
                            color: _country != null
                                ? textPrimary
                                : textSecondary.withValues(alpha: 0.6),
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (_country != null) ...[
                        Text(
                          _country!.dialLabel,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Icon(Icons.keyboard_arrow_down_rounded, color: accent),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              _FieldLabel(text: 'العنوان (اختياري)', color: textPrimary),
              const SizedBox(height: 8),
              TextField(
                controller: _addressController,
                textAlign: TextAlign.right,
                maxLength: maxStreetLength,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: textPrimary, fontSize: 16),
                decoration: _fieldDecoration(
                  hint: 'المشروع الأول',
                  fillColor: surface,
                  textSecondary: textSecondary,
                ).copyWith(counterText: ''),
              ),

              const SizedBox(height: 24),

              _FieldLabel(text: 'رقم الهاتف (اختياري)', color: textPrimary),
              const SizedBox(height: 8),
              _PhoneField(
                controller: _phoneController,
                country: _country,
                surface: surface,
                accent: accent,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                onPickCountry: _pickCountry,
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 48),

              AnimatedPrimaryButton(
                text: 'متابعة',
                style: const TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontWeight: FontWeight.bold,
                ),
                backgroundColor: _isFormValid ? accent : textSecondary,
                textColor: surface,
                onPressed: _continue,
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required Color fillColor,
    required Color textSecondary,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.6)),
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _FieldLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
    );
  }
}

// Round radio mark next to its label. No box around it.
class _GenderRadio extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;

  const _GenderRadio({
    required this.label,
    required this.selected,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? accent
                        : textSecondary.withValues(alpha: 0.6),
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Calling code and number in one field. The code sits on the left (numbers
// read left to right) and opens the country list.
class _PhoneField extends StatelessWidget {
  final TextEditingController controller;
  final CountryInfo? country;
  final Color surface;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onPickCountry;
  final ValueChanged<String> onChanged;

  const _PhoneField({
    required this.controller,
    required this.country,
    required this.surface,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.onPickCountry,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasCountry = country != null;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            InkWell(
              onTap: onPickCountry,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 10, 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasCountry ? country!.dialLabel : '+',
                      style: TextStyle(
                        color: hasCountry ? accent : textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 20,
                      color: textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              height: 26,
              color: textSecondary.withValues(alpha: 0.25),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: hasCountry,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                  LengthLimitingTextInputFormatter(18),
                ],
                onChanged: onChanged,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 16,
                  letterSpacing: 0.4,
                ),
                decoration: InputDecoration(
                  hintText: hasCountry ? '9XX XXX XXX' : 'اختر الدولة أولاً',
                  hintTextDirection:
                      hasCountry ? TextDirection.ltr : TextDirection.rtl,
                  hintStyle: TextStyle(
                    color: textSecondary.withValues(alpha: 0.6),
                    fontSize: hasCountry ? 16 : 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
