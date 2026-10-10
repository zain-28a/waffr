// Opt-in switches for the AI features and what each one sends.

import 'package:flutter/material.dart';
import 'package:waffr/core/sync/auth_session.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/data/services/ai_insights_service.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';
import 'package:waffr/widgets/containers/app_list_tile.dart';
import 'package:waffr/widgets/containers/glass.dart';

class AIPermissionsScreen extends StatefulWidget {
  const AIPermissionsScreen({super.key});

  @override
  State<AIPermissionsScreen> createState() => _AIPermissionsScreenState();
}

class _AIPermissionsScreenState extends State<AIPermissionsScreen> {
  final AiInsightsService _service = AiInsightsService.instance;

  // Null while checking; AI requests go through the account, so guests
  // see why the switches are off.
  bool? _signedIn;

  @override
  void initState() {
    super.initState();
    _service.ensureLoaded();
    AuthSession.instance.isLoggedIn().then((value) {
      if (mounted) setState(() => _signedIn = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final canUse = _signedIn == true;

    return Scaffold(
      backgroundColor: background,
      appBar: WaffrBackHeader(
        title: 'أذونات الذكاء الاصطناعي',
      ),
      body: AnimatedBuilder(
        animation: _service,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              if (_signedIn == false) ...[
                const AppListTile(
                  icon: Icons.person_outline_rounded,
                  title: 'تحتاج إلى حساب',
                  subtitle:
                      'تعمل ميزات الذكاء الاصطناعي عبر حسابك. سجّل الدخول لتفعيلها.',
                  showChevron: false,
                ),
                const SizedBox(height: 16),
              ],
              const AppSectionTitle(title: 'الميزات'),
              AppListTile(
                icon: Icons.auto_graph_rounded,
                title: 'تحليلات واقتراحات',
                subtitle:
                    'رؤى أسبوعية في الرئيسية، ملخص الشهر في التقارير، واقتراح مبلغ توفير',
                showChevron: false,
                trailing: Switch(
                  value: _service.insightsEnabled,
                  activeThumbColor: accent,
                  onChanged: canUse ? _service.setInsightsEnabled : null,
                ),
                onTap: canUse
                    ? () => _service.setInsightsEnabled(
                          !_service.insightsEnabled,
                        )
                    : null,
              ),
              const SizedBox(height: 10),
              AppListTile(
                icon: Icons.category_outlined,
                title: 'تصنيف تلقائي للمصروف',
                subtitle: 'يقترح التصنيف من الملاحظة التي تكتبها',
                showChevron: false,
                trailing: Switch(
                  value: _service.categorizeEnabled,
                  activeThumbColor: accent,
                  onChanged: canUse ? _service.setCategorizeEnabled : null,
                ),
                onTap: canUse
                    ? () => _service.setCategorizeEnabled(
                          !_service.categorizeEnabled,
                        )
                    : null,
              ),
              const SizedBox(height: 22),
              const AppSectionTitle(title: 'ما الذي يُرسَل'),
              GlassContainer(
                colorType: GlassColorType.surface,
                borderRadius: 22,
                padding: const EdgeInsets.all(16),
                child: Text(
                  'التحليلات: مجاميع الصرف لكل تصنيف، الرصيد، الدخل، '
                  'أهداف التوفير والالتزامات. لا تُرسَل العمليات المفردة ولا ملاحظاتها.\n\n'
                  'التصنيف التلقائي: نص الملاحظة وأسماء التصنيفات فقط.\n\n'
                  'تُرسَل البيانات عبر خادم وفّر إلى نموذج Claude من Anthropic '
                  'لتوليد النتيجة، ولا تُستخدم لأي غرض آخر. '
                  'إيقاف الميزة يحذف النتائج المحفوظة على هذا الجهاز.',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontFamilyFallback: const ['Tajawal'],
                    fontSize: 13,
                    height: 1.6,
                    color: textSecondary,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
