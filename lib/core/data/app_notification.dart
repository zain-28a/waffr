import 'dart:convert';

/// تصنيف الحدث الذي أنتج الإشعار.
enum NotificationType {
  balanceWarning,
  highSpending,
  goalReached,
  goalProgress,
  savingsTransferred,
  recurringPeriodCompleted,
  largeExpense,
  recurringExpenseBlocked,
}

/// وزن بصري خفيف، بدون ألوان جديدة.
enum NotificationPriority { warning, important, success, savings, info }

/// حدود مركزية لكل أنواع الإشعارات المعتمدة على نسب.
class NotificationThresholds {
  static const List<int> remainingPercents = [30, 20, 10];
  static const List<int> spendingPercents = [50, 70, 80, 90];
  static const List<int> goalPercents = [25, 50, 75];
  static const double largeExpenseMultiplier = 2.0;
  static const int minExpensesForLarge = 4;
}

/// إشعار واحد كما يُحفظ في SharedPreferences.
class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final String eventKey;
  final String? relatedId;
  final Map<String, String> metadata;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.eventKey,
    this.isRead = false,
    this.relatedId,
    this.metadata = const {},
  });

  NotificationPriority get priority => switch (type) {
        NotificationType.balanceWarning => NotificationPriority.warning,
        NotificationType.highSpending => NotificationPriority.important,
        NotificationType.largeExpense => NotificationPriority.important,
        NotificationType.goalReached => NotificationPriority.success,
        NotificationType.goalProgress => NotificationPriority.success,
        NotificationType.savingsTransferred => NotificationPriority.savings,
        NotificationType.recurringPeriodCompleted => NotificationPriority.info,
        NotificationType.recurringExpenseBlocked => NotificationPriority.warning,
      };

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      message: message,
      createdAt: createdAt,
      eventKey: eventKey,
      isRead: isRead ?? this.isRead,
      relatedId: relatedId,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'message': message,
        'createdAt': createdAt.toIso8601String(),
        'isRead': isRead,
        'eventKey': eventKey,
        'relatedId': relatedId,
        'metadata': metadata,
      };

  String encode() => jsonEncode(toJson());

  static AppNotification? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final title = decoded['title']?.toString().trim() ?? '';
      final message = decoded['message']?.toString().trim() ?? '';
      final eventKey = decoded['eventKey']?.toString().trim() ?? '';
      if (title.isEmpty || eventKey.isEmpty) return null;

      final metadata = <String, String>{};
      final rawMeta = decoded['metadata'];
      if (rawMeta is Map) {
        rawMeta.forEach((key, value) {
          if (value == null) return;
          metadata[key.toString()] = value.toString();
        });
      }

      return AppNotification(
        id: decoded['id']?.toString() ?? newId(),
        type: _parseType(decoded['type']?.toString()),
        title: title,
        message: message,
        createdAt:
            DateTime.tryParse(decoded['createdAt']?.toString() ?? '') ??
                DateTime.now(),
        isRead: decoded['isRead'] == true,
        eventKey: eventKey,
        relatedId: _text(decoded['relatedId']),
        metadata: metadata,
      );
    } catch (_) {
      return null;
    }
  }

  static int _seq = 0;

  static String newId() =>
      'n${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  static NotificationType _parseType(String? raw) {
    return switch (raw) {
      'balanceWarning' => NotificationType.balanceWarning,
      'highSpending' => NotificationType.highSpending,
      'goalReached' => NotificationType.goalReached,
      'goalProgress' => NotificationType.goalProgress,
      'savingsTransferred' => NotificationType.savingsTransferred,
      'recurringPeriodCompleted' => NotificationType.recurringPeriodCompleted,
      'largeExpense' => NotificationType.largeExpense,
      'recurringExpenseBlocked' => NotificationType.recurringExpenseBlocked,
      _ => NotificationType.recurringPeriodCompleted,
    };
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
