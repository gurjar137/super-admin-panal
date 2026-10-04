import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../models/school_admin_model.dart';
import '../../models/school_app_model.dart';
import '../../models/school_model.dart';
import '../../models/school_provision_dto.dart';
import '../../models/subscription_model.dart';
import '../../repositories/school_admin_repository.dart';
import '../../repositories/school_app_repository.dart';
import '../../repositories/school_repository.dart';
import '../../repositories/subscription_repository.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_text_field.dart';

class SchoolProvisioningScreen extends ConsumerStatefulWidget {
  const SchoolProvisioningScreen({super.key});

  @override
  ConsumerState<SchoolProvisioningScreen> createState() =>
      _SchoolProvisioningScreenState();
}

class _SchoolProvisioningScreenState extends ConsumerState<SchoolProvisioningScreen> {
  int _currentStep = 0;
  bool _isProcessing = false;
  String? _stepError;

  // Step 1: School Controllers
  final _schoolNameCtrl = TextEditingController();
  final _schoolCodeCtrl = TextEditingController();
  final _schoolEmailCtrl = TextEditingController();
  final _schoolPhoneCtrl = TextEditingController();
  final _schoolAddressCtrl = TextEditingController();
  final _schoolLogoCtrl = TextEditingController();
  SchoolStatus _schoolStatus = SchoolStatus.active;

  // Step 2: App Controllers
  final _appNameCtrl = TextEditingController();
  final _appIdentifierCtrl = TextEditingController();
  final _packageNameCtrl = TextEditingController();
  final _appVersionCtrl = TextEditingController(text: '1.0.0');
  final _playStoreUrlCtrl = TextEditingController();
  SchoolAppStatus _appStatus = SchoolAppStatus.active;

  // Step 3: Admin Controllers
  final _adminNameCtrl = TextEditingController();
  final _adminEmailCtrl = TextEditingController();
  final _adminPhoneCtrl = TextEditingController();
  final _adminPasswordCtrl = TextEditingController();
  bool _obscureAdminPassword = true;

  // Step 4: Subscription Controllers
  final _planNameCtrl = TextEditingController(text: 'Annual School License');
  DateTime _startDate = DateTime.now();
  late DateTime _endDate = DateTime.now().add(const Duration(days: 365));
  SubscriptionStatus _subStatus = SubscriptionStatus.active;
  final _subNotesCtrl = TextEditingController(text: 'Initial school provisioning subscription');

  // Created entities
  SchoolModel? _createdSchool;
  SchoolAppModel? _createdApp;
  SchoolAdminModel? _createdAdmin;
  SubscriptionModel? _createdSubscription;

  @override
  void dispose() {
    _schoolNameCtrl.dispose();
    _schoolCodeCtrl.dispose();
    _schoolEmailCtrl.dispose();
    _schoolPhoneCtrl.dispose();
    _schoolAddressCtrl.dispose();
    _schoolLogoCtrl.dispose();

    _appNameCtrl.dispose();
    _appIdentifierCtrl.dispose();
    _packageNameCtrl.dispose();
    _appVersionCtrl.dispose();
    _playStoreUrlCtrl.dispose();

    _adminNameCtrl.dispose();
    _adminEmailCtrl.dispose();
    _adminPhoneCtrl.dispose();
    _adminPasswordCtrl.dispose();

    _planNameCtrl.dispose();
    _subNotesCtrl.dispose();
    super.dispose();
  }

  void _onSchoolCodeChanged(String val) {
    final normalized = SchoolProvisionDto.normalizeCode(val);
    if (normalized != val) {
      _schoolCodeCtrl.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
  }

  // STEP 1: CREATE SCHOOL
  Future<void> _handleCreateSchool() async {
    setState(() => _stepError = null);
    final name = _schoolNameCtrl.text.trim();
    final code = SchoolProvisionDto.normalizeCode(_schoolCodeCtrl.text);

    if (name.isEmpty) {
      setState(() => _stepError = 'School Name is required.');
      return;
    }
    if (code.isEmpty || code.length < 3) {
      setState(() => _stepError = 'School Code must be at least 3 characters.');
      return;
    }

    setState(() => _isProcessing = true);
    final repo = ref.read(schoolRepositoryProvider);
    final result = await repo.createSchool(
      name: name,
      schoolCode: code,
      address: _schoolAddressCtrl.text.trim(),
      phone: _schoolPhoneCtrl.text.trim(),
      email: _schoolEmailCtrl.text.trim().toLowerCase(),
      logoUrl: _schoolLogoCtrl.text.trim(),
      status: _schoolStatus,
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result.isSuccess && result.dataOrNull != null) {
      final school = result.dataOrNull!;
      setState(() {
        _createdSchool = school;
        _currentStep = 1;
        // Pre-fill Step 2 values based on created school
        _appNameCtrl.text = '${school.name} App';
        _appIdentifierCtrl.text = '${school.schoolCode.replaceAll('-', '_')}_APP'.toUpperCase();
        final safePkgCode = school.schoolCode.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
        _packageNameCtrl.text = 'com.school.app.$safePkgCode';
      });
    } else {
      setState(() => _stepError = result.errorOrNull ?? 'Failed to create school');
    }
  }

  // STEP 2: CONFIGURE APP
  Future<void> _handleConfigureApp() async {
    if (_createdSchool == null) return;
    setState(() => _stepError = null);

    final appName = _appNameCtrl.text.trim();
    final appIdentifier = _appIdentifierCtrl.text.trim().toUpperCase();
    final packageName = _packageNameCtrl.text.trim().toLowerCase();
    final version = _appVersionCtrl.text.trim().isNotEmpty ? _appVersionCtrl.text.trim() : '1.0.0';

    if (appName.isEmpty) {
      setState(() => _stepError = 'App Name is required.');
      return;
    }
    if (appIdentifier.isEmpty) {
      setState(() => _stepError = 'App Identifier is required.');
      return;
    }
    if (packageName.isEmpty) {
      setState(() => _stepError = 'Android Package Name is required.');
      return;
    }

    setState(() => _isProcessing = true);
    final appRepo = ref.read(schoolAppRepositoryProvider);
    final result = await appRepo.createSchoolApp(
      schoolId: _createdSchool!.id,
      appName: appName,
      appIdentifier: appIdentifier,
      packageName: packageName,
      currentVersion: version,
      playStoreUrl: _playStoreUrlCtrl.text.trim(),
      status: _appStatus,
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result.isSuccess && result.dataOrNull != null) {
      setState(() {
        _createdApp = result.dataOrNull!;
        _currentStep = 2;
      });
    } else {
      setState(() => _stepError = result.errorOrNull ?? 'Failed to register school management app');
    }
  }

  // STEP 3: CREATE SCHOOL ADMIN
  Future<void> _handleCreateAdmin() async {
    if (_createdSchool == null) return;
    setState(() => _stepError = null);

    final name = _adminNameCtrl.text.trim();
    final email = _adminEmailCtrl.text.trim().toLowerCase();
    final phone = _adminPhoneCtrl.text.trim();
    final password = _adminPasswordCtrl.text;

    if (name.isEmpty) {
      setState(() => _stepError = 'Administrator Full Name is required.');
      return;
    }
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _stepError = 'Please enter a valid administrator email.');
      return;
    }
    if (password.length < 8) {
      setState(() => _stepError = 'Initial password must be at least 8 characters.');
      return;
    }

    setState(() => _isProcessing = true);
    final adminRepo = ref.read(schoolAdminRepositoryProvider);
    final result = await adminRepo.createSchoolAdmin(
      schoolId: _createdSchool!.id,
      fullName: name,
      email: email,
      phone: phone.isNotEmpty ? phone : null,
      password: password,
    );

    // CRITICAL SECURITY: Immediately wipe the plaintext password from memory
    _adminPasswordCtrl.clear();

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result.isSuccess && result.dataOrNull != null) {
      setState(() {
        _createdAdmin = result.dataOrNull!;
        _currentStep = 3;
      });
    } else {
      setState(() => _stepError = result.errorOrNull ?? 'Failed to create school administrator');
    }
  }

  // STEP 4: ACTIVATE SUBSCRIPTION
  Future<void> _handleActivateSubscription() async {
    if (_createdApp == null) return;
    setState(() => _stepError = null);

    final plan = _planNameCtrl.text.trim();
    if (plan.isEmpty) {
      setState(() => _stepError = 'Plan Name is required.');
      return;
    }
    if (_endDate.isBefore(_startDate)) {
      setState(() => _stepError = 'End Date cannot be earlier than Start Date.');
      return;
    }

    setState(() => _isProcessing = true);
    final subRepo = ref.read(subscriptionRepositoryProvider);
    final result = await subRepo.createSubscription(
      schoolAppId: _createdApp!.id,
      planName: plan,
      startDate: _startDate,
      endDate: _endDate,
      status: _subStatus,
      notes: _subNotesCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result.isSuccess && result.dataOrNull != null) {
      setState(() {
        _createdSubscription = result.dataOrNull!;
        _currentStep = 4;
      });
    } else {
      setState(() => _stepError = result.errorOrNull ?? 'Failed to activate subscription');
    }
  }

  void _resetWizard() {
    setState(() {
      _currentStep = 0;
      _stepError = null;
      _createdSchool = null;
      _createdApp = null;
      _createdAdmin = null;
      _createdSubscription = null;

      _schoolNameCtrl.clear();
      _schoolCodeCtrl.clear();
      _schoolEmailCtrl.clear();
      _schoolPhoneCtrl.clear();
      _schoolAddressCtrl.clear();
      _schoolLogoCtrl.clear();
      _schoolStatus = SchoolStatus.active;

      _appNameCtrl.clear();
      _appIdentifierCtrl.clear();
      _packageNameCtrl.clear();
      _appVersionCtrl.text = '1.0.0';
      _playStoreUrlCtrl.clear();
      _appStatus = SchoolAppStatus.active;

      _adminNameCtrl.clear();
      _adminEmailCtrl.clear();
      _adminPhoneCtrl.clear();
      _adminPasswordCtrl.clear();

      _planNameCtrl.text = 'Annual School License';
      _startDate = DateTime.now();
      _endDate = DateTime.now().add(const Duration(days: 365));
      _subStatus = SubscriptionStatus.active;
      _subNotesCtrl.text = 'Initial school provisioning subscription';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guided School Provisioning'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go(AppRoutes.schools),
        ),
      ),
      body: SingleChildScrollView(
        child: CenteredContentWrapper(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepperHeader(),
                const SizedBox(height: 24),
                if (_stepError != null) ...[
                  _buildErrorBanner(_stepError!),
                  const SizedBox(height: 16),
                ],
                _buildActiveStepContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepperHeader() {
    final steps = [
      '1. School',
      '2. Dedicated App',
      '3. Administrator',
      '4. Subscription',
      '5. Summary',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            final stepBefore = index ~/ 2;
            final isCompleted = _currentStep > stepBefore;
            return Expanded(
              child: Container(
                height: 2,
                color: isCompleted ? AppColors.primary : AppColors.borderLight,
              ),
            );
          }
          final stepIndex = index ~/ 2;
          final isActive = _currentStep == stepIndex;
          final isDone = _currentStep > stepIndex;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? AppColors.primary
                      : isActive
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : AppColors.surfaceLight,
                  border: Border.all(
                    color: isDone || isActive ? AppColors.primary : AppColors.borderLight,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text(
                          '${stepIndex + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isActive ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                steps[stepIndex],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? AppColors.textPrimary
                      : isDone
                          ? AppColors.primary
                          : AppColors.textSecondary,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1School();
      case 1:
        return _buildStep2App();
      case 2:
        return _buildStep3Admin();
      case 3:
        return _buildStep4Subscription();
      case 4:
      default:
        return _buildStep5Summary();
    }
  }

  // -------------------------------------------------------------
  // STEP 1: CREATE SCHOOL
  // -------------------------------------------------------------
  Widget _buildStep1School() {
    return _buildSectionCard(
      title: 'Step 1: School Identity & Registration',
      subtitle: 'Enter core school identity. The database UUID will be generated automatically.',
      icon: Icons.school_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _schoolNameCtrl,
            label: 'School Name *',
            hint: 'e.g. Oakridge International School',
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _schoolCodeCtrl,
            label: 'School Code (Unique Tenant Slug) *',
            hint: 'e.g. OAK-DEL-01',
            onChanged: _onSchoolCodeChanged,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _schoolEmailCtrl,
                  label: 'Official Email',
                  hint: 'contact@oakridge.edu',
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AppTextField(
                  controller: _schoolPhoneCtrl,
                  label: 'Official Phone',
                  hint: '+91 98765 43210',
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _schoolAddressCtrl,
            label: 'Campus Physical Address',
            hint: 'Plot 42, Institutional Area, Sector 5',
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _schoolLogoCtrl,
            label: 'Logo URL (Optional)',
            hint: 'https://cdn.example.com/logo.png',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<SchoolStatus>(
            initialValue: _schoolStatus,
            decoration: const InputDecoration(labelText: 'Initial Status'),
            items: const [
              DropdownMenuItem(value: SchoolStatus.active, child: Text('ACTIVE (Operational)')),
              DropdownMenuItem(value: SchoolStatus.inactive, child: Text('INACTIVE (Pending)')),
              DropdownMenuItem(value: SchoolStatus.suspended, child: Text('SUSPENDED')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _schoolStatus = val);
            },
          ),
          const SizedBox(height: 24),
          _buildActionButton(
            label: 'Create School & Continue',
            icon: Icons.arrow_forward_rounded,
            onPressed: _isProcessing ? null : _handleCreateSchool,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // STEP 2: CONFIGURE DEDICATED APP
  // -------------------------------------------------------------
  Widget _buildStep2App() {
    return _buildSectionCard(
      title: 'Step 2: Dedicated School Management App',
      subtitle: 'Bind a dedicated mobile client configuration to the newly created school UUID.',
      icon: Icons.mobile_friendly_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCreatedEntityBanner(
            title: 'Created School Tenant',
            name: _createdSchool!.name,
            code: _createdSchool!.schoolCode,
            id: _createdSchool!.id,
          ),
          const SizedBox(height: 20),
          AppTextField(
            controller: _appNameCtrl,
            label: 'App Display Name *',
            hint: 'e.g. Oakridge Management App',
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _appIdentifierCtrl,
            label: 'APP_IDENTIFIER (Build-Time Unique Constant) *',
            hint: 'e.g. OAK_APP',
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _packageNameCtrl,
            label: 'Android Package Name (Reverse Domain) *',
            hint: 'e.g. com.school.app.oakridge',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _appVersionCtrl,
                  label: 'Current Version *',
                  hint: '1.0.0',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<SchoolAppStatus>(
                  initialValue: _appStatus,
                  decoration: const InputDecoration(labelText: 'App Status'),
                  items: const [
                    DropdownMenuItem(value: SchoolAppStatus.active, child: Text('ACTIVE')),
                    DropdownMenuItem(value: SchoolAppStatus.inactive, child: Text('INACTIVE')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _appStatus = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _playStoreUrlCtrl,
            label: 'Play Store URL (Optional)',
            hint: 'https://play.google.com/store/apps/details?id=...',
          ),
          const SizedBox(height: 24),
          _buildActionButton(
            label: 'Register App & Continue',
            icon: Icons.arrow_forward_rounded,
            onPressed: _isProcessing ? null : _handleConfigureApp,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // STEP 3: CREATE SCHOOL ADMIN
  // -------------------------------------------------------------
  Widget _buildStep3Admin() {
    return _buildSectionCard(
      title: 'Step 3: Initial School Administrator',
      subtitle: 'Create the primary School Admin. The initial password is used transiently for signup.',
      icon: Icons.person_add_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCreatedEntityBanner(
            title: 'Created School & App',
            name: '${_createdSchool!.name} (${_createdApp!.appName})',
            code: _createdApp!.appIdentifier ?? '',
            id: _createdSchool!.id,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, size: 20, color: AppColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Security Guarantee: The initial password is used transiently to create the Supabase Auth user. It is NEVER saved to database tables, profiles, storage, or logs. The administrator will be required to change this password upon first login.',
                    style: TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _adminNameCtrl,
            label: 'Administrator Full Name *',
            hint: 'e.g. Dr. Arthur Pendelton',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _adminEmailCtrl,
                  label: 'Administrator Email *',
                  hint: 'principal@oakridge.edu',
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AppTextField(
                  controller: _adminPhoneCtrl,
                  label: 'Administrator Phone',
                  hint: '+91 99887 76655',
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _adminPasswordCtrl,
            obscureText: _obscureAdminPassword,
            decoration: InputDecoration(
              labelText: 'Initial Temporary Password *',
              hintText: 'At least 8 characters (e.g. TempAdmin@2026!)',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureAdminPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureAdminPassword = !_obscureAdminPassword),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildActionButton(
            label: 'Create Admin & Continue',
            icon: Icons.arrow_forward_rounded,
            onPressed: _isProcessing ? null : _handleCreateAdmin,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // STEP 4: ACTIVATE SUBSCRIPTION
  // -------------------------------------------------------------
  Widget _buildStep4Subscription() {
    final dateFormat = DateFormat('yyyy-MM-dd');

    return _buildSectionCard(
      title: 'Step 4: Activate Application License',
      subtitle: 'Create the authoritative subscription record linked to the dedicated School Management App.',
      icon: Icons.card_membership_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCreatedEntityBanner(
            title: 'School, App & Admin Configured',
            name: '${_createdSchool!.name} • Admin: ${_createdAdmin!.fullName}',
            code: _createdApp!.appIdentifier ?? '',
            id: _createdApp!.id,
          ),
          const SizedBox(height: 20),
          AppTextField(
            controller: _planNameCtrl,
            label: 'Plan Name *',
            hint: 'e.g. Annual School License',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start Date', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  subtitle: Text(dateFormat.format(_startDate), style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.calendar_today_rounded, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2025),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) setState(() => _startDate = picked);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('End Date', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  subtitle: Text(dateFormat.format(_endDate), style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.calendar_today_rounded, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _endDate,
                      firstDate: DateTime(2025),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) setState(() => _endDate = picked);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<SubscriptionStatus>(
            initialValue: _subStatus,
            decoration: const InputDecoration(labelText: 'Initial Subscription Status'),
            items: const [
              DropdownMenuItem(value: SubscriptionStatus.active, child: Text('ACTIVE')),
              DropdownMenuItem(value: SubscriptionStatus.inactive, child: Text('INACTIVE')),
              DropdownMenuItem(value: SubscriptionStatus.suspended, child: Text('SUSPENDED')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _subStatus = val);
            },
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _subNotesCtrl,
            label: 'Notes / Reference',
            hint: 'Initial provisioning license',
          ),
          const SizedBox(height: 24),
          _buildActionButton(
            label: 'Activate Subscription & Complete',
            icon: Icons.check_circle_rounded,
            onPressed: _isProcessing ? null : _handleActivateSubscription,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // STEP 5: FINAL PROVISIONING SUMMARY
  // -------------------------------------------------------------
  Widget _buildStep5Summary() {
    final dateFormat = DateFormat('yyyy-MM-dd');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Success Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.verified_rounded, size: 32, color: AppColors.success),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'School Provisioning Completed Successfully',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'All 4 architectural layers have been provisioned and bound in Supabase.',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Security Notice Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_rounded, size: 20, color: Color(0xFF15803D)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Initial password was set successfully. It will not be stored or displayed again. The administrator must set a permanent password upon first login.',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF15803D)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Summary Cards
        _buildSummaryCard(
          title: '1. Institution Entity (public.schools)',
          icon: Icons.apartment_rounded,
          items: [
            {'label': 'School Name', 'value': _createdSchool?.name ?? '—'},
            {'label': 'School Code', 'value': _createdSchool?.schoolCode ?? '—'},
            {'label': 'School UUID', 'value': _createdSchool?.id ?? '—', 'isUuid': true},
            {'label': 'Status', 'value': _createdSchool?.status.name.toUpperCase() ?? '—'},
          ],
        ),
        const SizedBox(height: 16),

        _buildSummaryCard(
          title: '2. Dedicated Mobile App (public.school_management_apps)',
          icon: Icons.smartphone_rounded,
          items: [
            {'label': 'App Name', 'value': _createdApp?.appName ?? '—'},
            {'label': 'APP_IDENTIFIER', 'value': _createdApp?.appIdentifier ?? '—'},
            {'label': 'Android Package', 'value': _createdApp?.packageName ?? '—'},
            {'label': 'Current Version', 'value': _createdApp?.currentVersion ?? '—'},
            {'label': 'Status', 'value': _createdApp?.status.name.toUpperCase() ?? '—'},
          ],
        ),
        const SizedBox(height: 16),

        _buildSummaryCard(
          title: '3. School Administrator (public.profiles & Supabase Auth)',
          icon: Icons.person_rounded,
          items: [
            {'label': 'Administrator Name', 'value': _createdAdmin?.fullName ?? '—'},
            {'label': 'Email Address', 'value': _createdAdmin?.email ?? '—'},
            {'label': 'Phone', 'value': _createdAdmin?.phone ?? '—'},
            {'label': 'Role', 'value': _createdAdmin?.role ?? '—'},
            {'label': 'Status', 'value': _createdAdmin?.status.toUpperCase() ?? '—'},
          ],
        ),
        const SizedBox(height: 16),

        _buildSummaryCard(
          title: '4. License & Subscription (public.school_app_subscriptions)',
          icon: Icons.card_membership_rounded,
          items: [
            {'label': 'Plan Name', 'value': _createdSubscription?.planName ?? '—'},
            {'label': 'Subscription Status', 'value': _createdSubscription?.status.name.toUpperCase() ?? '—'},
            {
              'label': 'Validity Window',
              'value': _createdSubscription != null
                  ? '${dateFormat.format(_createdSubscription!.startDate)} to ${dateFormat.format(_createdSubscription!.endDate)}'
                  : '—'
            },
          ],
        ),
        const SizedBox(height: 28),

        // Navigation Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.go(AppRoutes.schools),
                icon: const Icon(Icons.list_alt_rounded),
                label: const Text('Schools Directory'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => context.go(AppRoutes.schoolDetailsPath(_createdSchool!.id)),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Open School Details'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              tooltip: 'Provision Another School',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _resetWizard,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required IconData icon,
    required List<Map<String, dynamic>> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          const Divider(height: 20),
          ...items.map((it) {
            final isUuid = it['isUuid'] == true;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(
                      it['label'] as String,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            it['value'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: isUuid ? 'monospace' : null,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (isUuid) ...[
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 14, color: AppColors.textSecondary),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Copy UUID',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: it['value'] as String));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('UUID copied to clipboard')),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primarySubtle,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          child,
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: _isProcessing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon, size: 18),
        label: Text(
          _isProcessing ? 'Processing...' : label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildCreatedEntityBanner({
    required String title,
    required String name,
    required String code,
    required String id,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.successSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.successText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$name • $code',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'UUID: $id',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
