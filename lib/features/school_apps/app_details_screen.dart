import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../models/school_app_model.dart';
import '../../repositories/school_app_repository.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/error_state_view.dart';

final appDetailsProvider =
    FutureProvider.family.autoDispose<SchoolAppModel, String>((ref, appId) async {
  final repo = ref.watch(schoolAppRepositoryProvider);
  final result = await repo.getAppDetails(appId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load app details');
  }
  return result.dataOrNull!;
});

class AppDetailsScreen extends ConsumerStatefulWidget {
  final String appId;

  const AppDetailsScreen({super.key, required this.appId});

  @override
  ConsumerState<AppDetailsScreen> createState() => _AppDetailsScreenState();
}

class _AppDetailsScreenState extends ConsumerState<AppDetailsScreen> {
  bool _isProcessing = false;

  void _showEditMetadataDialog(SchoolAppModel app) {
    final nameController = TextEditingController(text: app.appName);
    final packageController = TextEditingController(text: app.packageName ?? '');
    final identifierController = TextEditingController(text: app.appIdentifier ?? '');
    final versionController = TextEditingController(text: app.currentVersion);
    final playStoreController = TextEditingController(text: app.playStoreUrl ?? '');
    final notesController = TextEditingController(text: app.notes ?? '');
    String? localError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Edit Dedicated App Metadata'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Update developer-managed app identification. Changes here do NOT compile or generate APKs.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                if (localError != null) ...[
                  Text(localError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Branded App Name *', hintText: 'e.g. St. Xavier Parent App'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: packageController,
                  decoration: const InputDecoration(labelText: 'Android Package Name', hintText: 'e.g. com.schoolos.stxavier'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: identifierController,
                  decoration: const InputDecoration(labelText: 'App Identifier Code', hintText: 'e.g. STXAVIER_APP_01'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: versionController,
                  decoration: const InputDecoration(labelText: 'Current Release Version', hintText: '1.0.0'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: playStoreController,
                  decoration: const InputDecoration(labelText: 'Google Play Store URL (Optional)', hintText: 'https://play.google.com/store/apps/...'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Developer Notes', hintText: 'Internal build notes or keystore alias'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setModalState(() => localError = 'App Name is required.');
                  return;
                }

                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                setState(() => _isProcessing = true);
                final repo = ref.read(schoolAppRepositoryProvider);
                final res = await repo.updateAppMetadata(
                  appId: app.id,
                  appName: name,
                  packageName: packageController.text.trim(),
                  appIdentifier: identifierController.text.trim(),
                  currentVersion: versionController.text.trim(),
                  playStoreUrl: playStoreController.text.trim(),
                  notes: notesController.text.trim(),
                );

                if (mounted) {
                  setState(() => _isProcessing = false);
                  if (res.isSuccess) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('App metadata saved successfully!'), backgroundColor: AppColors.success),
                    );
                    ref.invalidate(appDetailsProvider(widget.appId));
                  } else {
                    messenger.showSnackBar(
                      SnackBar(content: Text(res.errorOrNull ?? 'Failed to update metadata'), backgroundColor: AppColors.error),
                    );
                  }
                }
              },
              child: const Text('Save Metadata'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAccess(SchoolAppModel app) async {
    final nextState = !app.isActive;
    final action = nextState ? 'Activate' : 'Deactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action Application Access?'),
        content: Text(
          'Are you sure you want to $action access for "${app.appName}"?\n\n'
          'Note: The app remains installed on users devices, but SaaS backend data access will be ${nextState ? 'allowed' : 'blocked'}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: nextState ? AppColors.success : AppColors.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    final repo = ref.read(schoolAppRepositoryProvider);
    final res = await repo.toggleAppAccess(appId: app.id, isActive: nextState);

    if (mounted) {
      setState(() => _isProcessing = false);
      if (res.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('App access successfully set to ${nextState ? 'ACTIVE' : 'INACTIVE'}'), backgroundColor: AppColors.success),
        );
        ref.invalidate(appDetailsProvider(widget.appId));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.errorOrNull ?? 'Failed to toggle access'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appAsync = ref.watch(appDetailsProvider(widget.appId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Dedicated App Metadata'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(appDetailsProvider(widget.appId)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CenteredContentWrapper(
        child: appAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          error: (err, _) => ErrorStateView(
            title: 'Unable to Load App Details',
            message: err.toString().replaceFirst('Exception: ', ''),
            onRetry: () => ref.invalidate(appDetailsProvider(widget.appId)),
          ),
          data: (app) => _buildContent(context, app),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, SchoolAppModel app) {
    final dateFormat = DateFormat.yMMMMd();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Summary Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primarySubtle,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.smartphone_rounded, size: 30, color: AppColors.primary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.appName,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Dedicated School Management App • Version ${app.currentVersion}',
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: app.isActive ? AppColors.successSubtle : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: app.isActive ? AppColors.success.withValues(alpha: 0.3) : AppColors.borderLight),
                                  ),
                                  child: Text(
                                    app.isActive ? 'ACCESS: ACTIVE' : 'ACCESS: INACTIVE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: app.isActive ? AppColors.successText : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  // Actions: Edit Metadata, Activate/Deactivate, View School
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showEditMetadataDialog(app),
                        icon: const Icon(Icons.edit_note_rounded, size: 16),
                        label: const Text('Edit Metadata'),
                      ),
                      if (app.isActive)
                        OutlinedButton.icon(
                          onPressed: _isProcessing ? null : () => _toggleAccess(app),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                          ),
                          icon: const Icon(Icons.block_rounded, size: 16),
                          label: const Text('Deactivate Access'),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: _isProcessing ? null : () => _toggleAccess(app),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                          icon: const Icon(Icons.check_circle_rounded, size: 16),
                          label: const Text('Activate Access'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => context.go(AppRoutes.schoolDetailsPath(app.schoolId)),
                        icon: const Icon(Icons.school_rounded, size: 16),
                        label: const Text('View School Profile'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Section 1: Tenant Mapping & Identity
          _buildSection(
            title: 'School Tenant Mapping',
            icon: Icons.apartment_rounded,
            children: [
              _infoRow('School Name', app.schoolName ?? 'Assigned School'),
              _infoRow('authoritative school_id (UUID)', app.schoolId),
              _infoRow('Application Model', '1 School → 1 Dedicated Mobile App'),
            ],
          ),
          const SizedBox(height: 16),

          // Section 2: Application Identification
          _buildSection(
            title: 'App Identification & Release',
            icon: Icons.code_rounded,
            children: [
              _infoRow('Branded App Name', app.appName),
              _infoRow('Package Name (Android)', app.packageName ?? 'Not set by developer yet'),
              _infoRow('App Identifier', app.appIdentifier ?? 'Generated automatically'),
              _infoRow('Target Platform', 'ANDROID (Google Play)'),
              _infoRow('Current Version', app.currentVersion),
              _infoRow('Play Store URL', app.playStoreUrl ?? 'Not published to store yet'),
              _infoRow('Build Managed By', 'Developer via Android Studio (Manual Release)'),
              _infoRow('Registered On', dateFormat.format(app.createdAt)),
            ],
          ),
          const SizedBox(height: 16),

          // Section 3: Notes
          if (app.notes != null && app.notes!.isNotEmpty) ...[
            _buildSection(
              title: 'Developer Notes',
              icon: Icons.notes_rounded,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    app.notes!,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Developer Release Policy Notice
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 20, color: AppColors.primary),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Developer-Managed Build Architecture',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Super Admin is a central control panel. APK/AAB generation and Play Store publishing are executed manually in Android Studio. Setting access to INACTIVE instantly blocks backend SaaS requests without modifying client packages.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
