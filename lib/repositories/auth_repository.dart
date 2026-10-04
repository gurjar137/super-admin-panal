import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_result.dart';
import '../models/super_admin_model.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(authServiceProvider));
});

class AuthRepository {
  final AuthService _authService;

  AuthRepository(this._authService);

  Future<SuperAdminProfile?> getActiveSession() =>
      _authService.getActiveSuperAdminSession();

  Future<ApiResult<SuperAdminProfile>> signIn(String email, String password) =>
      _authService.signIn(email: email, password: password);

  Future<void> signOut() => _authService.signOut();

  Future<ApiResult<void>> requestPasswordReset(String email) =>
      _authService.requestPasswordReset(email);

  Future<ApiResult<void>> updatePassword(String newPassword) =>
      _authService.updatePassword(newPassword);
}
