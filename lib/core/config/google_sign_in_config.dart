/// إعدادات ربط حساب Google.
///
/// تسجيل الدخول اختياري بالكامل: إذا لم تُضبط هذه القيم
/// يبقى التطبيق يعمل بوضع الضيف والتخزين المحلي فقط.
///
/// خطوات الإعداد:
///
/// Android:
///  - سجّل التطبيق في Google Cloud Console أو Firebase
///    باسم الحزمة `com.example.waffer` وبصمة SHA-1 لكل نسخة بناء.
///  - إمّا تضع `google-services.json` داخل `android/app/`
///    (ويجب أن يحتوي على `oauth_client` بنوع `client_type: 3`)
///    وعندها تترك [serverClientId] فارغاً،
///  - أو تضع معرّف عميل الويب في [serverClientId].
///
/// iOS/macOS:
///  - ضع `GoogleService-Info.plist` في مشروع Xcode،
///    أو ضع معرّف عميل iOS في [clientId].
///
/// في كل الحالات فعّل Google Drive API من Google Cloud Console.
class GoogleSignInConfig {
  GoogleSignInConfig._();

  /// معرّف عميل iOS/macOS. اتركه `null` عند استخدام ملف plist.
  static const String? clientId = null;

  /// معرّف عميل الويب المستخدم على Android.
  /// اتركه `null` عند استخدام `google-services.json`.
  static const String? serverClientId =
      '111706237253-n2l64h07it6jgebqbco4mnhgr8r991b0.apps.googleusercontent.com';

  /// نطاق الوصول لمجلد بيانات التطبيق المخفي في Google Drive.
  ///
  /// هذا النطاق لا يمنح أي وصول لملفات المستخدم الشخصية،
  /// بل لمجلد خاص بالتطبيق فقط.
  static const List<String> driveScopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];
}
