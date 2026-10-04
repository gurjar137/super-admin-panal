import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/config/supabase_config.dart';
import '../../core/constants/billing_constants.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../models/school_app_model.dart';
import '../../models/invoice_payment_model.dart';
import '../../models/school_billing_settings_model.dart';
import '../../models/school_invoice_model.dart';
import '../../models/school_model.dart';
import '../../models/school_admin_model.dart';
import '../../models/school_student_count_summary.dart';
import '../../models/subscription_model.dart';
import '../../models/school_app_access_result.dart';
import '../../repositories/school_admin_repository.dart';
import '../../repositories/school_app_repository.dart';
import '../../repositories/school_billing_repository.dart';
import '../../repositories/school_repository.dart';
import '../../repositories/subscription_repository.dart';
import '../../services/school_app_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/error_state_view.dart';
import '../../widgets/status_chip.dart';

final schoolDetailsProvider =
    FutureProvider.family.autoDispose<SchoolModel, String>((ref, schoolId) async {
  final repo = ref.watch(schoolRepositoryProvider);
  final result = await repo.getSchoolDetails(schoolId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load school details');
  }
  return result.dataOrNull!;
});

final schoolDedicatedAppProvider =
    FutureProvider.family.autoDispose<SchoolAppModel?, String>((ref, schoolId) async {
  final repo = ref.watch(schoolAppRepositoryProvider);
  final result = await repo.getAppBySchoolId(schoolId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load school app configuration');
  }
  return result.dataOrNull;
});

class SchoolDetailsScreen extends ConsumerStatefulWidget {
  final String schoolId;

  const SchoolDetailsScreen({
    super.key,
    required this.schoolId,
  });

  @override
  ConsumerState<SchoolDetailsScreen> createState() => _SchoolDetailsScreenState();
}

class _SchoolDetailsScreenState extends ConsumerState<SchoolDetailsScreen> {
  bool _isUpdatingStatus = false;

  Future<void> _updateStatus(SchoolModel school, SchoolStatus newStatus) async {
    final actionName = newStatus == SchoolStatus.active ? 'Activate' : 'Deactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$actionName School?'),
        content: Text(
          'Are you sure you want to change the status of "${school.name}" to ${newStatus.displayName.toUpperCase()}?\n\n'
          'This will directly update the Supabase database.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == SchoolStatus.active
                  ? AppColors.success
                  : AppColors.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(actionName),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isUpdatingStatus = true);

    final repo = ref.read(schoolRepositoryProvider);
    final result = await repo.updateStatus(school.id, newStatus);

    if (!mounted) return;
    setState(() => _isUpdatingStatus = false);

    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated to ${newStatus.displayName} successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      ref.invalidate(schoolDetailsProvider(widget.schoolId));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorOrNull ?? 'Failed to update status'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showEditSchoolModal(SchoolModel school) {
    final nameController = TextEditingController(text: school.name);
    final phoneController = TextEditingController(text: school.phone ?? '');
    final emailController = TextEditingController(text: school.email ?? '');
    final addressController = TextEditingController(text: school.address ?? '');
    final logoUrlController = TextEditingController(text: school.logoUrl ?? '');
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit School Details',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Editing: ${school.name} (Code: ${school.schoolCode})',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'School Name *',
                        prefixIcon: Icon(Icons.school_outlined, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'School name is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                              prefixIcon: Icon(Icons.phone_outlined, size: 20),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: addressController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Campus Address',
                        prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: logoUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Logo URL (Optional)',
                        prefixIcon: Icon(Icons.image_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => isSaving = true);
                                final repo = ref.read(schoolRepositoryProvider);
                                final messenger = ScaffoldMessenger.of(context);
                                final nav = Navigator.of(modalCtx);
                                final res = await repo.updateSchool(
                                  schoolId: school.id,
                                  name: nameController.text.trim(),
                                  phone: phoneController.text.trim(),
                                  email: emailController.text.trim(),
                                  address: addressController.text.trim(),
                                  logoUrl: logoUrlController.text.trim(),
                                );
                                setModalState(() => isSaving = false);
                                if (res.isSuccess) {
                                  nav.pop();
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('School updated successfully in Supabase!'),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                  ref.invalidate(schoolDetailsProvider(widget.schoolId));
                                } else {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(res.errorOrNull ?? 'Failed to update school'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Save Changes to Database'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCreateAppModal(SchoolModel school) {
    final formKey = GlobalKey<FormState>();
    final appNameController = TextEditingController(text: '${school.name} App');
    final cleanCode = school.schoolCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final appIdentifierController = TextEditingController(text: '${cleanCode}_SCHOOL_APP');
    final cleanPackage = school.schoolCode.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final packageController = TextEditingController(text: 'com.schoolos.$cleanPackage');
    final versionController = TextEditingController(text: '1.0.0');
    final playStoreController = TextEditingController();
    final notesController = TextEditingController();
    SchoolAppStatus appStatus = SchoolAppStatus.active;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Create School App Record',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.link_rounded, size: 16, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Tenant: ${school.name}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'authoritative school_id: ${school.id}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          appNameController.text = '${school.name} App';
                          appIdentifierController.text = SchoolAppService.generateDefaultAppIdentifier(school.name);
                          packageController.text = SchoolAppService.generateDefaultPackageName(school.name);
                          versionController.text = '1.0.0';
                        },
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                        label: const Text('Auto-Suggest Setup'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: appNameController,
                      decoration: const InputDecoration(
                        labelText: 'Branded App Name *',
                        hintText: 'e.g. ABC Public School App',
                        prefixIcon: Icon(Icons.smartphone_rounded, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'App name is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: appIdentifierController,
                      decoration: const InputDecoration(
                        labelText: 'Internal App Identifier *',
                        hintText: 'e.g. ABC_SCHOOL_APP',
                        prefixIcon: Icon(Icons.badge_outlined, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'App Identifier is required';
                        final trimmed = val.trim().toUpperCase();
                        if (!trimmed.endsWith('_APP')) {
                          return 'App Identifier should end with _APP (e.g. ABC_SCHOOL_APP)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: packageController,
                      decoration: const InputDecoration(
                        labelText: 'Android Package Name *',
                        hintText: 'e.g. com.company.abcschool',
                        prefixIcon: Icon(Icons.android_rounded, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Android Package Name is required';
                        if (!SchoolAppService.isValidPackageName(val.trim())) {
                          return 'Invalid package format. Use reverse-domain format (e.g. com.company.school)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: versionController,
                            decoration: const InputDecoration(
                              labelText: 'Initial Version *',
                              hintText: '1.0.0',
                              prefixIcon: Icon(Icons.tag_rounded, size: 20),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Version is required';
                              if (!SchoolAppService.isValidVersion(val.trim())) {
                                return 'Invalid version format (e.g. 1.0.0)';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<SchoolAppStatus>(
                            initialValue: appStatus,
                            decoration: const InputDecoration(
                              labelText: 'Initial Access Status',
                              prefixIcon: Icon(Icons.toggle_on_outlined, size: 20),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: SchoolAppStatus.active,
                                child: Text('Active (Granted)'),
                              ),
                              DropdownMenuItem(
                                value: SchoolAppStatus.inactive,
                                child: Text('Inactive (Blocked)'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() => appStatus = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: playStoreController,
                      decoration: const InputDecoration(
                        labelText: 'Play Store URL (Optional)',
                        hintText: 'https://play.google.com/store/apps/details?id=...',
                        prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                      ),
                      validator: (val) {
                        if (val != null && val.trim().isNotEmpty && !SchoolAppService.isValidPlayStoreUrl(val.trim())) {
                          return 'Must be a valid URL starting with http:// or https://';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Developer Notes (Optional)',
                        hintText: 'Keystore alias, build track, or deployment instructions',
                        prefixIcon: Icon(Icons.notes_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => isSaving = true);
                                final repo = ref.read(schoolAppRepositoryProvider);
                                final messenger = ScaffoldMessenger.of(context);
                                final nav = Navigator.of(modalCtx);

                                final targetId = appIdentifierController.text.trim().toUpperCase();
                                final isIdUnique = await repo.isAppIdentifierUnique(targetId);
                                if (!isIdUnique) {
                                  setModalState(() => isSaving = false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('App Identifier "$targetId" is already in use by another school.'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                  return;
                                }

                                final targetPkg = packageController.text.trim().toLowerCase();
                                final isPkgUnique = await repo.isPackageNameUnique(targetPkg);
                                if (!isPkgUnique) {
                                  setModalState(() => isSaving = false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('Package Name "$targetPkg" is already registered to another school.'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                  return;
                                }

                                final res = await repo.createSchoolApp(
                                  schoolId: school.id,
                                  appName: appNameController.text.trim(),
                                  appIdentifier: targetId,
                                  packageName: targetPkg,
                                  currentVersion: versionController.text.trim(),
                                  playStoreUrl: playStoreController.text.trim(),
                                  status: appStatus,
                                  notes: notesController.text.trim(),
                                );
                                setModalState(() => isSaving = false);
                                if (res.isSuccess) {
                                  nav.pop();
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Dedicated School Management App created successfully!'),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                  ref.invalidate(schoolDedicatedAppProvider(widget.schoolId));
                                } else {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(res.errorOrNull ?? 'Failed to create app record'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Create School App Record'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditAppModal(SchoolAppModel app) {
    final formKey = GlobalKey<FormState>();
    final appNameController = TextEditingController(text: app.appName);
    final appIdentifierController = TextEditingController(text: app.appIdentifier ?? '');
    final packageController = TextEditingController(text: app.packageName ?? '');
    final versionController = TextEditingController(text: app.currentVersion);
    final playStoreController = TextEditingController(text: app.playStoreUrl ?? '');
    final notesController = TextEditingController(text: app.notes ?? '');
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit School App Metadata',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.textSecondary),
                              SizedBox(width: 6),
                              Text(
                                'Immutable Tenant Identity',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'school_id: ${app.schoolId}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: appNameController,
                      decoration: const InputDecoration(
                        labelText: 'Branded App Name *',
                        prefixIcon: Icon(Icons.smartphone_rounded, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'App name is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: appIdentifierController,
                      decoration: const InputDecoration(
                        labelText: 'Internal App Identifier *',
                        hintText: 'e.g. ABC_SCHOOL_APP',
                        prefixIcon: Icon(Icons.badge_outlined, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'App Identifier is required';
                        final trimmed = val.trim().toUpperCase();
                        if (!trimmed.endsWith('_APP')) {
                          return 'App Identifier should end with _APP (e.g. ABC_SCHOOL_APP)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: packageController,
                      decoration: const InputDecoration(
                        labelText: 'Android Package Name *',
                        hintText: 'e.g. com.company.abcschool',
                        prefixIcon: Icon(Icons.android_rounded, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Android Package Name is required';
                        if (!SchoolAppService.isValidPackageName(val.trim())) {
                          return 'Invalid package format. Use reverse-domain format (e.g. com.company.school)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: versionController,
                      decoration: const InputDecoration(
                        labelText: 'Current Version *',
                        hintText: '1.0.0',
                        prefixIcon: Icon(Icons.tag_rounded, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Version is required';
                        if (!SchoolAppService.isValidVersion(val.trim())) {
                          return 'Invalid version format (e.g. 1.0.0)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: playStoreController,
                      decoration: const InputDecoration(
                        labelText: 'Play Store URL (Optional)',
                        hintText: 'https://play.google.com/store/apps/details?id=...',
                        prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                      ),
                      validator: (val) {
                        if (val != null && val.trim().isNotEmpty && !SchoolAppService.isValidPlayStoreUrl(val.trim())) {
                          return 'Must be a valid URL starting with http:// or https://';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Developer Notes',
                        prefixIcon: Icon(Icons.notes_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => isSaving = true);
                                final repo = ref.read(schoolAppRepositoryProvider);
                                final messenger = ScaffoldMessenger.of(context);
                                final nav = Navigator.of(modalCtx);

                                final targetId = appIdentifierController.text.trim().toUpperCase();
                                final isIdUnique = await repo.isAppIdentifierUnique(targetId, excludeAppId: app.id);
                                if (!isIdUnique) {
                                  setModalState(() => isSaving = false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('App Identifier "$targetId" is already in use by another school.'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                  return;
                                }

                                final targetPkg = packageController.text.trim().toLowerCase();
                                final isPkgUnique = await repo.isPackageNameUnique(targetPkg, excludeAppId: app.id);
                                if (!isPkgUnique) {
                                  setModalState(() => isSaving = false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('Package Name "$targetPkg" is already registered to another school.'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                  return;
                                }

                                final res = await repo.updateAppMetadata(
                                  appId: app.id,
                                  appName: appNameController.text.trim(),
                                  packageName: targetPkg,
                                  appIdentifier: targetId,
                                  currentVersion: versionController.text.trim(),
                                  playStoreUrl: playStoreController.text.trim(),
                                  notes: notesController.text.trim(),
                                );
                                setModalState(() => isSaving = false);
                                if (res.isSuccess) {
                                  nav.pop();
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('App metadata saved successfully in Supabase!'),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                  ref.invalidate(schoolDedicatedAppProvider(widget.schoolId));
                                } else {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(res.errorOrNull ?? 'Failed to update metadata'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Save App Metadata'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleAppAccess(SchoolAppModel app) async {
    final nextState = !app.isActive;
    final action = nextState ? 'Activate' : 'Deactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action App Access?'),
        content: Text(
          'Are you sure you want to set access for "${app.appName}" to ${nextState ? 'ACTIVE' : 'INACTIVE'}?\n\n'
          '• School status remains unchanged.\n'
          '• ${nextState ? 'Backend API access will be granted.' : 'Backend API access will be blocked for this app.'}',
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

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(schoolAppRepositoryProvider);
    final res = await repo.toggleAppAccess(appId: app.id, isActive: nextState);

    if (!mounted) return;
    if (res.isSuccess) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('App access changed to ${nextState ? 'ACTIVE' : 'INACTIVE'} successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      ref.invalidate(schoolDedicatedAppProvider(widget.schoolId));
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(res.errorOrNull ?? 'Failed to toggle app access'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final schoolAsync = ref.watch(schoolDetailsProvider(widget.schoolId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('School Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh details',
            onPressed: () => ref.invalidate(schoolDetailsProvider(widget.schoolId)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CenteredContentWrapper(
        child: schoolAsync.when(
          loading: () => const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(strokeWidth: 2.5),
                SizedBox(height: 16),
                Text('Loading institution details...'),
              ],
            ),
          ),
          error: (err, stack) => ErrorStateView(
            title: 'School Details Unavailable',
            message: err.toString().replaceFirst('Exception: ', ''),
            onRetry: () => ref.invalidate(schoolDetailsProvider(widget.schoolId)),
          ),
          data: (school) => _buildDetailsContent(context, school),
        ),
      ),
    );
  }

  Widget _buildDetailsContent(BuildContext context, SchoolModel school) {
    final dateFormat = DateFormat.yMMMMd();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.primarySubtle,
                        child: Text(
                          school.name.isNotEmpty ? school.name[0].toUpperCase() : 'S',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              school.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    school.schoolCode,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSecondary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                StatusChip(status: school.status),
                              ],
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: school.id));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('School ID copied to clipboard!'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.vpn_key_outlined, size: 13, color: AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Text(
                                      'School ID: ${school.id}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontFamily: 'monospace',
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.copy_rounded, size: 12, color: AppColors.textSecondary),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // Action Buttons: Edit, Activate/Deactivate
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showEditSchoolModal(school),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit Info'),
                      ),
                      const SizedBox(width: 12),
                      if (school.status == SchoolStatus.active)
                        OutlinedButton.icon(
                          onPressed: _isUpdatingStatus
                              ? null
                              : () => _updateStatus(school, SchoolStatus.inactive),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                          ),
                          icon: const Icon(Icons.pause_circle_outline_rounded, size: 16),
                          label: const Text('Deactivate'),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: _isUpdatingStatus
                              ? null
                              : () => _updateStatus(school, SchoolStatus.active),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                          ),
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                          label: const Text('Activate School'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Section 0: Operational Overview / Summary Card (Phase 6 Requirement 9)
          _buildOperationalSummaryCard(context, school),
          const SizedBox(height: 16),

          // Section 1: Basic Information
          _buildSectionCard(
            title: 'Basic Information',
            icon: Icons.info_outline_rounded,
            children: [
              _infoRow('Database ID (UUID)', school.id),
              _infoRow('School Name', school.name),
              _infoRow('System Code', school.schoolCode),
              _infoRow('Official Email', school.email ?? 'Not provided'),
              _infoRow('Official Phone', school.phone ?? 'Not provided'),
              _infoRow('Campus Address', school.address ?? 'Not provided'),
              _infoRow('Registered On', dateFormat.format(school.createdAt)),
            ],
          ),
          const SizedBox(height: 16),

          // Section 2: Branding & Identity
          _buildSectionCard(
            title: 'Branding & Assets',
            icon: Icons.palette_outlined,
            children: [
              _infoRow('Logo URL', (school.logoUrl != null && school.logoUrl!.isNotEmpty) ? school.logoUrl! : 'Not configured'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDBA74)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Color(0xFFEA580C)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Additional branding fields (app_name, primary_color, secondary_color) are not yet available in the database schema. They will be added in a future migration.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF9A3412)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Section 3: Primary Administrator Summary
          _buildSectionCard(
            title: 'Primary Administrator',
            icon: Icons.manage_accounts_outlined,
            children: [
              _infoRow('Admin Full Name', school.adminName ?? 'Assigned via profiles'),
              _infoRow('Admin Email', school.adminEmail ?? 'Assigned via profiles'),
              _infoRow('Admin Phone', school.adminPhone ?? 'Not set'),
              _infoRow('Assigned Role', 'School Administrator (Level 1)'),
            ],
          ),
          const SizedBox(height: 16),

          // Section 4: School Identity (Authoritative UUID & Timestamps)
          _buildSectionCard(
            title: 'Tenant Identity',
            icon: Icons.fingerprint_rounded,
            children: [
              _infoRow('Authoritative Tenant ID', school.id),
              _infoRow('Registered Timestamp', dateFormat.format(school.createdAt)),
              if (school.updatedAt != null)
                _infoRow('Last Modified Timestamp', dateFormat.format(school.updatedAt!)),
            ],
          ),
          const SizedBox(height: 16),

          // Section 5: Dedicated School Management App (Visual Centerpiece)
          _buildSchoolAppSection(context, school, dateFormat),
          const SizedBox(height: 16),

          // Section 6: Subscription & Access Control (Phase 4)
          _buildSubscriptionAndAccessSection(context, school, dateFormat),
          const SizedBox(height: 16),

          // Section 7: School Administrator (Provisioning & Management)
          _buildSchoolAdminSection(context, school, dateFormat),
          const SizedBox(height: 16),

          // Section 8: Per-Student School Billing & Invoices
          _buildSchoolBillingSection(context, school, dateFormat),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSchoolAppSection(BuildContext context, SchoolModel school, DateFormat dateFormat) {
    final appAsync = ref.watch(schoolDedicatedAppProvider(school.id));

    return appAsync.when(
      loading: () => Card(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(height: 12),
                Text('Checking dedicated app configuration...', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
      error: (err, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                  SizedBox(width: 8),
                  Text('Dedicated App Status', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                err.toString().replaceFirst('Exception: ', ''),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(schoolDedicatedAppProvider(school.id)),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry Connection'),
              ),
            ],
          ),
        ),
      ),
      data: (app) {
        if (app == null) {
          // Empty state: No dedicated app configured yet
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.phone_android_rounded, color: AppColors.textSecondary, size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dedicated School Management App',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Not Configured • 1 School → 1 Dedicated App Architecture',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'This school does not have a dedicated mobile app record configured yet. Create a record to assign package name, version, and manage backend SaaS API access.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: () => _showCreateAppModal(school),
                    icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
                    label: const Text('Create School App Record'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final subAsync = ref.watch(schoolAppSubscriptionProvider(app.id));
        final subscription = subAsync.asData?.value;
        final accessResult = evaluateSchoolManagementAppAccess(
          schoolStatus: school.status,
          appStatus: app.status,
          subscription: subscription,
        );

        // App is configured - Display complete App Provisioning & Developer Setup!
        return Column(
          children: [
            // 1. App Provisioning Card (Phase 6 Requirement 1)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: app.isActive ? AppColors.primary.withValues(alpha: 0.3) : const Color(0xFFCBD5E1),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: app.isActive ? AppColors.primarySubtle : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.smartphone_rounded,
                            color: app.isActive ? AppColors.primary : AppColors.textSecondary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      app.appName,
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: app.isActive ? AppColors.successSubtle : const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: app.isActive ? AppColors.success.withValues(alpha: 0.4) : AppColors.error.withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Text(
                                      app.isActive ? 'ACCESS: ACTIVE' : 'ACCESS: INACTIVE',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: app.isActive ? AppColors.successText : AppColors.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'App Identifier: ${app.appIdentifier ?? "None"} • Package: ${app.packageName ?? "None"}',
                                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 10),

                    // App Provisioning Attributes (Phase 6 Requirement 1)
                    _copyableInfoRow('School Name', school.name, copyable: false),
                    _copyableInfoRow('School ID (UUID)', school.id),
                    _copyableInfoRow('App Name', app.appName),
                    _copyableInfoRow('App Identifier', app.appIdentifier ?? 'Not set'),
                    _copyableInfoRow('Android Package Name', app.packageName ?? 'Not set'),
                    _copyableInfoRow('Current Version', app.currentVersion),
                    _copyableInfoRow('Play Store URL', app.playStoreUrl ?? 'Not published to store yet'),
                    _infoRowWidget('App Status', _buildStatusBadge(app.status.displayName.toUpperCase(), app.isActive)),
                    _infoRowWidget(
                      'Subscription Status',
                      _buildStatusBadge(
                        subscription != null
                            ? (subscription.status == SubscriptionStatus.active ? 'ACTIVE (${subscription.planName})' : subscription.status.displayName.toUpperCase())
                            : 'NO SUBSCRIPTION',
                        subscription?.status == SubscriptionStatus.active,
                      ),
                    ),
                    _infoRowWidget(
                      'Effective Access',
                      _buildStatusBadge(
                        accessResult.isGranted ? 'ACTIVE (GRANTED)' : 'RESTRICTED (BLOCKED)',
                        accessResult.isGranted,
                      ),
                    ),
                    if (app.notes != null && app.notes!.isNotEmpty)
                      _infoRow('Developer Notes', app.notes!),
                    _infoRow('Registered On', dateFormat.format(app.createdAt)),
                    if (app.updatedAt != null)
                      _infoRow('Last Updated', dateFormat.format(app.updatedAt!)),

                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),

                    // Action Buttons: Edit Metadata & Toggle Access
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _showEditAppModal(app),
                          icon: const Icon(Icons.edit_note_rounded, size: 16),
                          label: const Text('Edit App Metadata'),
                        ),
                        if (app.isActive)
                          OutlinedButton.icon(
                            onPressed: () => _toggleAppAccess(app),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error),
                            ),
                            icon: const Icon(Icons.block_rounded, size: 16),
                            label: const Text('Deactivate Access'),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: () => _toggleAppAccess(app),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                            ),
                            icon: const Icon(Icons.check_circle_rounded, size: 16),
                            label: const Text('Activate Access'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Developer App Configuration (Phase 6 Requirement 5)
            _buildDeveloperConfigCard(context, school, app),
            const SizedBox(height: 16),

            // 3. Android Studio Workflow Setup Guide (Phase 6 Requirement 6)
            _buildDeveloperWorkflowGuide(context, app),
          ],
        );
      },
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionAndAccessSection(BuildContext context, SchoolModel school, DateFormat dateFormat) {
    final appAsync = ref.watch(schoolDedicatedAppProvider(school.id));

    return appAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (app) {
        if (app == null) {
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_clock_rounded, color: AppColors.textSecondary, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Subscription & Access',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    'A dedicated School Management App record must be created first before provisioning subscription and managing effective access.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        final subAsync = ref.watch(schoolAppSubscriptionProvider(app.id));
        final dateDisplayFormat = DateFormat('dd-MM-yyyy');

        return subAsync.when(
          loading: () => Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(height: 12),
                    Text('Loading subscription & access standing...', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
          error: (err, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                      SizedBox(width: 8),
                      Text('Subscription Status', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    err.toString().replaceFirst('Exception: ', ''),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => ref.invalidate(schoolAppSubscriptionProvider(app.id)),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry Connection'),
                  ),
                ],
              ),
            ),
          ),
          data: (subscription) {
            // Centralized date-aware access evaluation
            final accessResult = evaluateSchoolManagementAppAccess(
              schoolStatus: school.status,
              appStatus: app.status,
              subscription: subscription,
            );

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: accessResult.isGranted
                      ? AppColors.success.withValues(alpha: 0.3)
                      : AppColors.error.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Subscription & Access',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                        if (subscription != null)
                          SubscriptionStatusChip(status: subscription.status)
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'NO SUBSCRIPTION',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ==========================================
                    // VISUALLY PROMINENT EFFECTIVE ACCESS BANNER
                    // ==========================================
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: accessResult.isGranted
                            ? const Color(0xFFF0FDF4)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: accessResult.isGranted
                              ? const Color(0xFF86EFAC)
                              : const Color(0xFFFCA5A5),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            accessResult.isGranted
                                ? Icons.check_circle_rounded
                                : Icons.block_rounded,
                            size: 26,
                            color: accessResult.isGranted
                                ? AppColors.success
                                : AppColors.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  accessResult.isGranted
                                      ? 'EFFECTIVE ACCESS: GRANTED'
                                      : 'EFFECTIVE ACCESS: BLOCKED',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: accessResult.isGranted
                                        ? const Color(0xFF166534)
                                        : const Color(0xFF991B1B),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  accessResult.userMessage,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: accessResult.isGranted
                                        ? const Color(0xFF15803D)
                                        : const Color(0xFFB91C1C),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  accessResult.detailedReason,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: accessResult.isGranted
                                        ? const Color(0xFF166534).withValues(alpha: 0.8)
                                        : const Color(0xFF991B1B).withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1),
                    const SizedBox(height: 10),

                    // Subscription Metadata Rows
                    _infoRow('School Management App', app.appName),
                    _infoRow('App Status', app.status.displayName.toUpperCase()),
                    _infoRow(
                      'Subscription Status',
                      subscription != null
                          ? subscription.status.displayName.toUpperCase()
                          : 'Not Configured',
                    ),
                    if (subscription != null) ...[
                      _infoRow('Plan Name', subscription.planName),
                      _infoRow('Start Date', dateDisplayFormat.format(subscription.startDate)),
                      _infoRow('End Date', dateDisplayFormat.format(subscription.endDate)),
                      _infoRow(
                        'Date Standing',
                        subscription.isDateExpired
                            ? 'EXPIRED (End date passed)'
                            : (subscription.isDateNotStarted
                                ? 'SCHEDULED (Starts in future)'
                                : 'CURRENT (Within valid window)'),
                      ),
                      if (subscription.notes != null && subscription.notes!.isNotEmpty)
                        _infoRow('Subscription Notes', subscription.notes!),
                    ],

                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),

                    // Actions
                    if (subscription == null) ...[
                      ElevatedButton.icon(
                        onPressed: () => _showCreateSubscriptionModal(school, app),
                        icon: const Icon(Icons.add_task_rounded, size: 18),
                        label: const Text('Create Subscription'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                      ),
                    ] else ...[
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _showEditSubscriptionModal(school, app, subscription),
                            icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                            label: const Text('Edit Subscription'),
                          ),
                          if (subscription.status != SubscriptionStatus.active)
                            ElevatedButton.icon(
                              onPressed: () => _updateSubscriptionStatus(
                                app,
                                subscription,
                                SubscriptionStatus.active,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                              ),
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                              label: const Text('Activate'),
                            ),
                          if (subscription.status != SubscriptionStatus.suspended)
                            OutlinedButton.icon(
                              onPressed: () => _updateSubscriptionStatus(
                                app,
                                subscription,
                                SubscriptionStatus.suspended,
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.warning,
                                side: const BorderSide(color: AppColors.warning),
                              ),
                              icon: const Icon(Icons.pause_circle_outline_rounded, size: 16),
                              label: const Text('Suspend'),
                            ),
                          if (subscription.status != SubscriptionStatus.inactive)
                            OutlinedButton.icon(
                              onPressed: () => _updateSubscriptionStatus(
                                app,
                                subscription,
                                SubscriptionStatus.inactive,
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error,
                                side: const BorderSide(color: AppColors.error),
                              ),
                              icon: const Icon(Icons.cancel_outlined, size: 16),
                              label: const Text('Deactivate'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showCreateSubscriptionModal(SchoolModel school, SchoolAppModel app) {
    final formKey = GlobalKey<FormState>();
    final planController = TextEditingController(text: 'Annual School License');
    final notesController = TextEditingController();
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 365));
    SubscriptionStatus selectedStatus = SubscriptionStatus.active;
    bool isSaving = false;
    final dateDisplayFormat = DateFormat('dd-MM-yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Create Subscription',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dedicated App: ${app.appName} (${school.name})',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 14),

                    // Contextual IDs - Displayed read-only, never manually typed
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.link_rounded, size: 15, color: AppColors.primary),
                              SizedBox(width: 6),
                              Text(
                                'Linked Context (Auto-Bound)',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('School: ${school.name} (ID: ${school.id})',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'monospace')),
                          const SizedBox(height: 2),
                          Text('App ID: ${app.id}',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Plan Name
                    TextFormField(
                      controller: planController,
                      decoration: const InputDecoration(
                        labelText: 'Plan Name *',
                        hintText: 'e.g. Annual School License',
                        prefixIcon: Icon(Icons.card_membership_rounded, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Plan name is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Start Date & End Date pickers
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: startDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setModalState(() {
                                  startDate = picked;
                                  if (endDate.isBefore(startDate)) {
                                    endDate = startDate.add(const Duration(days: 365));
                                  }
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Start Date *',
                                prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                              ),
                              child: Text(
                                dateDisplayFormat.format(startDate),
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: endDate,
                                firstDate: startDate,
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setModalState(() => endDate = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'End Date *',
                                prefixIcon: Icon(Icons.event_available_rounded, size: 18),
                              ),
                              child: Text(
                                dateDisplayFormat.format(endDate),
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Status Dropdown
                    DropdownButtonFormField<SubscriptionStatus>(
                      initialValue: selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Initial Subscription Status',
                        prefixIcon: Icon(Icons.shield_outlined, size: 20),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: SubscriptionStatus.active,
                          child: Text('Active'),
                        ),
                        DropdownMenuItem(
                          value: SubscriptionStatus.inactive,
                          child: Text('Inactive'),
                        ),
                        DropdownMenuItem(
                          value: SubscriptionStatus.suspended,
                          child: Text('Suspended'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedStatus = val);
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Notes
                    TextFormField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Subscription Notes (Optional)',
                        hintText: 'Contract reference, special terms, or billing contact',
                        prefixIcon: Icon(Icons.notes_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Submit
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                if (endDate.isBefore(startDate)) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('End date cannot be earlier than start date.'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                  return;
                                }

                                setModalState(() => isSaving = true);
                                final repo = ref.read(subscriptionRepositoryProvider);
                                final messenger = ScaffoldMessenger.of(context);
                                final nav = Navigator.of(modalCtx);

                                final res = await repo.createSubscription(
                                  schoolAppId: app.id,
                                  planName: planController.text.trim(),
                                  startDate: startDate,
                                  endDate: endDate,
                                  status: selectedStatus,
                                  notes: notesController.text.trim(),
                                );

                                setModalState(() => isSaving = false);

                                if (res.isSuccess) {
                                  nav.pop();
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Subscription created & verified successfully in Supabase!'),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                  ref.invalidate(schoolAppSubscriptionProvider(app.id));
                                } else {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(res.errorOrNull ?? 'Failed to create subscription'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Provision Subscription'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditSubscriptionModal(SchoolModel school, SchoolAppModel app, SubscriptionModel subscription) {
    final formKey = GlobalKey<FormState>();
    final planController = TextEditingController(text: subscription.planName);
    final notesController = TextEditingController(text: subscription.notes ?? '');
    DateTime startDate = subscription.startDate;
    DateTime endDate = subscription.endDate;
    bool isSaving = false;
    final dateDisplayFormat = DateFormat('dd-MM-yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Subscription',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'App: ${app.appName} • School: ${school.name}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: planController,
                      decoration: const InputDecoration(
                        labelText: 'Plan Name *',
                        prefixIcon: Icon(Icons.card_membership_rounded, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Plan name is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: startDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setModalState(() => startDate = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Start Date *',
                                prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                              ),
                              child: Text(
                                dateDisplayFormat.format(startDate),
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: endDate,
                                firstDate: startDate,
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setModalState(() => endDate = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'End Date *',
                                prefixIcon: Icon(Icons.event_available_rounded, size: 18),
                              ),
                              child: Text(
                                dateDisplayFormat.format(endDate),
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Subscription Notes',
                        prefixIcon: Icon(Icons.notes_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                if (endDate.isBefore(startDate)) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('End date cannot be earlier than start date.'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                  return;
                                }

                                setModalState(() => isSaving = true);
                                final repo = ref.read(subscriptionRepositoryProvider);
                                final messenger = ScaffoldMessenger.of(context);
                                final nav = Navigator.of(modalCtx);

                                final res = await repo.updateSubscription(
                                  subscriptionId: subscription.id,
                                  planName: planController.text.trim(),
                                  startDate: startDate,
                                  endDate: endDate,
                                  notes: notesController.text.trim(),
                                );

                                setModalState(() => isSaving = false);

                                if (res.isSuccess) {
                                  nav.pop();
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Subscription updated & verified successfully!'),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                  ref.invalidate(schoolAppSubscriptionProvider(app.id));
                                } else {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(res.errorOrNull ?? 'Failed to update subscription'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Save Subscription Changes'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _updateSubscriptionStatus(
    SchoolAppModel app,
    SubscriptionModel subscription,
    SubscriptionStatus newStatus,
  ) async {
    final actionName = newStatus.displayName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$actionName Subscription?'),
        content: Text(
          'Are you sure you want to change the subscription status to ${newStatus.dbValue}?\n\n'
          '• School: ${subscription.schoolName}\n'
          '• App: ${app.appName}\n\n'
          'This will directly update and verify in the Supabase database.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == SubscriptionStatus.active
                  ? AppColors.success
                  : (newStatus == SubscriptionStatus.suspended ? AppColors.warning : AppColors.error),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(actionName),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(subscriptionRepositoryProvider);
    final res = await repo.updateStatus(
      subscriptionId: subscription.id,
      status: newStatus,
    );

    if (!mounted) return;
    if (res.isSuccess) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Subscription status set to ${newStatus.dbValue} & verified!'),
          backgroundColor: AppColors.success,
        ),
      );
      ref.invalidate(schoolAppSubscriptionProvider(app.id));
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(res.errorOrNull ?? 'Failed to update subscription status'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PHASE 6: PROVISIONING, DEVELOPER CONFIG, & WORKFLOW HELPERS
  // ===========================================================================

  Widget _buildOperationalSummaryCard(BuildContext context, SchoolModel school) {
    final appAsync = ref.watch(schoolDedicatedAppProvider(school.id));
    final app = appAsync.asData?.value;
    final subAsync = app != null ? ref.watch(schoolAppSubscriptionProvider(app.id)) : null;
    final subscription = subAsync?.asData?.value;

    final accessResult = evaluateSchoolManagementAppAccess(
      schoolStatus: school.status,
      appStatus: app?.status ?? SchoolAppStatus.inactive,
      subscription: subscription,
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primarySubtle,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.dashboard_customize_rounded, size: 20, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Operational Summary',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      Text(
                        'Central operational status for dedicated School Management App & SaaS standing',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildSummaryBadge(
                  label: 'School Status',
                  value: school.status.displayName.toUpperCase(),
                  isPositive: school.status == SchoolStatus.active,
                  icon: Icons.account_balance_rounded,
                ),
                _buildSummaryBadge(
                  label: 'Management App',
                  value: app != null ? (app.isActive ? 'ACTIVE' : 'INACTIVE') : 'NOT CONFIGURED',
                  isPositive: app?.isActive ?? false,
                  icon: Icons.smartphone_rounded,
                ),
                _buildSummaryBadge(
                  label: 'App Identifier',
                  value: app?.appIdentifier ?? '—',
                  isPositive: app?.appIdentifier != null && app!.appIdentifier!.isNotEmpty,
                  icon: Icons.badge_outlined,
                ),
                _buildSummaryBadge(
                  label: 'Android Package',
                  value: app?.packageName ?? '—',
                  isPositive: app?.packageName != null && app!.packageName!.isNotEmpty,
                  icon: Icons.android_rounded,
                ),
                _buildSummaryBadge(
                  label: 'Current Version',
                  value: app?.currentVersion ?? '—',
                  isPositive: app != null,
                  icon: Icons.tag_rounded,
                ),
                _buildSummaryBadge(
                  label: 'Subscription',
                  value: subscription != null
                      ? (subscription.status == SubscriptionStatus.active ? 'ACTIVE' : subscription.status.displayName.toUpperCase())
                      : 'NO SUBSCRIPTION',
                  isPositive: subscription?.status == SubscriptionStatus.active,
                  icon: Icons.card_membership_rounded,
                ),
                _buildSummaryBadge(
                  label: 'Effective Access',
                  value: accessResult.isGranted ? 'ACTIVE' : 'BLOCKED',
                  isPositive: accessResult.isGranted,
                  icon: accessResult.isGranted ? Icons.check_circle_outline_rounded : Icons.block_rounded,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBadge({
    required String label,
    required String value,
    required bool isPositive,
    required IconData icon,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: isPositive ? AppColors.successSubtle : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isPositive ? AppColors.successText : AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeveloperConfigCard(BuildContext context, SchoolModel school, SchoolAppModel app) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primarySubtle,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.terminal_rounded, size: 20, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Developer App Configuration',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      Text(
                        'Copyable parameters required when compiling the dedicated Android project in Android Studio',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),

            _copyableInfoRow('School', school.name),
            _copyableInfoRow('School ID', school.id),
            _copyableInfoRow('App Identifier', app.appIdentifier ?? '—'),
            _copyableInfoRow('App Name', app.appName),
            _copyableInfoRow('Package Name', app.packageName ?? '—'),
            _copyableInfoRow('Supabase Project URL', SupabaseConfig.url),
            _copyableInfoRow('Supabase Anon Key', SupabaseConfig.publishableKey),

            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: Color(0xFF16A34A)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Security Notice: Only public client configuration is exposed. Database passwords, auth admin secrets, and service-role keys remain strictly protected.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF166534), height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    final jsonText = _generateConfigJson(school: school, app: app);
                    _copyToClipboard(context, jsonText, 'Configuration JSON');
                  },
                  icon: const Icon(Icons.data_object_rounded, size: 16),
                  label: const Text('Copy Configuration (JSON)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    final propsText = _generateConfigProperties(school: school, app: app);
                    _copyToClipboard(context, propsText, 'Configuration Properties');
                  },
                  icon: const Icon(Icons.code_rounded, size: 16),
                  label: const Text('Copy Configuration (.env)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeveloperWorkflowGuide(BuildContext context, SchoolAppModel app) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.integration_instructions_rounded, size: 20, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Developer Setup (Android Studio Workflow)',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      Text(
                        'Step-by-step developer guide for manual Android project build and Play Store release',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildWorkflowStep(1, 'Copy Master Project', 'Copy the master School/Admin App project repository in Android Studio.'),
            _buildWorkflowStep(2, 'Change App Name', 'Set the branded app title to "${app.appName}" in android/app/src/main/res/values/strings.xml or manifest.'),
            _buildWorkflowStep(3, 'Change App Icon/Logo', 'Replace launcher icon assets in res/mipmap-* with the school branding assets.'),
            _buildWorkflowStep(4, 'Change Android Package Name', 'Set applicationId = "${app.packageName ?? 'com.company.schoolapp'}" in android/app/build.gradle.'),
            _buildWorkflowStep(5, 'Set APP_IDENTIFIER', 'Set AppConfig.appIdentifier = "${app.appIdentifier ?? 'ABC_SCHOOL_APP'}" or compile with --dart-define=APP_IDENTIFIER=${app.appIdentifier ?? 'ABC_SCHOOL_APP'}.'),
            _buildWorkflowStep(6, 'Verify Supabase Backend', 'Confirm the client connects to ${SupabaseConfig.url} with the public publishable anon key.'),
            _buildWorkflowStep(7, 'Build AAB in Android Studio', 'Select Build > Generate Signed Bundle / APK to produce the signed production Android App Bundle (.aab).'),
            _buildWorkflowStep(8, 'Publish to Google Play Store', 'Upload the signed .aab to Google Play Console under the school\'s dedicated developer account or listing.'),
            _buildWorkflowStep(9, 'Enter Released Version & URL', 'Once published, update Current Version ("${app.currentVersion}") and Play Store URL in this Super Admin panel.'),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkflowStep(int stepNumber, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$stepNumber',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String text, bool isPositive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isPositive ? AppColors.successSubtle : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isPositive ? AppColors.successText : AppColors.error,
        ),
      ),
    );
  }

  Widget _infoRowWidget(String label, Widget trailingWidget) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          trailingWidget,
        ],
      ),
    );
  }

  Widget _copyableInfoRow(String label, String value, {bool copyable = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (copyable && value != '—' && value.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _copyToClipboard(context, value, label),
                    child: const Padding(
                      padding: EdgeInsets.all(2.0),
                      child: Icon(Icons.copy_rounded, size: 15, color: AppColors.primary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard!'),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  String _generateConfigJson({
    required SchoolModel school,
    required SchoolAppModel app,
  }) {
    return '''{
  "school_name": "${school.name}",
  "school_id": "${school.id}",
  "app_identifier": "${app.appIdentifier ?? ''}",
  "app_name": "${app.appName}",
  "package_name": "${app.packageName ?? ''}",
  "current_version": "${app.currentVersion}",
  "supabase_url": "${SupabaseConfig.url}",
  "supabase_publishable_key": "${SupabaseConfig.publishableKey}"
}''';
  }

  String _generateConfigProperties({
    required SchoolModel school,
    required SchoolAppModel app,
  }) {
    return '''# Dedicated School Management App Developer Configuration
# Generated from Super Admin Panel
SCHOOL_NAME=${school.name}
SCHOOL_ID=${school.id}
APP_IDENTIFIER=${app.appIdentifier ?? ''}
APP_NAME=${app.appName}
PACKAGE_NAME=${app.packageName ?? ''}
CURRENT_VERSION=${app.currentVersion}
SUPABASE_URL=${SupabaseConfig.url}
SUPABASE_PUBLISHABLE_KEY=${SupabaseConfig.publishableKey}
''';
  }

  // ==========================================
  // SECTION 7: SCHOOL ADMINISTRATOR MANAGEMENT
  // ==========================================

  Widget _buildSchoolAdminSection(BuildContext context, SchoolModel school, DateFormat dateFormat) {
    final adminAsync = ref.watch(schoolAdminProvider(school.id));

    return adminAsync.when(
      loading: () => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.borderLight),
        ),
        child: const Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(height: 12),
                Text('Loading administrator account...', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
      error: (err, _) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.borderLight),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.errorSubtle,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('School Administrator', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        Text('Error loading administrator details', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(err.toString(), style: const TextStyle(fontSize: 13, color: AppColors.error)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(schoolAdminProvider(school.id)),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (admin) {
        if (admin == null) {
          // Unconfigured state
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.borderLight),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.textSecondary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'School Administrator',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Initial Administrator Account Provisioning',
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'NOT CONFIGURED',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'School Admin not configured',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Every active school requires an authoritative school administrator account to manage school operations, staff, and students.',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tenant Context: ${school.name} (${school.schoolCode})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: () => _showCreateAdminModal(school),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Create School Admin'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Configured state
        final isActive = admin.isActive;
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.borderLight),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isActive ? AppColors.successSubtle : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.admin_panel_settings_rounded,
                            color: isActive ? AppColors.successText : AppColors.textSecondary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              admin.fullName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              admin.email,
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primarySubtle,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            admin.role.toUpperCase(),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isActive ? AppColors.successSubtle : AppColors.errorSubtle,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            admin.status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isActive ? AppColors.successText : AppColors.errorText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 10),
                _infoRow('Full Name', admin.fullName),
                _infoRow('Email Address', admin.email),
                _infoRow('Phone Number', (admin.phone != null && admin.phone!.isNotEmpty) ? admin.phone! : 'Not provided'),
                _infoRow('System Role', admin.role),
                _infoRow('Designation', admin.designation ?? 'School Administrator'),
                _infoRow('Account Status', admin.status.toUpperCase()),
                _infoRow('Linked School', '${school.name} (${school.schoolCode})'),
                _infoRow('Authoritative Tenant ID', admin.schoolId),
                _infoRow('Supabase Auth User ID', admin.authUserId),
                if (admin.createdAt != null)
                  _infoRow('Created Date', dateFormat.format(admin.createdAt!)),
                if (admin.updatedAt != null)
                  _infoRow('Last Updated', dateFormat.format(admin.updatedAt!)),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showEditAdminModal(school, admin),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Edit Details'),
                    ),
                    if (isActive)
                      OutlinedButton.icon(
                        onPressed: () => _toggleAdminStatus(school, admin, 'inactive'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                        ),
                        icon: const Icon(Icons.block_rounded, size: 16),
                        label: const Text('Deactivate'),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: () => _toggleAdminStatus(school, admin, 'active'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                        label: const Text('Reactivate'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateAdminModal(SchoolModel school) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isSaving = false;
    String? errorMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Create School Administrator',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Provision initial administrator account for ${school.name}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    // Contextual IDs - Displayed read-only, never manually typed
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TARGET TENANT CONTEXT (AUTOMATICALLY ASSIGNED)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('School Name: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Text(school.name, style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Text('School Code: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Text(school.schoolCode, style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Text('Tenant ID: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Expanded(
                                child: Text(
                                  school.id,
                                  style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: AppColors.primary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.errorSubtle,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(fontSize: 12.5, color: AppColors.errorText),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Full Name
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        hintText: 'e.g. Rahul Sharma',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
                    ),
                    const SizedBox(height: 14),

                    // Email Address
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email Address *',
                        hintText: 'e.g. admin.school1@schoolos.test',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        final trimmed = v.trim();
                        if (!trimmed.contains('@') || !trimmed.contains('.')) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Phone Number
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number (Optional)',
                        hintText: 'e.g. +91 98765 43210',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Password
                    TextFormField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Initial Password *',
                        hintText: 'Minimum 6 characters',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setModalState(() => obscurePassword = !obscurePassword),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Password is required';
                        if (v.trim().length < 6) return 'Password must be at least 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Information Note
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB), size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This action will create an authenticated login in Supabase Auth and bind a profile with role "school_admin" to this school. Plaintext password is never saved in the profile database.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() {
                                  isSaving = true;
                                  errorMessage = null;
                                });

                                final repo = ref.read(schoolAdminRepositoryProvider);
                                final result = await repo.createSchoolAdmin(
                                  schoolId: school.id,
                                  fullName: nameController.text.trim(),
                                  email: emailController.text.trim(),
                                  phone: phoneController.text.trim().isNotEmpty
                                      ? phoneController.text.trim()
                                      : null,
                                  password: passwordController.text.trim(),
                                );

                                if (!modalCtx.mounted) return;

                                if (result.isSuccess) {
                                  Navigator.pop(modalCtx);
                                  ref.invalidate(schoolAdminProvider(school.id));
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('School Administrator account created successfully!'),
                                        backgroundColor: AppColors.success,
                                      ),
                                    );
                                  }
                                } else {
                                  setModalState(() {
                                    isSaving = false;
                                    errorMessage = result.errorOrNull ?? 'Failed to create school administrator.';
                                  });
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Create School Admin',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditAdminModal(SchoolModel school, SchoolAdminModel admin) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: admin.fullName);
    final phoneController = TextEditingController(text: admin.phone ?? '');
    bool isSaving = false;
    String? errorMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Administrator Details',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Account: ${admin.email}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    if (errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.errorSubtle,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(fontSize: 12.5, color: AppColors.errorText),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Full Name
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
                    ),
                    const SizedBox(height: 14),

                    // Phone Number
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Readonly Email note
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Email (${admin.email}) is linked to Supabase Auth and cannot be modified here.',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() {
                                  isSaving = true;
                                  errorMessage = null;
                                });

                                final repo = ref.read(schoolAdminRepositoryProvider);
                                final result = await repo.updateSchoolAdminProfile(
                                  profileId: admin.id,
                                  fullName: nameController.text.trim(),
                                  phone: phoneController.text.trim().isNotEmpty
                                      ? phoneController.text.trim()
                                      : null,
                                );

                                if (!modalCtx.mounted) return;

                                if (result.isSuccess) {
                                  Navigator.pop(modalCtx);
                                  ref.invalidate(schoolAdminProvider(school.id));
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Administrator details updated successfully!'),
                                        backgroundColor: AppColors.success,
                                      ),
                                    );
                                  }
                                } else {
                                  setModalState(() {
                                    isSaving = false;
                                    errorMessage = result.errorOrNull ?? 'Failed to update administrator.';
                                  });
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleAdminStatus(SchoolModel school, SchoolAdminModel admin, String newStatus) async {
    final isDeactivating = newStatus == 'inactive';
    final actionName = isDeactivating ? 'Deactivate' : 'Reactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$actionName School Administrator?'),
        content: Text(
          isDeactivating
              ? 'Are you sure you want to deactivate ${admin.fullName} (${admin.email})?\n\n'
                  'While inactive, this administrator will be blocked from accessing the School Management App.'
              : 'Are you sure you want to reactivate ${admin.fullName} (${admin.email})?\n\n'
                  'This will restore their access to the School Management App.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDeactivating ? AppColors.error : AppColors.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(actionName),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final repo = ref.read(schoolAdminRepositoryProvider);
    final result = await repo.updateSchoolAdminStatus(
      profileId: admin.id,
      newStatus: newStatus,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      ref.invalidate(schoolAdminProvider(school.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('School Administrator ${isDeactivating ? "deactivated" : "reactivated"} successfully.'),
          backgroundColor: isDeactivating ? AppColors.error : AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorOrNull ?? 'Failed to update administrator status.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ==============================================================================
  // SECTION 8: PER-STUDENT SCHOOL BILLING & INVOICES
  // ==============================================================================

  Widget _buildSchoolBillingSection(BuildContext context, SchoolModel school, DateFormat dateFormat) {
    final countsAsync = ref.watch(schoolStudentCountsProvider(school.id));
    final settingsAsync = ref.watch(schoolBillingSettingsProvider(school.id));
    final invoicesAsync = ref.watch(schoolInvoicesProvider(school.id));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Icon, Title, Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primarySubtle,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Per-Student School Billing',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '₹20 / student per billing period • Live Supabase Snapshot',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        final currentSettings = settingsAsync.asData?.value ??
                            SchoolBillingSettingsModel.defaultForSchool(school.id);
                        _showEditBillingRateDialog(school, currentSettings);
                      },
                      icon: const Icon(Icons.tune_rounded, size: 15),
                      label: const Text('Edit Rate'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        final counts = countsAsync.asData?.value ?? SchoolStudentCountSummary.empty(school.id);
                        final settings = settingsAsync.asData?.value ??
                            SchoolBillingSettingsModel.defaultForSchool(school.id);
                        _showGenerateBillModal(school, counts, settings);
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Generate Bill'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Live Metrics Strip (Student Count, Rate, Estimated Bill)
            countsAsync.when(
              loading: () => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Fetching live student metrics from Supabase...', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.errorSubtle,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Failed to load student counts: $err', style: const TextStyle(fontSize: 12, color: AppColors.errorText)),
              ),
              data: (counts) {
                final settings = settingsAsync.asData?.value ??
                    SchoolBillingSettingsModel.defaultForSchool(school.id);
                final estTotal = BillingConstants.calculateTotalAmount(
                  studentCount: counts.billableStudents,
                  ratePerStudent: settings.ratePerStudent,
                );

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      // Total Students
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Students', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text(
                              NumberFormat('#,###').format(counts.totalStudents),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            const Text('Enrolled in school', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 40, color: const Color(0xFFCBD5E1)),
                      const SizedBox(width: 16),
                      // Billable Students
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Billable Students', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text(
                              NumberFormat('#,###').format(counts.billableStudents),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              counts.selectedAcademicYearName != null
                                  ? 'AY: ${counts.selectedAcademicYearName}'
                                  : 'Active status',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 40, color: const Color(0xFFCBD5E1)),
                      const SizedBox(width: 16),
                      // Rate / Student
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Rate / Student', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text(
                              BillingConstants.formatCurrency(settings.ratePerStudent),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text('${settings.billingCycle.toLowerCase()} cycle', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 40, color: const Color(0xFFCBD5E1)),
                      const SizedBox(width: 16),
                      // Estimated Bill
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Current Period Bill', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text(
                              BillingConstants.formatCurrency(estTotal),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.success),
                            ),
                            const SizedBox(height: 2),
                            const Text('students × rate', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Section 9: School Financial Summary Strip
            ref.watch(schoolFinancialSummaryProvider(school.id)).when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => const SizedBox.shrink(),
                  data: (fin) {
                    if (!fin.hasInvoices) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildSummaryMetric('Current Bill', BillingConstants.formatCurrency(fin.currentBillAmount), AppColors.textPrimary),
                          _buildSummaryMetric('Total Billed', BillingConstants.formatCurrency(fin.totalBilled), const Color(0xFF2563EB)),
                          _buildSummaryMetric('Total Paid', BillingConstants.formatCurrency(fin.totalPaid), AppColors.success),
                          _buildSummaryMetric('Outstanding', BillingConstants.formatCurrency(fin.outstandingAmount), AppColors.warning),
                          if (fin.overdueAmount > 0)
                            _buildSummaryMetric('Overdue', BillingConstants.formatCurrency(fin.overdueAmount), AppColors.error),
                        ],
                      ),
                    );
                  },
                ),

            const SizedBox(height: 20),

            // Invoices History Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Invoice History',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: 'Refresh Invoices',
                  onPressed: () {
                    ref.invalidate(schoolInvoicesProvider(school.id));
                    ref.invalidate(schoolStudentCountsProvider(school.id));
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Invoices Table / List
            invoicesAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.errorSubtle,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Error loading invoices: $err', style: const TextStyle(color: AppColors.errorText, fontSize: 13)),
              ),
              data: (invoices) {
                if (invoices.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_outlined, size: 36, color: AppColors.textMuted),
                        const SizedBox(height: 10),
                        const Text(
                          'No Invoices Generated Yet',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Generate the first billing invoice for this school using the "Generate Bill" button above.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: invoices.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 10),
                  itemBuilder: (ctx, index) {
                    final inv = invoices[index];
                    return _buildInvoiceItemCard(ctx, school, inv, dateFormat);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetric(String title, String value, Color color) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }

  Widget _buildInvoiceStatusBadge(SchoolInvoiceModel inv) {
    Color bg;
    Color fg;
    String label;

    if (inv.isPaid) {
      bg = AppColors.successSubtle;
      fg = AppColors.successText;
      label = 'PAID';
    } else if (inv.status == InvoiceStatus.cancelled) {
      bg = const Color(0xFFF1F5F9);
      fg = const Color(0xFF64748B);
      label = 'CANCELLED';
    } else if (inv.isOverdue) {
      bg = const Color(0xFFFEE2E2);
      fg = AppColors.error;
      label = 'OVERDUE';
    } else {
      bg = const Color(0xFFFEF3C7);
      fg = AppColors.warning;
      label = 'UNPAID';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _buildInvoiceItemCard(
    BuildContext context,
    SchoolModel school,
    SchoolInvoiceModel inv,
    DateFormat dateFormat,
  ) {
    final periodDisplay =
        '${DateFormat('dd MMM yyyy').format(inv.billingPeriodStart)} — ${DateFormat('dd MMM yyyy').format(inv.billingPeriodEnd)}';
    final isPaid = inv.isPaid;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isPaid ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isPaid ? AppColors.successSubtle : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isPaid ? Icons.check_circle_outline_rounded : Icons.pending_actions_rounded,
              color: isPaid ? AppColors.success : AppColors.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      inv.displayInvoiceNumber,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.primary),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '($periodDisplay)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildInvoiceStatusBadge(inv),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Snapshot Students: ${NumberFormat('#,###').format(inv.studentCount)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    Text(
                      'Rate: ${BillingConstants.formatCurrency(inv.ratePerStudent)}/st',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    Text(
                      'Due: ${DateFormat('dd MMM yyyy').format(inv.dueDate)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (inv.academicYearName != null)
                      Text(
                        'AY: ${inv.academicYearName}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                BillingConstants.formatCurrency(inv.totalAmount),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => context.push('/invoices/${inv.id}'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 28),
                      textStyle: const TextStyle(fontSize: 11.5),
                    ),
                    child: const Text('View Details'),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () => _showInvoiceSnapshotModal(inv, dateFormat),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 28),
                      textStyle: const TextStyle(fontSize: 11.5),
                    ),
                    child: const Text('Snapshot'),
                  ),
                  const SizedBox(width: 6),
                  if (inv.canMarkPaid)
                    ElevatedButton(
                      onPressed: () => _showRecordPaymentDialog(inv),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 28),
                        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Mark Paid'),
                    )
                  else if (inv.isPaid)
                    OutlinedButton(
                      onPressed: () => _showMarkUnpaidDialog(inv),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 28),
                        textStyle: const TextStyle(fontSize: 11.5),
                      ),
                      child: const Text('Mark Unpaid'),
                    ),
                  if (inv.canCancel) ...[
                    const SizedBox(width: 6),
                    OutlinedButton(
                      onPressed: () => _showCancelInvoiceDialog(inv),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 28),
                        textStyle: const TextStyle(fontSize: 11.5),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEditBillingRateDialog(SchoolModel school, SchoolBillingSettingsModel settings) {
    final rateController = TextEditingController(text: settings.ratePerStudent.toStringAsFixed(2));
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Configure Billing Rate'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Update the per-student billing rate for ${school.name}.',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: rateController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Rate per Student (INR) *',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Rate is required';
                      final parsed = double.tryParse(v.trim());
                      if (parsed == null || parsed < 0) return 'Please enter a valid non-negative rate';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Color(0xFFD97706)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Important: Changing this rate will only apply to future invoices. Historical invoices retain their permanently frozen snapshot rate.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final newRate = double.parse(rateController.text.trim());
                        setDialogState(() => isSaving = true);

                        final messenger = ScaffoldMessenger.of(context);
                        final repo = ref.read(schoolBillingRepositoryProvider);
                        final res = await repo.updateBillingRate(school.id, newRate);

                        if (!dialogCtx.mounted) return;

                        if (res.isSuccess) {
                          Navigator.pop(dialogCtx);
                          ref.invalidate(schoolBillingSettingsProvider(school.id));
                          ref.invalidate(schoolBillingOverviewProvider(school.id));
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Billing rate updated successfully!'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        } else {
                          setDialogState(() => isSaving = false);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(res.errorOrNull ?? 'Failed to update billing rate'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                child: isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Rate'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showGenerateBillModal(
    SchoolModel school,
    SchoolStudentCountSummary counts,
    SchoolBillingSettingsModel settings,
  ) {
    final now = DateTime.now();
    DateTime startDate = DateTime(now.year, now.month, 1);
    DateTime endDate = DateTime(now.year, now.month + 1, 0);
    DateTime dueDate = now.add(const Duration(days: 15));
    String? selectedAyId = counts.selectedAcademicYearId;
    final notesController = TextEditingController();
    bool isGenerating = false;
    String? errorMessage;
    final dateDisplayFormat = DateFormat('dd-MM-yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final billableCount = counts.billableStudents;
          final totalAmount = BillingConstants.calculateTotalAmount(
            studentCount: billableCount,
            ratePerStudent: settings.ratePerStudent,
          );

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Generate School Bill',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'School: ${school.name} (${school.schoolCode})',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  if (errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorSubtle,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.errorText),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Confirmation Live Preview Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LIVE INVOICE SNAPSHOT CONFIRMATION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('School:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                            Text(school.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Academic Year:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                            Text(
                              counts.selectedAcademicYearName ??
                                  (counts.availableAcademicYears.isNotEmpty
                                      ? counts.availableAcademicYears.first.name
                                      : 'Not Configured'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: (counts.selectedAcademicYearName != null || counts.availableAcademicYears.isNotEmpty)
                                    ? AppColors.textPrimary
                                    : AppColors.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Billable Students:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                            Text(
                              NumberFormat('#,###').format(billableCount),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Rate per Student:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                            Text(
                              BillingConstants.formatCurrency(settings.ratePerStudent),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Amount:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            Text(
                              BillingConstants.formatCurrency(totalAmount),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.success),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (counts.availableAcademicYears.isEmpty && (counts.selectedAcademicYearId == null || counts.selectedAcademicYearId!.isEmpty)) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorSubtle,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.error_outline, color: AppColors.error, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Academic year is not configured for this school.',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.errorText),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (billableCount == 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warningSubtle,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No billable students found for the selected academic year.',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.warningText),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Academic Year selection if available
                  if (counts.availableAcademicYears.isNotEmpty) ...[
                    DropdownButtonFormField<String?>(
                      initialValue: selectedAyId,
                      decoration: const InputDecoration(
                        labelText: 'Academic Year',
                        prefixIcon: Icon(Icons.school_outlined, size: 20),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Academic Years')),
                        ...counts.availableAcademicYears.map(
                          (ay) => DropdownMenuItem(value: ay.id, child: Text(ay.name)),
                        ),
                      ],
                      onChanged: (val) => setModalState(() => selectedAyId = val),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Billing Period Pickers (Start & End Date)
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: startDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setModalState(() => startDate = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Period Start *',
                              prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                              border: OutlineInputBorder(),
                            ),
                            child: Text(dateDisplayFormat.format(startDate), style: const TextStyle(fontSize: 13)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: endDate,
                              firstDate: startDate,
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setModalState(() => endDate = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Period End *',
                              prefixIcon: Icon(Icons.event_available_rounded, size: 18),
                              border: OutlineInputBorder(),
                            ),
                            child: Text(dateDisplayFormat.format(endDate), style: const TextStyle(fontSize: 13)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Due Date
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: dueDate,
                        firstDate: startDate,
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setModalState(() => dueDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Payment Due Date *',
                        prefixIcon: Icon(Icons.schedule_rounded, size: 18),
                        border: OutlineInputBorder(),
                      ),
                      child: Text(dateDisplayFormat.format(dueDate), style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Notes
                  TextFormField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Invoice Notes (Optional)',
                      hintText: 'e.g. Monthly per-student platform subscription',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Confirm & Generate Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: isGenerating
                          ? null
                          : () async {
                              final bool hasAcademicYear = counts.selectedAcademicYearId != null ||
                                  (selectedAyId != null && selectedAyId!.isNotEmpty) ||
                                  counts.availableAcademicYears.isNotEmpty;
                              if (!hasAcademicYear) {
                                setModalState(() => errorMessage = 'Academic year is not configured for this school.');
                                return;
                              }

                              if (billableCount <= 0) {
                                setModalState(() => errorMessage = 'No billable students found for the selected academic year.');
                                return;
                              }

                              if (endDate.isBefore(startDate)) {
                                setModalState(() => errorMessage = 'Period End cannot be earlier than Period Start.');
                                return;
                              }

                              setModalState(() {
                                isGenerating = true;
                                errorMessage = null;
                              });

                              final messenger = ScaffoldMessenger.of(context);
                              final repo = ref.read(schoolBillingRepositoryProvider);
                              final res = await repo.generateInvoice(
                                schoolId: school.id,
                                academicYearId: selectedAyId,
                                billingPeriodStart: startDate,
                                billingPeriodEnd: endDate,
                                dueDate: dueDate,
                                notes: notesController.text.trim(),
                              );

                              if (!modalCtx.mounted) return;

                              if (res.isSuccess) {
                                Navigator.pop(modalCtx);
                                ref.invalidate(schoolInvoicesProvider(school.id));
                                ref.invalidate(schoolBillingOverviewProvider(school.id));
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Bill generated and frozen successfully!'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              } else {
                                setModalState(() {
                                  isGenerating = false;
                                  errorMessage = res.errorOrNull ?? 'Failed to generate invoice';
                                });
                              }
                            },
                      child: isGenerating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Confirm & Generate Bill Snapshot', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showInvoiceSnapshotModal(SchoolInvoiceModel inv, DateFormat dateFormat) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalCtx) {
        final periodDisplay =
            '${DateFormat('dd MMM yyyy').format(inv.billingPeriodStart)} — ${DateFormat('dd MMM yyyy').format(inv.billingPeriodEnd)}';
        final isPaid = inv.isPaid;

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isPaid ? AppColors.successSubtle : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.receipt_rounded, color: isPaid ? AppColors.success : AppColors.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Invoice Snapshot Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            Text('Status: ${inv.status.dbValue}', style: TextStyle(fontSize: 12, color: isPaid ? AppColors.successText : AppColors.error, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(modalCtx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 10),

                _copyableInfoRow('Invoice ID', inv.id),
                _copyableInfoRow('School ID', inv.schoolId),
                if (inv.schoolName != null) _infoRow('School Name', inv.schoolName!),
                if (inv.academicYearName != null) _infoRow('Academic Year', inv.academicYearName!),
                _infoRow('Billing Period', periodDisplay),
                _infoRow('Frozen Student Count', NumberFormat('#,###').format(inv.studentCount)),
                _infoRow('Snapshot Rate', BillingConstants.formatCurrency(inv.ratePerStudent)),
                _infoRow('Subtotal', BillingConstants.formatCurrency(inv.subtotal)),
                _infoRow('Total Bill Amount', BillingConstants.formatCurrency(inv.totalAmount)),
                _infoRow('Payment Due Date', DateFormat('dd MMM yyyy').format(inv.dueDate)),
                if (inv.paidAt != null)
                  _infoRow('Paid Timestamp', DateFormat('dd MMM yyyy, hh:mm a').format(inv.paidAt!)),
                _infoRow('Generated Timestamp', DateFormat('dd MMM yyyy, hh:mm a').format(inv.createdAt)),
                if (inv.notes != null && inv.notes!.isNotEmpty) _infoRow('Notes', inv.notes!),

                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF16A34A)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Security & Integrity: This invoice is an immutable snapshot. Future student enrollment changes or billing rate modifications will never alter this record.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF166534)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRecordPaymentDialog(SchoolInvoiceModel inv) {
    DateTime selectedDate = DateTime.now();
    PaymentMethod selectedMethod = PaymentMethod.bankTransfer;
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool loading = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Record Full Payment', style: TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Full payment only: Payment amount is fixed to the exact invoice total.',
                      style: TextStyle(fontSize: 12, color: AppColors.info, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Payment Amount', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      BillingConstants.formatCurrency(inv.totalAmount),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<PaymentMethod>(
                    initialValue: selectedMethod,
                    items: PaymentMethod.values.map((m) => DropdownMenuItem(value: m, child: Text(m.displayName))).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedMethod = val);
                    },
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  ),
                  const SizedBox(height: 12),
                  const Text('Payment Reference (UTR / Cheque)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Reference number...', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  ),
                  const SizedBox(height: 12),
                  const Text('Notes (Optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Payment notes...', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      setDialogState(() => loading = true);
                      final messenger = ScaffoldMessenger.of(context);
                      final repo = ref.read(schoolBillingRepositoryProvider);
                      final res = await repo.recordPayment(
                        invoiceId: inv.id,
                        amount: inv.totalAmount,
                        paymentMethod: selectedMethod,
                        paymentDate: selectedDate,
                        paymentReference: refCtrl.text.trim(),
                        notes: notesCtrl.text.trim(),
                      );
                      if (dialogCtx.mounted) {
                        Navigator.pop(dialogCtx);
                      }
                      if (mounted) {
                        if (res.isSuccess) {
                          ref.invalidate(schoolInvoicesProvider(inv.schoolId));
                          ref.invalidate(schoolFinancialSummaryProvider(inv.schoolId));
                          ref.invalidate(schoolBillingOverviewProvider(inv.schoolId));
                          messenger.showSnackBar(
                            SnackBar(content: Text('Payment recorded for ${inv.displayInvoiceNumber}'), backgroundColor: AppColors.success),
                          );
                        } else {
                          messenger.showSnackBar(
                            SnackBar(content: Text(res.errorOrNull ?? 'Failed to record payment'), backgroundColor: AppColors.error),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
              child: const Text('Confirm Payment'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMarkUnpaidDialog(SchoolInvoiceModel inv) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Mark as Unpaid?'),
        content: Text('Are you sure you want to revert ${inv.displayInvoiceNumber} to UNPAID?\n\nHistorical payment records will be preserved and marked voided.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final repo = ref.read(schoolBillingRepositoryProvider);
              final res = await repo.markAsUnpaid(invoiceId: inv.id);
              if (mounted) {
                if (res.isSuccess) {
                  ref.invalidate(schoolInvoicesProvider(inv.schoolId));
                  ref.invalidate(schoolFinancialSummaryProvider(inv.schoolId));
                  ref.invalidate(schoolBillingOverviewProvider(inv.schoolId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invoice marked as UNPAID'), backgroundColor: AppColors.info),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res.errorOrNull ?? 'Failed to revert payment'), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning, foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showCancelInvoiceDialog(SchoolInvoiceModel inv) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Cancel Invoice?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to cancel ${inv.displayInvoiceNumber}?'),
            const SizedBox(height: 8),
            const Text('Cancelled invoices remain in database for audit history and cannot be un-cancelled.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Cancellation reason...'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Keep Active')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final repo = ref.read(schoolBillingRepositoryProvider);
              final res = await repo.cancelInvoice(invoiceId: inv.id, reason: reasonCtrl.text.trim());
              if (mounted) {
                if (res.isSuccess) {
                  ref.invalidate(schoolInvoicesProvider(inv.schoolId));
                  ref.invalidate(schoolFinancialSummaryProvider(inv.schoolId));
                  ref.invalidate(schoolBillingOverviewProvider(inv.schoolId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invoice cancelled'), backgroundColor: AppColors.sidebarDark),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res.errorOrNull ?? 'Failed to cancel invoice'), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Cancel Invoice'),
          ),
        ],
      ),
    );
  }
}
