import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/super_admin_audit_log_model.dart';
import '../../repositories/audit_log_repository.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';

class AuditLogsScreen extends ConsumerStatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  ConsumerState<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends ConsumerState<AuditLogsScreen> {
  final TextEditingController _actionFilterController = TextEditingController();
  final TextEditingController _schoolFilterController = TextEditingController();
  String? _selectedEntityType;

  final List<String> _entityTypes = [
    'All',
    'school',
    'billing',
    'invoice',
    'payment',
    'provisioning',
    'app',
    'subscription',
    'auth',
  ];

  @override
  void dispose() {
    _actionFilterController.dispose();
    _schoolFilterController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final current = ref.read(auditLogFilterProvider);
    final actionText = _actionFilterController.text.trim();
    final schoolText = _schoolFilterController.text.trim();
    final entityType = (_selectedEntityType == null || _selectedEntityType == 'All')
        ? null
        : _selectedEntityType;

    ref.read(auditLogFilterProvider.notifier).state = current.copyWith(
      action: actionText.isNotEmpty ? actionText : null,
      schoolId: schoolText.isNotEmpty ? schoolText : null,
      entityType: entityType,
      clearAction: actionText.isEmpty,
      clearSchool: schoolText.isEmpty,
      clearEntityType: entityType == null,
      page: 0,
    );
  }

  void _resetFilter() {
    _actionFilterController.clear();
    _schoolFilterController.clear();
    setState(() {
      _selectedEntityType = 'All';
    });
    ref.read(auditLogFilterProvider.notifier).state = const AuditLogFilter();
  }

  void _nextPage() {
    final current = ref.read(auditLogFilterProvider);
    ref.read(auditLogFilterProvider.notifier).state = current.copyWith(
      page: current.page + 1,
    );
  }

  void _prevPage() {
    final current = ref.read(auditLogFilterProvider);
    if (current.page > 0) {
      ref.read(auditLogFilterProvider.notifier).state = current.copyWith(
        page: current.page - 1,
      );
    }
  }

  void _showMetadataDialog(SuperAdminAuditLogModel log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(log.actionIcon, color: log.actionColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                log.actionDisplayName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Event ID', log.id),
                _buildDetailRow('Actor User ID', log.actorAuthUserId),
                if (log.actorProfileId != null)
                  _buildDetailRow('Actor Profile ID', log.actorProfileId!),
                _buildDetailRow('Actor Role', log.actorRole.toUpperCase()),
                _buildDetailRow('Entity Type', log.entityType),
                if (log.entityId != null)
                  _buildDetailRow('Entity ID', log.entityId!),
                if (log.schoolId != null)
                  _buildDetailRow('School ID', log.schoolId!),
                _buildDetailRow(
                  'Created At (UTC)',
                  '${DateFormat('yyyy-MM-dd HH:mm:ss').format(log.createdAt.toUtc())} UTC',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Metadata Payload:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(log.metadata),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(auditLogFilterProvider);
    final logsAsync = ref.watch(auditLogsProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Super Admin Audit Logs'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.dashboard);
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Audit Logs',
            onPressed: () => ref.invalidate(auditLogsProvider),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header summary
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_user_outlined, color: AppColors.primary, size: 24),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Immutable Administrative Event Trail',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_outline, size: 14, color: Colors.green.shade800),
                              const SizedBox(width: 4),
                              Text(
                                'Append-Only Protected',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Filters row
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: _actionFilterController,
                            decoration: const InputDecoration(
                              labelText: 'Action (e.g. school_created)',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _applyFilter(),
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: _schoolFilterController,
                            decoration: const InputDecoration(
                              labelText: 'School ID',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _applyFilter(),
                          ),
                        ),
                        SizedBox(
                          width: 170,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedEntityType ?? 'All',
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Entity Type',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: _entityTypes.map((type) {
                              return DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedEntityType = val;
                              });
                            },
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _applyFilter,
                          icon: const Icon(Icons.filter_list, size: 16),
                          label: const Text('Filter'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _resetFilter,
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Audit records list
            Expanded(
              child: logsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      Text('Failed to load audit logs: $err'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => ref.invalidate(auditLogsProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (logs) {
                  if (logs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_toggle_off, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'No audit log events found matching the criteria.',
                            style: TextStyle(color: Colors.grey, fontSize: 15),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: logs.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final dateStr = DateFormat('MMM dd, yyyy HH:mm:ss').format(log.createdAt.toLocal());

                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: log.actionColor.withValues(alpha: 0.15),
                            child: Icon(log.actionIcon, color: log.actionColor, size: 20),
                          ),
                          title: Row(
                            children: [
                              Text(
                                log.action,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.blueGrey.shade200),
                                ),
                                child: Text(
                                  log.actorRole.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey.shade800,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                dateStr,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                Text('Entity: ${log.entityType}'),
                                if (log.entityId != null)
                                  Text('ID: ${log.entityId!.length > 18 ? '${log.entityId!.substring(0, 18)}...' : log.entityId}'),
                                if (log.schoolId != null)
                                  Text('School: ${log.schoolId!.length > 8 ? '${log.schoolId!.substring(0, 8)}...' : log.schoolId}'),
                              ],
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () => _showMetadataDialog(log),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Pagination footer
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Page ${filter.page + 1} (Page size: ${filter.pageSize})',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: filter.page > 0 ? _prevPage : null,
                        icon: const Icon(Icons.chevron_left, size: 18),
                        label: const Text('Previous'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _nextPage,
                        icon: const Icon(Icons.chevron_right, size: 18),
                        label: const Text('Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
