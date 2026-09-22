import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/widgets/brand/waffer_page_header.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const sections = <({String title, List<({String question, String answer})> items})>[
      (
        title: 'الرصيد والدخل',
        items: [
          (
            question: 'كيف أضيف دخلاً إلى الرصيد؟',
            answer:
                'من الشاشة الرئيسية اضغط «إضافة دخل»، ثم أدخل المبلغ. اختر «مدة المبلغ»: «شهري» أو «بدون مدة». إذا كان لديك رصيد حالياً يمكنك إبقاؤه أو نقله إلى التوفير. مصدر الدخل اختياري. ثم اضغط «حفظ الدخل». يُسجَّل الوقت حسب ساعة جهازك مباشرة، حتى لو لم يكن هناك اتصال.',
          ),
          (
            question: 'ماذا تعني «مدة المبلغ» و«نقل الرصيد للتوفير»؟',
            answer:
                '«شهري» يربط هذا الدخل بالشهر الحالي. عند انتهاء الشهر ينقل وفّر ما تبقى منه، بعد المصروفات والادخار الدوري، إلى التوفير. لا يُضاف دخل جديد تلقائياً. «بدون مدة» لا يجري هذا النقل. «نقل الرصيد للتوفير» ينقل رصيدك الحالي كله إلى التوفير قبل إضافة الدخل الجديد.',
          ),
          (
            question: 'كيف أحدد الدخل الشهري أو أغيّره أو أزيله؟',
            answer:
                'من الإعدادات اضغط «الدخل الشهري». الخيار ظاهر حتى قبل أن تضبطه. أدخل المبلغ ثم «حفظ» لتحديده أو تغييره، أو «إزالة الدخل» لإلغائه بالكامل. الإزالة لا تحذف الدخل المسجّل سابقاً في السجل، لكنها توقف الخطط الدورية التي تعتمد على نسبة من الدخل، وتوقف خصم المصروفات المتكررة إلى أن تعيد ضبط الدخل.',
          ),
          (
            question: 'كيف يُحسب الرصيد الحالي؟',
            answer:
                'الرصيد الحالي هو مجموع الدخل المسجّل ناقص مجموع المصروفات وناقص المبلغ الموجود حالياً في التوفير. ادخار مبلغ يقلّل الرصيد المتاح، وسحبه يعيده إليه.',
          ),
          (
            question: 'كيف أتراجع عن دخل سجّلته؟',
            answer:
                'من بطاقة الرصيد في الشاشة الرئيسية اضغط أيقونة المدفوعات لفتح سجل الدخل. بجانب العملية اضغط أيقونة التراجع، ثم أكّد. يُحذف الدخل من السجل ويُخصم مبلغه من الرصيد، وينعكس ذلك على التقارير والمزامنة.',
          ),
        ],
      ),
      (
        title: 'المصروفات',
        items: [
          (
            question: 'كيف أسجّل مصروفاً؟',
            answer:
                'من الشاشة الرئيسية اضغط «إضافة مصروف»، وأدخل المبلغ، ثم اختر التصنيف. يمكنك إضافة ملاحظة. لا يُحفظ المصروف إذا كان أكبر من الرصيد المتاح. الوقت المسجّل هو وقت جهازك لحظة الحفظ.',
          ),
          (
            question: 'كيف أستخدم المضاعف بجانب المبلغ؟',
            answer:
                'بجانب المبلغ، في الجهة المقابلة لـ «ل.س» وبنفس حجمه، يوجد مضاعف يبدأ من ×1. اضغطه واختر قيمة مثل ×2 أو ×3. المبلغ المحفوظ هو ما كتبته مضروباً في هذه القيمة. عند ×1 يبقى المبلغ كما أدخلته.',
          ),
          (
            question: 'كيف أضيف تصنيفاً خاصاً؟',
            answer:
                'داخل نافذة المصروف، في شبكة التصنيفات، اضغط «مخصص» ثم اختر اسماً وأيقونة. لتعديل تصنيف أضفته أو حذفه، اضغط عليه مطوّلاً.',
          ),
          (
            question: 'لماذا لا أستطيع إنشاء مصروف متكرر؟',
            answer:
                'المصروف المتكرر يحتاج دخلاً شهرياً محدداً من الإعدادات. إذا لم يكن مضبوطاً، يظهر توضيح قصير ولن يُحفظ المصروف المتكرر. اضبط «الدخل الشهري» ثم أعد المحاولة.',
          ),
          (
            question: 'متى يظهر المصروف المتكرر في السجل؟',
            answer:
                'إنشاء المصروف المتكرر لا يخصم مبلغاً فوراً. عند حلول موعده، وإذا كان الدخل الشهري ما زال محدداً والرصيد كافياً، يُسجَّل كمصروف عادي مرة واحدة لذلك الموعد. يظهر في سجل المصاريف ويؤثر في الرصيد والتقارير مثل أي مصروف أدخلته بنفسك. إذا لم يكفِ الرصيد يُؤجَّل الخصم ويصلك تنبيه. إذا أزلت الدخل الشهري يتوقف الخصم إلى أن تعيده.',
          ),
          (
            question: 'كيف أعدّل المصروفات المتكررة أو أوقفها؟',
            answer:
                'من الإعدادات اضغط «المصروفات المتكررة». يمكنك تغيير المبلغ أو إيقاف الخصم التلقائي أو حذف البند.',
          ),
          (
            question: 'كيف أتراجع عن مصروف؟',
            answer:
                'من شاشة التقارير اضغط «سجل المصاريف». بجانب المصروف اضغط أيقونة التراجع ثم أكّد. يُحذف من السجل ويعود مبلغه إلى الرصيد. إذا كان ناتجاً عن شراء من قائمة المشتريات، يعود ذلك العنصر غير مُشترى.',
          ),
          (
            question: 'أين أرى آخر مصروفاتي؟',
            answer:
                'الشاشة الرئيسية تعرض آخر ثلاثة مصروفات. لعرض السجل كاملاً افتح التقارير ثم «سجل المصاريف».',
          ),
        ],
      ),
      (
        title: 'التقارير',
        items: [
          (
            question: 'كيف أقرأ التقارير؟',
            answer:
                'افتح التقارير من رمز الرسم البياني في الشريط السفلي. اختر «اليوم» أو أسبوعاً أو شهراً أو 3 أشهر أو 6 أشهر أو سنة، واستخدم السهمين للتنقل بين الفترات. يعرض التقرير مجموع الصرف، وتوزيعه حسب التصنيف، ومقارنته بالفترة السابقة.',
          ),
          (
            question: 'ماذا يعرض تقرير اليوم؟',
            answer:
                'تقرير «اليوم» يخص اليوم الحالي من منتصف الليل حتى نهايته، ويقسّم الرسم حسب الساعات. الساعة التي لا فيها مصروف تبقى فارغة على الرسم دون أن تعطّل العرض. عند لمس نقطة تظهر الساعة والمبلغ.',
          ),
        ],
      ),
      (
        title: 'التوفير والأهداف',
        items: [
          (
            question: 'كيف أدّخر مبلغاً أو أسحبه؟',
            answer:
                'من شاشة التوفير اضغط «ادخار مبلغ» لنقل مبلغ من الرصيد إلى التوفير، أو «سحب إلى الرصيد» لإعادته. لا يمكنك ادخار أكثر من رصيدك المتاح، ولا سحب أكثر مما هو مدّخر.',
          ),
          (
            question: 'كيف أنشئ هدف توفير؟',
            answer:
                'من شاشة التوفير اضغط «إنشاء هدف». أدخل الاسم والمبلغ المستهدف، ثم اختر طريقة الادخار: نسبة من الدخل، أو مبلغاً ثابتاً كل شهر، أو مبلغاً مخصصاً تدّخره بنفسك. مبلغ الادخار الشهري يقبل الأرقام الكبيرة مثل بقية مبالغ وفّر. راجع المعاينة ثم احفظ.',
          ),
          (
            question: 'لماذا لا أستطيع إنشاء خطة دورية؟',
            answer:
                'الخطة الدورية تُحسب من الدخل الشهري. إذا لم تحدده بعد، يوضح وفّر ذلك ويمنع إنشاء الخطة. اضبط «الدخل الشهري» من الإعدادات أولاً. النسبة من الدخل والمبلغ الثابت في هدف التوفير يحتاجان الدخل الشهري أيضاً، أما «مبلغ مخصص» فيبقى متاحاً بدونه.',
          ),
          (
            question: 'كيف تعمل الخطة الدورية؟',
            answer:
                'من شاشة التوفير اضغط «خطط دورية». اختر نسبة الادخار والمدة، راجع المبلغ الدوري والمستهدف، ثم أكّد. عند اكتمال كل فترة ينقل وفّر مبلغ الخطة من الرصيد المتاح إلى التوفير، بحد ما يتوفر في الرصيد. إذا أزلت الدخل الشهري تتوقف الخطط المعتمدة على النسبة إلى أن تعيد ضبطه.',
          ),
          (
            question: 'كيف يُحسب تقدّم الهدف، وكيف أحذفه؟',
            answer:
                'التقدّم هو ما دخل إلى التوفير لهذا الهدف بعد إنشائه، بعد طرح ما سُحب. عند بلوغ المبلغ المستهدف يكتمل الهدف. الأهداف المكتملة في «الأهداف المحققة». من «إدارة الأهداف» يمكنك ترتيب الأهداف أو حذف هدف. حذف الهدف لا يسحب المال المدّخر.',
          ),
        ],
      ),
      (
        title: 'التسوق',
        items: [
          (
            question: 'كيف أستخدم قائمة المشتريات؟',
            answer:
                'من بطاقة الرصيد اضغط أيقونة القائمة، أو افتحها من شاشة التوفير. أضف ما تريد شراءه. عند تسجيل الشراء يُطلب السعر ويُنشأ مصروف عادي بالمبلغ والوقت الحالي على جهازك، ويظهر في السجل والرصيد. التراجع عن ذلك المصروف يعيد العنصر إلى القائمة.',
          ),
        ],
      ),
      (
        title: 'الإشعارات والوقت',
        items: [
          (
            question: 'كيف تعمل الإشعارات؟',
            answer:
                'رمز الجرس في الشريط السفلي يعرض تنبيهات داخل وفّر عن الرصيد والإنفاق والادخار والأهداف وتعذّر خصم مصروف متكرر. يمكنك فتح تنبيه لتمييزه كمقروء، أو تعيين الكل كمقروء، أو مسح السجل. عند كتم الإشعارات لا تُضاف تنبيهات جديدة.',
          ),
          (
            question: 'هل يعتمد وقت العمليات على الإنترنت؟',
            answer:
                'لا. وقت المصروف والدخل والادخار والشراء والموعد المتكرر هو وقت جهازك لحظة حدوثه. إذا سجّلت مصروفاً الساعة 6 مساءً دون اتصال، يبقى 6 مساءً حتى لو اتصل الجهاز لاحقاً. المزامنة لا تستبدل هذا الوقت بوقت وصول العملية إلى الخادم.',
          ),
        ],
      ),
      (
        title: 'الحساب والمظهر',
        items: [
          (
            question: 'كيف أسجّل الدخول أو أستخدم التطبيق دون حساب؟',
            answer:
                'يمكنك استخدام وفّر على الجهاز دون حساب. من الإعدادات اضغط بطاقة الحساب لتسجيل الدخول أو إنشاء حساب. بعد تسجيل الدخول تُزامَن بياناتك عند توفر الاتصال. تسجيل الخروج يعيدك إلى شاشة الدخول وتبقى بياناتك على الجهاز، ويمكنك المتابعة كضيف.',
          ),
          (
            question: 'كيف أغيّر المظهر؟',
            answer:
                'من الإعدادات استخدم «الوضع الداكن». العربية هي اللغة الوحيدة في هذه النسخة.',
          ),
        ],
      ),
      (
        title: 'الحماية والبيانات',
        items: [
          (
            question: 'كيف يعمل قفل التطبيق؟',
            answer:
                'من الإعدادات فعّل «قفل التطبيق» ثم أكّد بهوية جهازك. وفّر لا ينشئ رمزاً خاصاً، بل يستخدم قفل الشاشة أو البصمة أو الوجه المعدّ على الجهاز. عند مغادرة التطبيق تُطلب المصادقة من جديد عبر «فتح القفل».',
          ),
          (
            question: 'ماذا لو لم تعمل البصمة؟',
            answer:
                'تأكد من إعداد قفل الشاشة على جهازك. قد تسمح نافذة النظام برمز الجهاز أو نمطه. إذا ألغيت المحاولة ابقَ في شاشة القفل واضغط «فتح القفل» مرة أخرى. الأجهزة التي لا تدعم مصادقة الجهاز لا يمكن تفعيل القفل عليها.',
          ),
          (
            question: 'ماذا يحدث عند إعادة ضبط التطبيق؟',
            answer:
                'بعد تأكيد حذف البيانات يمسح وفّر ما على هذا الجهاز: الملف، والدخل والمصروفات والتوفير والأهداف والمصروفات المتكررة وقائمة المشتريات والإشعارات والمظهر وقفل التطبيق. لا يمكن التراجع. عند تسجيل الدخول قد تُستعاد النسخة المتزامنة مع الحساب، أما البيانات التي لم تُزامَن فتُحذف من الجهاز.',
          ),
        ],
      ),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    return Scaffold(
      backgroundColor: bg,
      appBar: WafferPageHeader(
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_forward_ios_rounded, color: textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'المساعدة',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'دليل وفّر',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: textPrimary,
              fontFamily: 'Tajawal',
            ),
          ),
          const SizedBox(height: 5),
          
          const SizedBox(height: 22),
          for (final section in sections) ...[
            Text(
              section.title,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < section.items.length; index++) ...[
              if (index > 0) const SizedBox(height: 12),
              _FAQItem(
                question: section.items[index].question,
                answer: section.items[index].answer,
                accent: accent,
                surface: surface,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              ),
            ],
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }
}

class _FAQItem extends StatefulWidget {
  final String question;
  final String answer;
  final Color accent;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;

  const _FAQItem({
    required this.question,
    required this.answer,
    required this.accent,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  State<_FAQItem> createState() => _FAQItemState();
}

class _FAQItemState extends State<_FAQItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.only(
            right: 16,
            left: 16,
            bottom: 16,
          ),
          trailing: Icon(
            _isExpanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            color: widget.accent,
          ),
          onExpansionChanged: (expanded) {
            setState(() {
              _isExpanded = expanded;
            });
          },
          title: Text(
            widget.question,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: widget.textPrimary,
              fontFamily: 'Tajawal',
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                widget.answer,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: widget.textSecondary,
                  fontFamily: 'Tajawal',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
