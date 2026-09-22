import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/backup_service.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/widgets/button/ani_pri_button.dart';

enum Gender { male, female }

class UserInfoScreen extends StatefulWidget {
  final VoidCallback onContinue;

  const UserInfoScreen({super.key, required this.onContinue});

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  Gender? _selectedGender;
  DateTime? _birthDate;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingData() async {
    final prefs = await SharedPreferences.getInstance();

    final email = prefs.getString('user_email') ?? '';
    final name = prefs.getString('user_name') ?? '';
    final address = _existingAddress(prefs);
    final gender = prefs.getString('user_gender');
    final birthdate = prefs.getString('user_birthdate');

    if (!mounted) return;

    setState(() {
      _emailController.text = email;
      _nameController.text = name;
      _addressController.text = address;

      if (gender == 'male') {
        _selectedGender = Gender.male;
      } else if (gender == 'female') {
        _selectedGender = Gender.female;
      }

      if (birthdate != null) {
        _birthDate = DateTime.tryParse(birthdate);
      }
    });
  }

  bool get _isFormValid {
    final emailValid = _emailController.text.trim().contains('@') &&
        _emailController.text.trim().contains('.');
    final nameValid = _nameController.text.trim().isNotEmpty;
    final birthValid = _birthDate != null;
    return emailValid && nameValid && birthValid;
  }

  Future<void> _pickBirthDate(Color accent) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
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

  /// عنوان واحد. إن وُجدت حقول قديمة منفصلة تُجمع هنا مرة واحدة.
  String _existingAddress(SharedPreferences prefs) {
    final stored = prefs.getString('user_address')?.trim() ?? '';
    if (stored.isNotEmpty) return stored;

    return [
      prefs.getString('user_country'),
      prefs.getString('user_city'),
      prefs.getString('user_street'),
    ]
        .map((part) => part?.trim() ?? '')
        .where((part) => part.isNotEmpty)
        .join('، ');
  }

  Future<void> _saveAndContinue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_email', _emailController.text.trim());
    await prefs.setString('user_name', _nameController.text.trim());
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      await prefs.remove('user_address');
    } else {
      await prefs.setString('user_address', address);
    }
    await prefs.remove('user_country');
    await prefs.remove('user_city');
    await prefs.remove('user_street');
    if (_selectedGender != null) {
      await prefs.setString('user_gender', _selectedGender == Gender.male ? 'male' : 'female');
    }
    if (_birthDate != null) {
      await prefs.setString('user_birthdate', _birthDate!.toIso8601String());
    }
    BackupService.instance.scheduleBackup();

    widget.onContinue();
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

              // ===== الإيميل =====
              _FieldLabel(text: 'البريد الإلكتروني :', color: textPrimary),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: textPrimary, fontSize: 16),
                decoration: _fieldDecoration(
                  hint: 'example@gmail.com',
                  fillColor: surface,
                  textSecondary: textSecondary,
                ),
              ),

              const SizedBox(height: 24),

              // ===== الاسم =====
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

              // ===== الجنس (اختياري) =====
              _FieldLabel(text: 'الجنس (اختياري)', color: textPrimary),
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

              // ===== تاريخ الميلاد =====
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

              const SizedBox(height: 24),

              // ===== العنوان (اختياري) =====
              _FieldLabel(text: 'العنوان (اختياري)', color: textPrimary),
              const SizedBox(height: 8),
              TextField(
                controller: _addressController,
                textAlign: TextAlign.right,
                textInputAction: TextInputAction.done,
                style: TextStyle(color: textPrimary, fontSize: 16),
                decoration: _fieldDecoration(
                  hint: 'البلد، المدينة، الشارع',
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
                onPressed: _isFormValid ? _saveAndContinue : () {},
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