import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/school_model.dart';
import 'package:super_admin_app/widgets/empty_state_view.dart';
import 'package:super_admin_app/widgets/metric_card.dart';
import 'package:super_admin_app/widgets/status_chip.dart';

void main() {
  testWidgets('StatusChip renders active status badge', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusChip(status: SchoolStatus.active),
        ),
      ),
    );

    expect(find.text('ACTIVE'), findsOneWidget);
  });

  testWidgets('MetricCard displays title, value and subtitle', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MetricCard(
            title: 'Total Schools',
            value: '42',
            icon: Icons.apartment_rounded,
            iconColor: Colors.blue,
            iconBgColor: Colors.blueGrey,
            subtitle: 'Operational systems',
          ),
        ),
      ),
    );

    expect(find.text('Total Schools'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Operational systems'), findsOneWidget);
  });

  testWidgets('EmptyStateView renders title and message', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyStateView(
            title: 'No Schools',
            message: 'No tenant schools have been added yet.',
          ),
        ),
      ),
    );

    expect(find.text('No Schools'), findsOneWidget);
    expect(find.text('No tenant schools have been added yet.'), findsOneWidget);
  });
}
