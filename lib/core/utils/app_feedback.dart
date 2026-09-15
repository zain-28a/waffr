import 'package:flutter/material.dart';

const String insufficientBalanceMessage =
    'المبلغ أكبر من رصيدك الحالي، لا يمكن إتمام العملية.';

void showAppSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, textAlign: TextAlign.center),
    ),
  );
}

void showInsufficientBalanceMessage(BuildContext context) {
  showAppSnackBar(context, insufficientBalanceMessage);
}
