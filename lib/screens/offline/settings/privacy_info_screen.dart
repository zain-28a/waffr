import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';

class PrivacyInfoScreen extends StatelessWidget {
  const PrivacyInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness ==
            Brightness.dark;

    final bg = isDark
        ? AppColors.darkBackground
        : AppColors.lightBackground;

    final surface = isDark
        ? AppColors.darkSurface
        : AppColors.lightSurface;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    final accent = isDark
        ? AppColors.darkAccent
        : AppColors.lightAccent;

    return Scaffold(
      backgroundColor: bg,

      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,

        title: Text(
          'الخصوصية والبيانات',

          style: TextStyle(
            color: textPrimary,
            fontWeight:
                FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),

        leading: IconButton(
          icon: Icon(
            Icons.arrow_forward_ios_rounded,
            color: textPrimary,
          ),

          onPressed: () =>
              Navigator.pop(context),
        ),
      ),

      body: ListView(
        padding:
            const EdgeInsets.all(20),

        children: [
          _InfoSection(
            icon: Icons.visibility_off_outlined,
            title: 'خصوصيتك المالية',
            description:
                'وفر لا يطّلع على بياناتك المالية ولا يقرأها ولا يشاركها مع أي جهة. رصيدك، أهدافك، تفاصيل مصروفاتك، ونشاط حسابك المالي تبقى خاصة بك وحدك على جهازك.',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),

          const SizedBox(height: 16),

          _InfoSection(
            icon: Icons.badge_outlined,
            title: 'ما الذي يُحفظ عنك؟',
            description:
                'نحفظ فقط معلومات حساب أساسية: الاسم، الجنس، العمر، والبريد الإلكتروني. الهدف منها الاحتفاظ بسجل المستخدم وفهم طبيعة المستخدمين بشكل عام، وليس متابعة سلوكك المالي أو الاطلاع على مصروفاتك.',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),

          const SizedBox(height: 16),

          _InfoSection(
            icon: Icons.person_off_outlined,
            title: 'وضع الضيف',
            description:
                'إذا كنت تستخدم التطبيق كضيف، فكل بياناتك تُحفظ على جهازك فقط. لا تُرسل إلى أي مكان ولا تُخزَّن على أي خادم خارجي.',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),

          const SizedBox(height: 16),

          _InfoSection(
            icon: Icons.storage_rounded,
            title: 'تخزين البيانات',
            description:
                'بياناتك المالية تُحفظ محلياً على جهازك. إذا ربطت حساب Google، تُحفظ نسخة احتياطية في مجلد تطبيقك الخاص على Drive لاستعادتها عند الحاجة، دون أن نستخدمها لمتابعة نشاطك المالي.',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),

          const SizedBox(height: 16),

          _InfoSection(
            icon: Icons.phone_android_rounded,
            title: 'التشغيل دون اتصال',
            description:
                'عندما يعمل التطبيق في وضع عدم الاتصال بالإنترنت (Offline)، تبقى جميع بياناتك على جهازك. لا يحتاج التطبيق إلى الإنترنت للعمل، وبياناتك محفوظة محلياً فقط.',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),

          const SizedBox(height: 16),

          _InfoSection(
            icon: Icons.lock_outline_rounded,
            title: 'حماية الوصول',
            description:
                'عند تفعيل "قفل التطبيق"، يتم حماية الوصول إلى التطبيق باستخدام مصادقة الجهاز (البصمة، التعرف على الوجه، رمز PIN، أو النمط). هذا يمنع أي شخص من فتح التطبيق دون إذنك.',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),

          const SizedBox(height: 16),

          _InfoSection(
            icon: Icons.delete_outline_rounded,
            title: 'إعادة ضبط التطبيق',
            description:
                'عند إعادة ضبط التطبيق من الإعدادات، يتم حذف جميع بياناتك المحلية بشكل دائم من جهازك: معلوماتك الشخصية، الرصيد، سجل المصاريف والدخل، أهداف التوفير، والإشعارات. هذا الإجراء لا يمكن التراجع عنه.',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 30),

          Container(
            padding:
                const EdgeInsets.all(18),

            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius:
                  BorderRadius.circular(20),

              border: Border.all(
                color: accent.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),

            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: accent,
                      size: 28,
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Text(
                        'بياناتك تحت سيطرتك الكاملة ولا تغادر جهازك.',

                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              FontWeight.w600,
                          color: textPrimary,
                          fontFamily: 'Cairo',
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: accent,
                      size: 28,
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Text(
                        'أنت من يقرر أي بيانات يمكن استخدامها لميزات الذكاء الاصطناعي.',

                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              FontWeight.w600,
                          color: textPrimary,
                          fontFamily: 'Cairo',
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _InfoSection
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  final Color accent;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;

  const _InfoSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.accent,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: surface,
        borderRadius:
            BorderRadius.circular(20),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,

                decoration:
                    BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
                ),

                child: Icon(
                  icon,
                  color: accent,
                  size: 24,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Text(
                  title,

                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.bold,
                    color: textPrimary,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            description,

            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: textSecondary,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }
}
