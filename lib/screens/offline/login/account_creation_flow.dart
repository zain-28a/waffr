import 'package:flutter/material.dart';
import 'package:waffer/data/models/registration_profile.dart';
import 'package:waffer/screens/offline/login/register_screen.dart';
import 'package:waffer/screens/offline/user_info/user_info_screen.dart';

// Two-step signup on one route: profile (UserInfoScreen), then credentials.

class AccountCreationFlow extends StatefulWidget {
  final Future<void> Function() onCompleted;
  final bool popOnSuccess;

  const AccountCreationFlow({
    super.key,
    required this.onCompleted,
    this.popOnSuccess = false,
  });

  @override
  State<AccountCreationFlow> createState() => _AccountCreationFlowState();
}

class _AccountCreationFlowState extends State<AccountCreationFlow> {
  RegistrationProfile? _profile;
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return PopScope(
      // On step 1, system back returns to user info instead of leaving.
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _step == 0) return;
        setState(() => _step = 0);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: _step != 0,
            child: UserInfoScreen(
              onBack: () => Navigator.of(context).pop(),
              onContinue: (value) {
                setState(() {
                  _profile = value;
                  _step = 1;
                });
              },
            ),
          ),
          if (_step == 1 && profile != null)
            RegisterScreen(
              profile: profile,
              onBack: () => setState(() => _step = 0),
              onCompleted: widget.onCompleted,
              popOnSuccess: widget.popOnSuccess,
            ),
        ],
      ),
    );
  }
}
