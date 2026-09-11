
import 'package:flutter/material.dart';
import 'package:waffer/core/data/expense_categories.dart';
import 'package:waffer/core/data/transaction.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final TransactionStore _store = TransactionStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final accent = isDark
        ? AppColors.darkAccent
        : AppColors.lightAccent;

    final surface = isDark
        ? AppColors.darkSurface
        : const Color.fromARGB(153, 255, 253, 249);

    final cardDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      color: surface,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 40,
          offset: const Offset(0, -3),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "السجل",
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 30,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        iconTheme: IconThemeData(
          color: textPrimary,
        ),
      ),
      body: AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          final transactions = _store.transactions;

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                children: [
                  const SizedBox(height: 15),

                  // إجمالي المصاريف
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 25,
                    ),
                    decoration: cardDecoration,
                    child: Column(
                      children: [
                        Text(
                          "الاجمالي",
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: textPrimary,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          formatMoney(_store.totalExpense),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // عنوان السجل
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'سجل الانفاق :',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 15),

                  // العمليات
                  if (transactions.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 45,
                      ),
                      decoration: cardDecoration,
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 45,
                            color: textPrimary.withValues(alpha: 0.35),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "السجل فارغ",
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              color: textPrimary.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(
                        top: 22,
                        right: 22,
                        bottom: 8,
                        left: 22,
                      ),
                      decoration: cardDecoration,
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics:
                            const NeverScrollableScrollPhysics(),
                        itemCount: transactions.length,
                        separatorBuilder: (context, index) =>
                            Divider(
                          height: 25,
                          color: textPrimary.withValues(alpha: 0.08),
                        ),
                        itemBuilder: (context, index) {
                          return _TransactionRow(
                            transaction: transactions[index],
                            accent: accent,
                            textPrimary: textPrimary,
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final WafferTransaction transaction;
  final Color accent;
  final Color textPrimary;

  const _TransactionRow({
    required this.transaction,
    required this.accent,
    required this.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.isIncome;

    final title =
        isIncome ? 'دخل' : categoryFor(transaction.category).label;

    final icon = isIncome
        ? Icons.savings_outlined
        : categoryFor(transaction.category).icon;

    final details = <String>[
      if (transaction.note != null) transaction.note!,
      if (!isIncome && transaction.paymentMethod != null)
        transaction.paymentMethod!,
    ].join(' • ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.12),
          ),
          child: Icon(
            icon,
            color: accent,
            size: 22,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),

              if (details.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    color: textPrimary.withValues(alpha: 0.6),
                  ),
                ),
              ],

              const SizedBox(height: 3),

              Text(
                '${formatDate(transaction.dateTime)} • ${formatTime(transaction.dateTime)}',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: textPrimary.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 8),

        Text(
          '${isIncome ? '+' : '-'} ${formatMoney(transaction.amount)}',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: accent,
          ),
        ),
      ],
    );
  }
}
