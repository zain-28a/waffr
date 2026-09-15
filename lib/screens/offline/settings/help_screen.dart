import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const faqs = <({String question, String answer})>[
      (
        question: 'كيف أضيف دخلاً إلى الرصيد؟',
        answer: 'من الشاشة الرئيسية اضغط «إضافة دخل»، ثم أدخل «مبلغ الدخل». حدّد «مدة المبلغ» واختر ما سيحدث للرصيد الحالي إن ظهر هذا الخيار، وأضف مصدر الدخل اختيارياً، ثم اضغط «حفظ الدخل».',
      ),
      (
        question: 'ماذا تعني «مدة المبلغ» و«نقل الرصيد للتوفير»؟',
        answer: 'اختيار «أسبوعي» أو «شهري» يربط الدخل بتلك الفترة، وعند انتهائها ينقل وفّر ما تبقى منها بعد المصروفات والادخار الدوري إلى التوفير. لا يُضاف دخل جديد تلقائياً. أما «بدون مدة» فلا يجري هذا النقل. وإذا اخترت «نقل الرصيد للتوفير»، ينتقل رصيدك الحالي كله إلى التوفير قبل إضافة الدخل الجديد.',
      ),
      (
        question: 'كيف أسجّل مصروفاً؟',
        answer: 'من الشاشة الرئيسية اضغط «إضافة مصروف»، وأدخل المبلغ، ثم اختر التصنيف وطريقة الدفع. يمكنك إضافة ملاحظة اختيارية، وبعد ذلك اضغط «حفظ المصروف». لا يمنع التطبيق تسجيل مبلغ أكبر من الرصيد المتاح، وقد يصبح الرصيد سالباً.',
      ),
      (
        question: 'كيف يُحسب الرصيد الحالي؟',
        answer: 'الرصيد الحالي هو مجموع الدخل المسجّل ناقص مجموع المصروفات وناقص المبلغ الموجود حالياً في التوفير. ادخار مبلغ يقلّل الرصيد المتاح للصرف، وسحبه إلى الرصيد يعيده إليه.',
      ),
      (
        question: 'أين أراجع مصروفاتي السابقة؟',
        answer: 'تعرض الشاشة الرئيسية آخر ثلاثة مصروفات. لعرض جميع المصروفات، افتح شاشة التقارير من رمز الرسم البياني في الشريط السفلي، ثم اضغط «سجل المصاريف»؛ ستظهر المصروفات مرتبة حسب اليوم مع المبلغ والتصنيف والملاحظة والتاريخ.',
      ),
      (
        question: 'كيف أستخدم التقارير؟',
        answer: 'افتح شاشة التقارير من رمز الرسم البياني في الشريط السفلي. اختر أسبوعاً أو شهراً أو 3 أشهر أو 6 أشهر أو سنة، واستخدم السهمين للتنقل بين الفترات. يعرض التقرير الصرف خلال الفترة، وتوزيع المصروفات حسب التصنيف، والمقارنة بالفترة السابقة.',
      ),
      (
        question: 'كيف أدّخر مبلغاً أو أسحبه؟',
        answer: 'افتح شاشة التوفير من رمز وفّر في منتصف الشريط السفلي. اضغط «ادخار مبلغ» لنقل مبلغ من الرصيد التشغيلي إلى التوفير، أو «سحب إلى الرصيد» لإعادته. لا يمكنك ادخار أكثر من رصيدك المتاح أو سحب أكثر من المبلغ المدّخر.',
      ),
      (
        question: 'كيف أنشئ هدف توفير؟',
        answer: 'سجّل دخلاً أسبوعياً أو شهرياً أولاً، ثم افتح شاشة التوفير واضغط «إنشاء هدف». أدخل اسم الهدف والمبلغ المستهدف، واختر الادخار كنسبة من الدخل أو كمبلغ ثابت لكل فترة، وراجع المعاينة ثم اضغط «حفظ الهدف». يمكن أن يكون لديك هدف نشط واحد فقط، ولا تتوفر حالياً إمكانية تعديل الهدف أو حذفه.',
      ),
      (
        question: 'كيف تعمل الخطط الدورية؟',
        answer: 'بعد تسجيل دخل أسبوعي أو شهري، افتح شاشة التوفير واضغط «خطط دورية». اختر نسبة الادخار والمدة، ثم راجع المبلغ الدوري والمبلغ المستهدف واضغط «تأكيد الخطة». عند اكتمال كل فترة، ينقل وفّر مبلغ الخطة من الرصيد المتاح إلى التوفير بحد أقصى ما يتوفر في الرصيد.',
      ),
      (
        question: 'كيف يُحسب تقدّم الهدف وأين أرى الأهداف المحققة؟',
        answer: 'يُحسب التقدّم من صافي ما دخل إلى التوفير بعد إنشاء الهدف، بعد طرح ما سُحب منه. عندما يبلغ التقدّم المبلغ المستهدف، يكتمل الهدف تلقائياً. لعرض الأهداف المكتملة اضغط «الأهداف المحققة» في شاشة التوفير.',
      ),
      (
        question: 'كيف أعدّل معلوماتي الشخصية؟',
        answer: 'افتح الإعدادات واضغط بطاقة الملف الشخصي في أعلى الشاشة. عدّل البريد الإلكتروني أو الاسم أو الجنس أو تاريخ الميلاد، ثم اضغط «متابعة» للحفظ. الاسم والبريد الإلكتروني الصحيح وتاريخ الميلاد مطلوبة، أما الجنس فاختياري.',
      ),
      (
        question: 'كيف أغيّر مظهر التطبيق أو لغته؟',
        answer: 'من الإعدادات استخدم مفتاح «الوضع الداكن» للتبديل بين المظهر الفاتح والداكن. العربية هي اللغة الوحيدة المتاحة حالياً، لذلك لا يوجد خيار لتغيير اللغة في هذه النسخة.',
      ),
      (
        question: 'كيف يعمل قفل التطبيق عند تفعيله أو عند مغادرة وفّر؟',
        answer: 'فعّل «قفل التطبيق» من الإعدادات، ثم أكّد هويتك بحماية الجهاز. لا ينشئ وفّر رمزاً منفصلاً، بل يستخدم الطريقة التي أعددتها على جهازك. عند انتقال التطبيق إلى الخلف تُلغى المصادقة الحالية، وعند العودة إلى مسار التطبيق المقفل استخدم «فتح القفل» للدخول من جديد.',
      ),
      (
        question: 'ماذا أفعل إذا لم تعمل البصمة أو مصادقة الجهاز؟',
        answer: 'تأكد من إعداد قفل الشاشة والبصمة أو التعرف على الوجه في إعدادات جهازك. قد تسمح نافذة النظام باستخدام رمز الجهاز أو نمطه لأن وفّر يستخدم حماية الجهاز. إذا ألغيت المحاولة أو فشلت، ابقَ في شاشة «مقفل» واضغط «فتح القفل» للمحاولة مجدداً. الأجهزة التي لا تدعم مصادقة الجهاز لا يمكن تفعيل القفل عليها.',
      ),
      (
        question: 'كيف تعمل الإشعارات؟',
        answer: 'يعرض رمز الجرس في الشريط السفلي تنبيهات داخل وفّر عن الرصيد والإنفاق والادخار وتقدّم الأهداف. يمكنك فتح تنبيه لتمييزه كمقروء، أو تعيين الكل كمقروء، أو مسح السجل فقط. عند كتم الإشعارات لن تُضاف تنبيهات جديدة إلى السجل.',
      ),
      
      (
        question: 'ماذا يحدث عند إعادة ضبط التطبيق؟',
        answer: 'بعد تأكيد «حذف البيانات»، يمسح وفّر جميع بياناته المحلية: معلومات الملف الشخصي، والدخل والمصروفات وحركات التوفير، والأهداف، وسجل الإشعارات وإعداد الكتم، وأذونات الذكاء الاصطناعي، والمظهر، وقفل التطبيق. لا يمكن التراجع عن ذلك، وعند تشغيل التطبيق من جديد ستبدأ الإعداد من البداية. لا يتضمن هذا الإجراء حذفاً من أي خدمة خارج مساحة التخزين المحلية.',
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
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'المساعدة',
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_forward_ios_rounded, color: textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'الأسئلة الشائعة',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: textPrimary,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'إجابات للأسئلة الأكثر شيوعاً',
            style: TextStyle(
              fontSize: 14,
              color: textSecondary,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 25),

          for (var index = 0; index < faqs.length; index++) ...[
            if (index > 0) const SizedBox(height: 12),
            _FAQItem(
              question: faqs[index].question,
              answer: faqs[index].answer,
              accent: accent,
              surface: surface,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
          ],

          const SizedBox(height: 30),
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
              fontFamily: 'Cairo',
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
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
