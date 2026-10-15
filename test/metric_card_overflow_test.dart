import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/dashboard_stats.dart';
import 'package:super_admin_app/theme/app_theme.dart';
import 'package:super_admin_app/widgets/metric_card.dart';

void main() {
  group('MetricCard Layout & Overflow Prevention Tests', () {
    testWidgets('1. Fits cleanly in 126.5px height (original overflow scenario) without error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 215,
                height: 126.5,
                child: MetricCard(
                  title: 'Total Schools',
                  value: '42',
                  icon: Icons.apartment_rounded,
                  iconColor: Colors.blue,
                  iconBgColor: Colors.blueGrey,
                  subtitle: 'Registered Tenants',
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Total Schools'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Registered Tenants'), findsOneWidget);
    });

    testWidgets('2. Fits cleanly in compact 115px height without overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 115,
                child: MetricCard(
                  title: 'Active Schools',
                  value: '10,013',
                  icon: Icons.check_circle_rounded,
                  iconColor: Colors.green,
                  iconBgColor: Colors.greenAccent,
                  subtitle: 'Live Operations',
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Active Schools'), findsOneWidget);
      expect(find.text('10,013'), findsOneWidget);
      expect(find.text('Live Operations'), findsOneWidget);
    });

    testWidgets('3. Handles long titles, large values, and long subtitles gracefully', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 215,
                height: 140,
                child: MetricCard(
                  title: 'Multi-Tenant Management Applications',
                  value: '₹12,450,000',
                  icon: Icons.apps_rounded,
                  iconColor: Colors.purple,
                  iconBgColor: Colors.purpleAccent,
                  subtitle: 'Active Dedicated Tenant Systems Across All Regions',
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Multi-Tenant Management Applications'), findsOneWidget);
      expect(find.text('₹12,450,000'), findsOneWidget);
    });

    testWidgets('4. Works in unbounded height Column without crashing or throwing RenderFlex error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  MetricCard(
                    title: 'Expired Subscriptions',
                    value: '0',
                    icon: Icons.warning_rounded,
                    iconColor: Colors.red,
                    iconBgColor: Colors.redAccent,
                    subtitle: 'Access Blocked',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Expired Subscriptions'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('5. Renders without subtitle cleanly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 215,
                height: 130,
                child: MetricCard(
                  title: 'Quick Metric',
                  value: '99',
                  icon: Icons.speed_rounded,
                  iconColor: Colors.orange,
                  iconBgColor: Colors.orangeAccent,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Quick Metric'), findsOneWidget);
      expect(find.text('99'), findsOneWidget);
    });
  });

  group('Dashboard Metrics Grid Responsive Breakpoint Tests', () {
    Widget buildDashboardMetricsTestWidget(double width, double height) {
      final stats = DashboardStats(
        totalSchools: 12,
        activeSchools: 10,
        inactiveSchools: 2,
        suspendedSchools: 0,
        totalApps: 12,
        activeApps: 12,
        totalSubscriptions: 12,
        activeSubscriptions: 11,
        expiredSubscriptions: 1,
        recentSchools: [],
      );

      final cards = [
        MetricCard(
          title: 'Total Schools',
          value: stats.totalSchools.toString(),
          icon: Icons.apartment_rounded,
          iconColor: Colors.blue,
          iconBgColor: Colors.blue.withValues(alpha: 0.1),
          subtitle: 'Registered Tenants',
        ),
        MetricCard(
          title: 'Active Schools',
          value: stats.activeSchools.toString(),
          icon: Icons.check_circle_outline_rounded,
          iconColor: Colors.green,
          iconBgColor: Colors.green.withValues(alpha: 0.1),
          subtitle: 'Live Operations',
        ),
        MetricCard(
          title: 'Inactive Schools',
          value: stats.inactiveSchools.toString(),
          icon: Icons.pause_circle_outline_rounded,
          iconColor: Colors.grey,
          iconBgColor: const Color(0xFFF1F5F9),
          subtitle: 'Temporarily Inactive',
        ),
        MetricCard(
          title: 'Management Apps',
          value: stats.totalApps.toString(),
          icon: Icons.apps_rounded,
          iconColor: Colors.lightBlue,
          iconBgColor: const Color(0xFFE0F2FE),
          subtitle: '${stats.activeApps} Active Dedicated Apps',
        ),
        MetricCard(
          title: 'Active Subscriptions',
          value: stats.activeSubscriptions.toString(),
          icon: Icons.link_rounded,
          iconColor: Colors.purple,
          iconBgColor: const Color(0xFFF3E8FF),
          subtitle: '${stats.totalSubscriptions} Total Subscriptions',
        ),
        MetricCard(
          title: 'Expired Subscriptions',
          value: stats.expiredSubscriptions.toString(),
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.red,
          iconBgColor: Colors.red.withValues(alpha: 0.1),
          subtitle: 'Access Blocked',
        ),
      ];

      return MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  int crossAxisCount;
                  double childAspectRatio;

                  if (w >= 860) {
                    crossAxisCount = 4;
                    childAspectRatio = 1.4;
                  } else if (w >= 580) {
                    crossAxisCount = 2;
                    childAspectRatio = 2.0;
                  } else {
                    crossAxisCount = 1;
                    childAspectRatio = 2.4;
                  }

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: childAspectRatio,
                    children: cards,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

    testWidgets('6. Desktop 1200px content area (width: 908px) renders all 6 cards with 0 overflow', (tester) async {
      await tester.pumpWidget(buildDashboardMetricsTestWidget(908, 800));
      expect(tester.takeException(), isNull);
      expect(find.text('Total Schools'), findsOneWidget);
      expect(find.text('Active Schools'), findsOneWidget);
      expect(find.text('Inactive Schools'), findsOneWidget);
      expect(find.text('Management Apps'), findsOneWidget);
      expect(find.text('Active Subscriptions'), findsOneWidget);
      expect(find.text('Expired Subscriptions'), findsOneWidget);
    });

    testWidgets('7. Wide Desktop (width: 1200px) renders with 0 overflow', (tester) async {
      await tester.pumpWidget(buildDashboardMetricsTestWidget(1200, 800));
      expect(tester.takeException(), isNull);
      expect(find.text('Total Schools'), findsOneWidget);
      expect(find.text('Expired Subscriptions'), findsOneWidget);
    });

    testWidgets('8. Tablet (width: 768px) renders 2-column grid with 0 overflow', (tester) async {
      await tester.pumpWidget(buildDashboardMetricsTestWidget(768, 900));
      expect(tester.takeException(), isNull);
      expect(find.text('Total Schools'), findsOneWidget);
      expect(find.text('Expired Subscriptions'), findsOneWidget);
    });

    testWidgets('9. Mobile (width: 375px) renders 1-column grid with 0 overflow', (tester) async {
      await tester.pumpWidget(buildDashboardMetricsTestWidget(375, 1200));
      expect(tester.takeException(), isNull);
      expect(find.text('Total Schools'), findsOneWidget);
      expect(find.text('Expired Subscriptions'), findsOneWidget);
    });

    testWidgets('10. Small Mobile (width: 320px) renders cleanly with 0 overflow', (tester) async {
      await tester.pumpWidget(buildDashboardMetricsTestWidget(320, 1200));
      expect(tester.takeException(), isNull);
      expect(find.text('Total Schools'), findsOneWidget);
      expect(find.text('Expired Subscriptions'), findsOneWidget);
    });
  });
}
