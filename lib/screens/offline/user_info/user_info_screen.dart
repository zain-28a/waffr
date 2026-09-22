import 'package:flutter/material.dart';
import 'package:waffer/core/data/registration_profile.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/widgets/button/ani_pri_button.dart';

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
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();

  Gender? _selectedGender;
  DateTime? _birthDate;

  @override
  void dispose() {
    _nameController.dispose();
    _countryController.dispose();
    _cityController.dispose();
    _streetController.dispose();
    super.dispose();
  }

  String? get _genderValue {
    if (_selectedGender == Gender.male) return 'male';
    if (_selectedGender == Gender.female) return 'female';
    return null;
  }

  bool get _isFormValid {
    return registrationProfileError(
          name: _nameController.text,
          birthDate: _birthDate,
          gender: _genderValue,
          country: _countryController.text,
          city: _cityController.text,
          street: _streetController.text,
        ) ==
        null;
  }

  Future<void> _pickBirthDate(Color accent) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: accent),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _continue() {
    final error = registrationProfileError(
      name: _nameController.text,
      birthDate: _birthDate,
      gender: _genderValue,
      country: _countryController.text,
      city: _cityController.text,
      street: _streetController.text,
    );
    if (error != null) {
      showAppSnackBar(context, error);
      return;
    }

    final birthDate = _birthDate;
    final gender = _genderValue;
    if (birthDate == null || gender == null) return;

    widget.onContinue(
      RegistrationProfile(
        name: _nameController.text.trim(),
        birthDate: birthDate,
        gender: gender,
        country: _countryController.text.trim(),
        city: _cityController.text.trim(),
        street: _streetController.text.trim(),
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
                  fontFamily: 'Tajawal',
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
                onTap: () => _pickBirthDate(accent),
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
                        _birthDate != null ? _formatDate(_birthDate!) : "...",
                        style: TextStyle(
                          color: _birthDate != null ? textPrimary : textSecondary,
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

              _FieldLabel(text: 'الجنس', color: textPrimary),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _GenderButton(
                      label: 'ذكر',
                      isSelected: _selectedGender == Gender.male,
                      accent: accent,
                      surface: surface,
                      textPrimary: textPrimary,
                      onTap: () => setState(() => _selectedGender = Gender.male),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _GenderButton(
                      label: 'أنثى',
                      isSelected: _selectedGender == Gender.female,
                      accent: accent,
                      surface: surface,
                      textPrimary: textPrimary,
                      onTap: () => setState(() => _selectedGender = Gender.female),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              _FieldLabel(text: 'الدولة', color: textPrimary),
              const SizedBox(height: 8),
              TextField(
                controller: _countryController,
                textAlign: TextAlign.right,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: textPrimary, fontSize: 16),
                decoration: _fieldDecoration(
                  hint: 'سوريا',
                  fillColor: surface,
                  textSecondary: textSecondary,
                ),
              ),

              const SizedBox(height: 24),

              _FieldLabel(text: 'المدينة', color: textPrimary),
              const SizedBox(height: 8),
              TextField(
                controller: _cityController,
                textAlign: TextAlign.right,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: textPrimary, fontSize: 16),
                decoration: _fieldDecoration(
                  hint: 'اللاذقية',
                  fillColor: surface,
                  textSecondary: textSecondary,
                ),
              ),

              const SizedBox(height: 24),

              _FieldLabel(text: 'الشارع (اختياري)', color: textPrimary),
              const SizedBox(height: 8),
              TextField(
                controller: _streetController,
                textAlign: TextAlign.right,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: textPrimary, fontSize: 16),
                decoration: _fieldDecoration(
                  hint: 'العنوان',
                  fillColor: surface,
                  textSecondary: textSecondary,
                ),
              ),

              const SizedBox(height: 48),

              AnimatedPrimaryButton(
                text: 'متابعة',
                style: const TextStyle(
                  fontFamily: 'Tajawal',
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

class _GenderButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color accent;
  final Color surface;
  final Color textPrimary;
  final VoidCallback onTap;

  const _GenderButton({
    required this.label,
    required this.isSelected,
    required this.accent,
    required this.surface,
    required this.textPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? accent : surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accent : accent.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? surface : textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
