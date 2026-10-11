// Name, email, and photo shown on Profile. Not an account editor.

import 'package:flutter/foundation.dart';
import 'package:waffr/core/sync/auth_session.dart';
import 'package:waffr/data/services/profile_photo.dart';
import 'package:waffr/core/prefs/app_prefs.dart';

class ProfileIdentity extends ChangeNotifier {
  ProfileIdentity._();

  static final ProfileIdentity instance = ProfileIdentity._();

  String _name = '';
  String _email = '';
  bool _loggedIn = false;
  bool _loaded = false;
  String? _photoPath;
  Future<void>? _loader;

  /// False until the first [reload] finishes; sign-in state is unknown before.
  bool get isLoaded => _loaded;

  /// Loads once if nothing has loaded yet; otherwise returns the last load.
  Future<void> ensureLoaded() => _loader ??= _load();

  String get name => _name;

  String get email => _email;

  bool get isLoggedIn => _loggedIn;

  String? get photoPath => _photoPath;

  /// The account name while signed in. The name saved from an account
  /// stays on the device after signing out, so a guest always reads «ضيف».
  String get displayName {
    if (!_loggedIn) return 'ضيف';
    final trimmed = _name.trim();
    return trimmed.isNotEmpty ? trimmed : 'مستخدم وفّر';
  }

  String? get displayEmail {
    if (!_loggedIn) return null;
    final trimmed = _email.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> reload() {
    _loader = _load();
    return _loader!;
  }

  void reset() {
    _name = '';
    _email = '';
    _loggedIn = false;
    _loaded = false;
    _photoPath = null;
    _loader = null;
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await AppPrefs.instance;
    final loggedIn = await AuthSession.instance.isLoggedIn();
    final accountEmail = await AuthSession.instance.email() ?? '';
    final photoPath = await ProfilePhoto.path();
    _loggedIn = loggedIn;
    _name = prefs.getString('user_name') ?? '';
    _email = loggedIn ? accountEmail : '';
    _photoPath = photoPath;
    _loaded = true;
    notifyListeners();
  }
}
