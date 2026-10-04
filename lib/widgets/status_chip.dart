import 'package:flutter/material.dart';
import '../models/school_model.dart';
import '../models/subscription_model.dart';
import '../theme/app_colors.dart';

class StatusChip extends StatelessWidget {
  final SchoolStatus status;
  final double fontSize;
  final EdgeInsets padding;

  const StatusChip({
    super.key,
    required this.status,
    this.fontSize = 11.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    Color border;

    switch (status) {
      case SchoolStatus.active:
        bg = AppColors.successSubtle;
        fg = AppColors.successText;
        border = AppColors.success.withValues(alpha: 0.3);
        break;
      case SchoolStatus.inactive:
        bg = const Color(0xFFF1F5F9);
        fg = AppColors.textSecondary;
        border = AppColors.borderLight;
        break;
      case SchoolStatus.suspended:
        bg = AppColors.errorSubtle;
        fg = AppColors.errorText;
        border = AppColors.error.withValues(alpha: 0.3);
        break;
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: fg,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status.displayName.toUpperCase(),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class SubscriptionStatusChip extends StatelessWidget {
  final SubscriptionStatus status;
  final double fontSize;
  final EdgeInsets padding;

  const SubscriptionStatusChip({
    super.key,
    required this.status,
    this.fontSize = 11.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    Color border;

    switch (status) {
      case SubscriptionStatus.active:
        bg = AppColors.successSubtle;
        fg = AppColors.successText;
        border = AppColors.success.withValues(alpha: 0.3);
        break;
      case SubscriptionStatus.inactive:
        bg = const Color(0xFFF1F5F9);
        fg = AppColors.textSecondary;
        border = AppColors.borderLight;
        break;
      case SubscriptionStatus.expired:
        bg = const Color(0xFFFFF1F2);
        fg = const Color(0xFFBE123C);
        border = const Color(0xFFFDA4AF);
        break;
      case SubscriptionStatus.suspended:
        bg = AppColors.errorSubtle;
        fg = AppColors.errorText;
        border = AppColors.error.withValues(alpha: 0.3);
        break;
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: fg,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status.displayName.toUpperCase(),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
