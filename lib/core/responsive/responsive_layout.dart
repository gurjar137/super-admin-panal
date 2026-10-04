import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// Responsive helper to switch between Mobile, Tablet, and Desktop/Web layouts.
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppConstants.breakpointTablet;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= AppConstants.breakpointTablet && width < AppConstants.breakpointDesktop;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppConstants.breakpointDesktop;

  static bool isWideScreen(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 800.0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= AppConstants.breakpointDesktop) {
      return desktop;
    } else if (width >= AppConstants.breakpointTablet && tablet != null) {
      return tablet!;
    } else {
      return mobile;
    }
  }
}

/// A container that constrains content to a readable maximum width on wide displays.
class CenteredContentWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const CenteredContentWrapper({
    super.key,
    required this.child,
    this.maxWidth = AppConstants.maxContentWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0),
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
