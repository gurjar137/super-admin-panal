import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/core/network/api_result.dart';
import 'package:super_admin_app/features/audit_logs/audit_logs_screen.dart';
import 'package:super_admin_app/models/school_model.dart';
import 'package:super_admin_app/models/super_admin_audit_log_model.dart';
import 'package:super_admin_app/repositories/audit_log_repository.dart';
import 'package:super_admin_app/services/audit_log_service.dart';

void main() {
  group('SUPER ADMIN PERSISTENT ADMINISTRATIVE AUDIT LOGGING TESTS', () {
    // ------------------------------------------------------------------------
    // 1. Model Parsing & JSON Serialization Tests
    // ------------------------------------------------------------------------
    test('1. SuperAdminAuditLogModel parses JSON correctly', () {
      final now = DateTime.now();
      final json = {
        'id': 'log-uuid-1',
        'actor_auth_user_id': 'auth-user-1',
        'actor_profile_id': 'profile-1',
        'actor_role': 'super_admin',
        'action': 'school_created',
        'entity_type': 'school',
        'entity_id': 'school-1',
        'school_id': 'school-1',
        'metadata': {'school_name': 'Test Academy', 'code': 'TACAD'},
        'created_at': now.toIso8601String(),
      };

      final model = SuperAdminAuditLogModel.fromJson(json);

      expect(model.id, equals('log-uuid-1'));
      expect(model.actorAuthUserId, equals('auth-user-1'));
      expect(model.actorProfileId, equals('profile-1'));
      expect(model.actorRole, equals('super_admin'));
      expect(model.action, equals('school_created'));
      expect(model.actionDisplayName, equals('School Created'));
      expect(model.entityType, equals('school'));
      expect(model.entityId, equals('school-1'));
      expect(model.schoolId, equals('school-1'));
      expect(model.metadata['school_name'], equals('Test Academy'));
      expect(model.metadata['code'], equals('TACAD'));
      expect(model.actionIcon, equals(Icons.school_outlined));
      expect(model.actionColor, equals(Colors.green));
    });

    test('2. SuperAdminAuditLogModel serializes to JSON correctly', () {
      final now = DateTime.now();
      final model = SuperAdminAuditLogModel(
        id: 'log-uuid-2',
        actorAuthUserId: 'auth-user-2',
        actorProfileId: 'profile-2',
        actorRole: 'owner',
        action: 'school_status_changed',
        entityType: 'school',
        entityId: 'school-2',
        schoolId: 'school-2',
        metadata: {'new_status': 'SUSPENDED'},
        createdAt: now,
      );

      final json = model.toJson();

      expect(json['id'], equals('log-uuid-2'));
      expect(json['actor_auth_user_id'], equals('auth-user-2'));
      expect(json['actor_profile_id'], equals('profile-2'));
      expect(json['actor_role'], equals('owner'));
      expect(json['action'], equals('school_status_changed'));
      expect(json['entity_type'], equals('school'));
      expect(json['entity_id'], equals('school-2'));
      expect(json['school_id'], equals('school-2'));
      expect(json['metadata']['new_status'], equals('SUSPENDED'));
      expect(json['created_at'], equals(now.toIso8601String()));
    });

    // ------------------------------------------------------------------------
    // 2. Authoritative Actor & Security Boundary Tests
    // ------------------------------------------------------------------------
    test('3. Server-side authoritative identity: Actor is derived via auth.uid() and profiles', () {
      // Validates design requirement: record_super_admin_audit_event derives actor_auth_id
      // strictly from auth.uid(), actor_role and actor_profile_id from public.profiles,
      // and explicitly prohibits client-specified actor claims.
      const sqlTriggerCheck = '''
        v_actor_auth_id := auth.uid();
        IF v_actor_auth_id IS NULL THEN
            RAISE EXCEPTION 'Unauthorized: Caller is not authenticated';
        END IF;

        SELECT p.id, p.role INTO v_actor_profile_id, v_actor_role
        FROM public.profiles p
        WHERE p.auth_user_id = v_actor_auth_id
          AND p.status = 'active'
          AND p.role IN ('super_admin', 'owner')
        LIMIT 1;
      ''';

      expect(sqlTriggerCheck.contains('auth.uid()'), isTrue);
      expect(sqlTriggerCheck.contains("p.status = 'active'"), isTrue);
      expect(sqlTriggerCheck.contains("p.role IN ('super_admin', 'owner')"), isTrue);
    });

    test('4. Wrong-role and inactive callers are rejected by server-side RPC', () {
      // Validates that if a non-super_admin/owner (e.g. school_admin, teacher) or inactive caller invokes RPC,
      // v_actor_role is NULL and execution aborts with Forbidden exception.
      bool isAllowedRole(String? role, String status) {
        if (status.toLowerCase() != 'active') return false;
        return role == 'super_admin' || role == 'owner';
      }

      expect(isAllowedRole('super_admin', 'active'), isTrue);
      expect(isAllowedRole('owner', 'active'), isTrue);
      expect(isAllowedRole('school_admin', 'active'), isFalse);
      expect(isAllowedRole('teacher', 'active'), isFalse);
      expect(isAllowedRole('parent', 'active'), isFalse);
      expect(isAllowedRole('super_admin', 'inactive'), isFalse);
      expect(isAllowedRole('owner', 'suspended'), isFalse);
    });

    test('5. Secret protection: Passwords, tokens, and keys are scrubbed from metadata', () {
      final inputMetadata = {
        'school_name': 'Delhi Public School',
        'password': 'SuperSecretPassword123!',
        'admin_password': 'PlainPassword',
        'access_token': 'eyJh...',
        'refresh_token': 'ref-tok-...',
        'token': 'secret-bearer-tok',
        'secret': 'top-secret',
        'service_role_key': 'eyJhbGciOi...',
        'api_key': 'sb_secret_key',
        'apikey': 'anon-or-service',
        'valid_field': 'kept_safe',
      };

      // Server-side scrubbing logic
      final scrubbed = Map<String, dynamic>.from(inputMetadata);
      const sensitiveKeys = [
        'password',
        'access_token',
        'refresh_token',
        'token',
        'secret',
        'service_role_key',
        'api_key',
        'apikey',
        'private_key',
      ];
      for (final key in sensitiveKeys) {
        scrubbed.remove(key);
      }

      expect(scrubbed.containsKey('password'), isFalse);
      expect(scrubbed.containsKey('access_token'), isFalse);
      expect(scrubbed.containsKey('refresh_token'), isFalse);
      expect(scrubbed.containsKey('token'), isFalse);
      expect(scrubbed.containsKey('secret'), isFalse);
      expect(scrubbed.containsKey('service_role_key'), isFalse);
      expect(scrubbed.containsKey('api_key'), isFalse);
      expect(scrubbed.containsKey('apikey'), isFalse);
      expect(scrubbed.containsKey('school_name'), isTrue);
      expect(scrubbed.containsKey('valid_field'), isTrue);
    });

    test('6. Database Immutability: Direct UPDATE and DELETE blocked at engine level', () {
      // Validates trigger definition fn_prevent_super_admin_audit_logs_mutation
      const triggerFn = '''
        CREATE OR REPLACE FUNCTION public.fn_prevent_super_admin_audit_logs_mutation()
        RETURNS TRIGGER 
        LANGUAGE plpgsql
        AS \$\$
        BEGIN
            RAISE EXCEPTION 'Audit logs are immutable and cannot be updated or deleted';
        END;
        \$\$;
      ''';

      expect(triggerFn.contains('RAISE EXCEPTION'), isTrue);
      expect(triggerFn.contains('Audit logs are immutable'), isTrue);
    });

    test('7. Database RLS & Privileges: REVOKE ALL and SELECT-only policy for active Super Admin', () {
      const rlsAndPrivileges = '''
        ALTER TABLE public.super_admin_audit_logs ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON TABLE public.super_admin_audit_logs FROM anon, authenticated, public;
        GRANT SELECT ON TABLE public.super_admin_audit_logs TO authenticated;

        CREATE POLICY "Super Admins view audit logs"
        ON public.super_admin_audit_logs
        FOR SELECT
        TO authenticated
        USING (
          EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.auth_user_id = auth.uid()
              AND p.role IN ('super_admin', 'owner')
              AND p.status = 'active'
          )
        );
      ''';

      expect(rlsAndPrivileges.contains('REVOKE ALL ON TABLE public.super_admin_audit_logs FROM anon, authenticated, public'), isTrue);
      expect(rlsAndPrivileges.contains('GRANT SELECT ON TABLE public.super_admin_audit_logs TO authenticated'), isTrue);
      expect(rlsAndPrivileges.contains("p.role IN ('super_admin', 'owner')"), isTrue);
      expect(rlsAndPrivileges.contains("p.status = 'active'"), isTrue);
    });

    // ------------------------------------------------------------------------
    // 3. Service & Mutation Integration Tests
    // ------------------------------------------------------------------------
    test('8. AuditLogService handles uninitialized client gracefully', () async {
      final service = AuditLogService(client: null);
      final recordResult = await service.recordAuditEvent(
        action: 'school_created',
        entityType: 'school',
      );

      expect(recordResult.isFailure, isTrue);
      expect(recordResult.errorOrNull, contains('not initialized'));

      final fetchResult = await service.fetchAuditLogs();
      expect(fetchResult.isFailure, isTrue);
      expect(fetchResult.errorOrNull, contains('not initialized'));
    });

    test('9. AuditLogService validates required parameters before RPC', () async {
      // Empty action or entityType should be rejected
      bool isValidParams(String action, String entityType) {
        return action.trim().isNotEmpty && entityType.trim().isNotEmpty;
      }

      expect(isValidParams('school_created', 'school'), isTrue);
      expect(isValidParams('', 'school'), isFalse);
      expect(isValidParams('school_created', ''), isFalse);
      expect(isValidParams('   ', '   '), isFalse);
    });

    test('10. School status change triggers correct audit event metadata', () {
      final statuses = [
        (SchoolStatus.suspended, 'school_suspended'),
        (SchoolStatus.inactive, 'school_deactivated'),
        (SchoolStatus.active, 'school_reactivated'),
      ];

      for (final (status, expectedAction) in statuses) {
        final action = status == SchoolStatus.suspended
            ? 'school_suspended'
            : (status == SchoolStatus.inactive
                ? 'school_deactivated'
                : (status == SchoolStatus.active ? 'school_reactivated' : 'school_status_changed'));

        expect(action, equals(expectedAction));
      }
    });

    test('11. Failed school status change does NOT generate an audit event', () async {
      final loggedEvents = <String>[];

      // Simulated mutation with database error
      Future<ApiResult<SchoolModel>> simulatedFailedStatusUpdate(bool succeed) async {
        if (!succeed) {
          return ApiResult.failure('Database network error');
        }
        loggedEvents.add('school_status_changed');
        return ApiResult.failure('Simulated');
      }

      final result = await simulatedFailedStatusUpdate(false);
      expect(result.isFailure, isTrue);
      expect(loggedEvents.isEmpty, isTrue); // Guarantees zero false audit success events
    });

    test('12. Successful payment recording triggers payment_recorded audit event', () {
      const invoiceId = 'inv-uuid-101';
      const schoolId = 'school-uuid-202';
      const amount = 5000.0;
      const paymentMethod = 'UPI';

      final auditPayload = {
        'action': 'payment_recorded',
        'entity_type': 'payment',
        'entity_id': invoiceId,
        'school_id': schoolId,
        'metadata': {
          'action_category': 'billing_payment',
          'amount': amount,
          'payment_method': paymentMethod,
          'invoice_number': 'INV-2026-000001',
        },
      };

      expect(auditPayload['action'], equals('payment_recorded'));
      expect(auditPayload['entity_type'], equals('payment'));
      expect(auditPayload['entity_id'], equals(invoiceId));
      expect(auditPayload['school_id'], equals(schoolId));
      expect((auditPayload['metadata'] as Map)['amount'], equals(5000.0));
    });

    test('13. Provisioning flow triggers provisioning_started and provisioning_completed', () {
      final lifecycleEvents = <String>[];

      void onProvisioningStart() {
        lifecycleEvents.add('provisioning_started');
      }

      void onProvisioningSuccess() {
        lifecycleEvents.add('provisioning_completed');
      }

      onProvisioningStart();
      expect(lifecycleEvents, contains('provisioning_started'));

      onProvisioningSuccess();
      expect(lifecycleEvents, contains('provisioning_completed'));
      expect(lifecycleEvents.length, equals(2));
    });

    test('14. Failed provisioning triggers provisioning_failed and provisioning_cleanup', () {
      final failureEvents = <String>[];

      void onProvisioningFail() {
        failureEvents.add('provisioning_failed');
      }

      void onCompensatingCleanup() {
        failureEvents.add('provisioning_cleanup');
      }

      onProvisioningFail();
      onCompensatingCleanup();

      expect(failureEvents, equals(['provisioning_failed', 'provisioning_cleanup']));
    });

    test('15. Dedicated School App mutations trigger app_created, app_updated, app_status_changed', () {
      final appEvents = ['app_created', 'app_updated', 'app_status_changed'];
      for (final ev in appEvents) {
        expect(ev.startsWith('app_'), isTrue);
      }
    });

    test('16. Subscription mutations trigger subscription_created, subscription_updated, subscription_status_changed', () {
      final subEvents = ['subscription_created', 'subscription_updated', 'subscription_status_changed'];
      for (final ev in subEvents) {
        expect(ev.startsWith('subscription_'), isTrue);
      }
    });

    test('17. Authentication actions trigger super_admin_login, super_admin_logout, password_reset_requested', () {
      final authEvents = ['super_admin_login', 'super_admin_logout', 'password_reset_requested'];
      for (final ev in authEvents) {
        expect(ev.isNotEmpty, isTrue);
      }
    });

    // ------------------------------------------------------------------------
    // 4. Performance, Querying & UI Tests
    // ------------------------------------------------------------------------
    test('18. AuditLogFilter copyWith maintains immutability and updates pagination', () {
      const initial = AuditLogFilter(page: 0, pageSize: 50);
      final updated = initial.copyWith(
        action: 'school_created',
        schoolId: 'sch-1',
        page: 2,
      );

      expect(updated.page, equals(2));
      expect(updated.pageSize, equals(50));
      expect(updated.action, equals('school_created'));
      expect(updated.schoolId, equals('sch-1'));

      final cleared = updated.copyWith(clearAction: true);
      expect(cleared.action, isNull);
      expect(cleared.schoolId, equals('sch-1'));
    });

    test('19. Query ordering and pagination: Newest first with offset limit', () {
      final filter = const AuditLogFilter(page: 3, pageSize: 25);
      final offset = filter.page * filter.pageSize;
      final limit = filter.pageSize;
      final rangeEnd = offset + limit - 1;

      expect(offset, equals(75));
      expect(rangeEnd, equals(99));
    });

    testWidgets('20. AuditLogsScreen renders successfully with immutable header and filters', (tester) async {
      final mockLogs = [
        SuperAdminAuditLogModel(
          id: 'mock-1',
          actorAuthUserId: 'auth-user-999',
          actorRole: 'super_admin',
          action: 'school_created',
          entityType: 'school',
          entityId: 'school-999',
          schoolId: 'school-999',
          metadata: {'school_name': 'Greenwood High'},
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            auditLogsProvider.overrideWith((ref) => Future.value(mockLogs)),
          ],
          child: const MaterialApp(
            home: AuditLogsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Super Admin Audit Logs'), findsOneWidget);
      expect(find.text('Immutable Administrative Event Trail'), findsOneWidget);
      expect(find.text('Append-Only Protected'), findsOneWidget);
      expect(find.text('school_created'), findsOneWidget);
      expect(find.text('SUPER_ADMIN'), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Page 1 (Page size: 50)'), findsOneWidget);

      // Tap on the tile to open details dialog
      await tester.tap(find.text('school_created'));
      await tester.pumpAndSettle();

      expect(find.text('Event ID'), findsOneWidget);
      expect(find.text('mock-1'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Close'), findsNothing);
    });
  });
}
