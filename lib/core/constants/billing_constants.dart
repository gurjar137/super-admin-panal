/// Per-Student Billing System Constants
class BillingConstants {
  BillingConstants._();

  /// Default fee charged per billable student per billing period (in INR)
  static const double defaultRatePerStudent = 20.00;

  /// Default ISO currency code
  static const String defaultCurrency = 'INR';

  /// Default currency symbol
  static const String defaultCurrencySymbol = '₹';

  /// Standard billing cycle
  static const String defaultBillingCycle = 'MONTHLY';

  /// Exact, decimal-safe bill calculation avoiding floating point errors.
  /// Converts to paise (cents), performs integer multiplication, and converts back to standard currency unit.
  static double calculateTotalAmount({
    required int studentCount,
    required double ratePerStudent,
  }) {
    if (studentCount <= 0 || ratePerStudent <= 0) return 0.00;
    final rateInPaise = (ratePerStudent * 100).round();
    final totalInPaise = studentCount * rateInPaise;
    return totalInPaise / 100.0;
  }

  /// Format an amount with currency symbol
  static String formatCurrency(double amount, {String symbol = defaultCurrencySymbol}) {
    // Exact 2 decimal places or comma separated
    final isWhole = amount == amount.roundToDouble();
    if (isWhole) {
      return '$symbol${amount.toInt()}';
    }
    return '$symbol${amount.toStringAsFixed(2)}';
  }
}
