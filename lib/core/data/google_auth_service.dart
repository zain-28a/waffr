import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:waffer/core/config/google_sign_in_config.dart';

/// غلاف بسيط حول `google_sign_in`.
///
/// كل العمليات هنا تفشل بصمت وترجع `null` أو `false`،
/// لأن تسجيل الدخول ميزة اختيارية ولا يجوز أن تعطّل
/// عمل التطبيق دون إنترنت أو دون إعداد صحيح.
class GoogleAuthService extends ChangeNotifier {
  GoogleAuthService._();

  static final GoogleAuthService instance = GoogleAuthService._();

  GoogleSignInAccount? _currentUser;
  Future<bool>? _initializer;
  bool _initialized = false;

  /// الحساب المسجّل حالياً، أو `null` في وضع الضيف.
  GoogleSignInAccount? get currentUser => _currentUser;

  bool get isSignedIn => _currentUser != null;

  String? get email => _currentUser?.email;

  String? get displayName => _currentUser?.displayName;

  String? get photoUrl => _currentUser?.photoUrl;

  /// يهيّئ الإضافة مرة واحدة. يرجع `false` إذا كان الإعداد ناقصاً.
  Future<bool> ensureInitialized() {
    return _initializer ??= _initialize();
  }

  Future<bool> _initialize() async {
    try {
      await GoogleSignIn.instance.initialize(
        clientId: GoogleSignInConfig.clientId,
        serverClientId: GoogleSignInConfig.serverClientId,
      );

      _initialized = true;

      return true;
    } catch (_) {
      // إعداد ناقص أو منصة غير مدعومة: نكمل بوضع الضيف.
      _initializer = null;

      return false;
    }
  }

  /// محاولة استعادة الجلسة السابقة دون أي تفاعل من المستخدم.
  Future<GoogleSignInAccount?> restoreSession() async {
    if (!await ensureInitialized()) {
      return null;
    }

    try {
      final account =
          await GoogleSignIn.instance.attemptLightweightAuthentication();

      _setUser(account);

      return account;
    } catch (_) {
      return null;
    }
  }

  /// تسجيل دخول تفاعلي. يرجع `null` عند الإلغاء أو الفشل.
  Future<GoogleSignInAccount?> signIn() async {
    if (!await ensureInitialized()) {
      return null;
    }

    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      return null;
    }

    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: GoogleSignInConfig.driveScopes,
      );

      _setUser(account);

      // `scopeHint` غير مضمون على كل المنصات، لذلك يُطلب
      // إذن Drive صراحة أثناء تفاعل المستخدم.
      try {
        await account.authorizationClient.authorizeScopes(
          GoogleSignInConfig.driveScopes,
        );
      } catch (_) {
        // الهوية نجحت؛ المزامنة ستُعاد لاحقاً إن توفّر الإذن.
      }

      return account;
    } catch (_) {
      // يشمل إلغاء المستخدم وأخطاء الإعداد والشبكة.
      return null;
    }
  }

  Future<void> signOut() async {
    if (_initialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // لا يمنع الخروج محلياً.
      }
    }

    _setUser(null);
  }

  Future<void> disconnect() async {
    if (_initialized) {
      try {
        await GoogleSignIn.instance.disconnect();
      } catch (_) {
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
      }
    }

    _setUser(null);
  }

  /// ترويسات الاعتماد اللازمة لاستدعاءات Drive.
  ///
  /// [promptIfNecessary] يكون `true` فقط أثناء تسجيل الدخول،
  /// لأن طلب الأذونات قد يفتح واجهة تحتاج تفاعل المستخدم.
  Future<Map<String, String>?> authHeaders({
    bool promptIfNecessary = false,
  }) async {
    final user = _currentUser;

    if (user == null) {
      return null;
    }

    try {
      return await user.authorizationClient.authorizationHeaders(
        GoogleSignInConfig.driveScopes,
        promptIfNecessary: promptIfNecessary,
      );
    } catch (_) {
      return null;
    }
  }

  void _setUser(GoogleSignInAccount? account) {
    if (_currentUser == account) {
      return;
    }

    _currentUser = account;

    notifyListeners();
  }
}
