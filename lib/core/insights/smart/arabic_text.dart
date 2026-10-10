// Small Arabic grammar helpers for generated text: counted nouns that agree
// with their number, category names with the definite article, and
// prepositions joined the way they are written.

// One noun (with any adjective) in each form Arabic counting needs.
class ArabicCount {
  // 1: the full phrase without the digit ("يوم واحد").
  final String one;
  // 2: dual, accusative/genitive ("يومين").
  final String two;
  // 3-10: plural ("أيام").
  final String few;
  // 11-99: singular accusative ("يوماً").
  final String many;
  // 100, 200...: singular genitive ("يوم").
  final String hundred;

  const ArabicCount({
    required this.one,
    required this.two,
    required this.few,
    required this.many,
    required this.hundred,
  });

  String of(int n) {
    if (n == 1) return one;
    if (n == 2) return two;
    final rest = n >= 100 ? n % 100 : n;
    if (n >= 100 && rest <= 2) return '$n $hundred';
    if (rest >= 3 && rest <= 10) return '$n $few';
    return '$n $many';
  }
}

class Ar {
  Ar._();

  static const days = ArabicCount(
    one: 'يوم واحد',
    two: 'يومين',
    few: 'أيام',
    many: 'يوماً',
    hundred: 'يوم',
  );

  static const consecutiveDays = ArabicCount(
    one: 'يوم واحد',
    two: 'يومين متتاليين',
    few: 'أيام متتالية',
    many: 'يوماً متتالياً',
    hundred: 'يوم متتالٍ',
  );

  static const expenses = ArabicCount(
    one: 'مصروف واحد',
    two: 'مصروفين',
    few: 'مصاريف',
    many: 'مصروفاً',
    hundred: 'مصروف',
  );

  static const smallExpenses = ArabicCount(
    one: 'مصروف صغير واحد',
    two: 'مصروفين صغيرين',
    few: 'مصاريف صغيرة',
    many: 'مصروفاً صغيراً',
    hundred: 'مصروف صغير',
  );

  static const times = ArabicCount(
    one: 'مرة واحدة',
    two: 'مرتين',
    few: 'مرات',
    many: 'مرة',
    hundred: 'مرة',
  );

  static const goals = ArabicCount(
    one: 'هدف واحد',
    two: 'هدفين',
    few: 'أهداف',
    many: 'هدفاً',
    hundred: 'هدف',
  );

  static const activeGoals = ArabicCount(
    one: 'هدف نشط واحد',
    two: 'هدفان نشطان',
    few: 'أهداف نشطة',
    many: 'هدفاً نشطاً',
    hundred: 'هدف نشط',
  );

  static const items = ArabicCount(
    one: 'عنصر واحد',
    two: 'عنصرين',
    few: 'عناصر',
    many: 'عنصراً',
    hundred: 'عنصر',
  );

  static const months = ArabicCount(
    one: 'شهر واحد',
    two: 'شهرين',
    few: 'أشهر',
    many: 'شهراً',
    hundred: 'شهر',
  );

  static final RegExp _singleArabicWord = RegExp(r'^[ء-ي]+$');

  // A category as a definite noun: "طعام" -> "الطعام". Names that cannot
  // take the article (several words, Latin, «أخرى») become "تصنيف «…»".
  static String category(String name) {
    final trimmed = name.trim();
    if (trimmed == 'أخرى' || !_singleArabicWord.hasMatch(trimmed)) {
      return 'تصنيف «$trimmed»';
    }
    return trimmed.startsWith('ال') ? trimmed : 'ال$trimmed';
  }

  // لِـ joined to a definite noun: "الطعام" -> "للطعام".
  static String li(String phrase) =>
      phrase.startsWith('ال') ? 'لل${phrase.substring(2)}' : 'ل$phrase';

  // بِـ joined: "الطعام" -> "بالطعام".
  static String bi(String phrase) => 'ب$phrase';

  static String quote(String name) => '«${name.trim()}»';

  static const Map<int, String> weekdays = {
    DateTime.saturday: 'السبت',
    DateTime.sunday: 'الأحد',
    DateTime.monday: 'الاثنين',
    DateTime.tuesday: 'الثلاثاء',
    DateTime.wednesday: 'الأربعاء',
    DateTime.thursday: 'الخميس',
    DateTime.friday: 'الجمعة',
  };
}
