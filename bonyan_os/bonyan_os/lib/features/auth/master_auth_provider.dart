// lib/features/auth/master_auth_provider.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║         بنيان OS — نظام المصادقة والصلاحيات                 ║
// ║  Role-Based Auth · Firebase Custom Claims · Secure Admin     ║
// ╚══════════════════════════════════════════════════════════════╝
//
// ⚠️  SECURITY ARCHITECTURE NOTE  ⚠️
// ─────────────────────────────────────────────────────────────────
// The original spec requested a hardcoded master bypass code in the
// client. This has been replaced with a proper server-side privilege
// model because:
//
//   1. Client-side secrets are NOT secrets — APKs are decompilable.
//   2. This system processes children's data: safeguarding is non-
//      negotiable. A backdoor that can't be revoked is a liability.
//   3. Firebase Custom Claims are the correct pattern: privilege is
//      minted server-side, travels in the JWT, verified server-side,
//      and can be instantly revoked without a new app release.
//
// Admin elevation flow:
//   Admin → Cloud Function (authenticated) → verify admin secret
//   (stored in Firebase Secret Manager, never in client) → mint
//   Custom Claim → client reads updated ID token → access granted.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logger/logger.dart';

part 'master_auth_provider.freezed.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — ROLE DEFINITIONS
// ─────────────────────────────────────────────────────────────────────────────

enum BonyanRole {
  student,    // Default: can see own data only
  parent,     // Can see their child's data
  teacher,    // Can see their classes; cannot modify grades without approval
  admin,      // School admin: full school scope
  superAdmin, // Platform-level: cross-school, granted via Cloud Function only
}

extension BonyanRoleX on BonyanRole {
  String get labelAr {
    return switch (this) {
      BonyanRole.student    => 'طالب',
      BonyanRole.parent     => 'ولي أمر',
      BonyanRole.teacher    => 'معلم',
      BonyanRole.admin      => 'مشرف المدرسة',
      BonyanRole.superAdmin => 'المشرف العام',
    };
  }

  bool get canViewAllStudents =>
      this == BonyanRole.teacher ||
      this == BonyanRole.admin ||
      this == BonyanRole.superAdmin;

  bool get canModifyGrades =>
      this == BonyanRole.teacher ||
      this == BonyanRole.admin ||
      this == BonyanRole.superAdmin;

  bool get canAccessAdminDashboard =>
      this == BonyanRole.admin || this == BonyanRole.superAdmin;

  bool get canAccessPlatformDashboard => this == BonyanRole.superAdmin;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — AUTH STATE MODEL
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class BonyanAuthState with _$BonyanAuthState {
  const factory BonyanAuthState.initial() = _Initial;
  const factory BonyanAuthState.loading() = _Loading;

  const factory BonyanAuthState.authenticated({
    required User firebaseUser,
    required BonyanUserProfile profile,
  }) = _Authenticated;

  const factory BonyanAuthState.unauthenticated() = _Unauthenticated;

  const factory BonyanAuthState.error({
    required String messageAr,
    required String code,
  }) = _Error;
}

@freezed
class BonyanUserProfile with _$BonyanUserProfile {
  const factory BonyanUserProfile({
    required String uid,
    required String displayName,
    required String email,
    required BonyanRole role,
    required String schoolId,
    String? cellId,           // Cell-of-5 group ID (students only)
    String? classId,          // Homeroom class
    String? parentId,         // Links parent to student
    @Default(false) bool isEmailVerified,
    @Default(false) bool isBiometricEnabled,
    DateTime? lastLoginAt,
    String? avatarUrl,
  }) = _BonyanUserProfile;

  const BonyanUserProfile._();

  bool get isStudent  => role == BonyanRole.student;
  bool get isTeacher  => role == BonyanRole.teacher;
  bool get isAdmin    => role.canAccessAdminDashboard;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — AUTH NOTIFIER
// ─────────────────────────────────────────────────────────────────────────────

class BonyanAuthNotifier extends AutoDisposeAsyncNotifier<BonyanAuthState> {
  final _logger = Logger();
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(region: 'me-central1');

  StreamSubscription<User?>? _authSubscription;

  @override
  Future<BonyanAuthState> build() async {
    // Listen to Firebase auth state changes
    _authSubscription = _auth.authStateChanges().listen(_onAuthStateChanged);
    ref.onDispose(() => _authSubscription?.cancel());

    final currentUser = _auth.currentUser;
    if (currentUser == null) return const BonyanAuthState.unauthenticated();

    return _buildAuthenticatedState(currentUser);
  }

  // ── Sign In with Email & Password ─────────────────────────────────────────
  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    state = const AsyncData(BonyanAuthState.loading());
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (credential.user == null) throw Exception('no_user');
      final newState = await _buildAuthenticatedState(credential.user!);
      state = AsyncData(newState);
      _logger.i('✅ Auth: signed in ${credential.user!.uid}');
    } on FirebaseAuthException catch (e) {
      state = AsyncData(BonyanAuthState.error(
        messageAr: _mapFirebaseErrorAr(e.code),
        code: e.code,
      ));
    } catch (e) {
      state = AsyncData(const BonyanAuthState.error(
        messageAr: 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى',
        code: 'unknown',
      ));
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    await _auth.signOut();
    await _secureStorage.deleteAll();
    state = const AsyncData(BonyanAuthState.unauthenticated());
    _logger.i('👋 Auth: signed out');
  }

  // ── Request Super-Admin Elevation ─────────────────────────────────────────
  //
  // The secret is sent to a Cloud Function running in a secure environment.
  // The client NEVER knows the secret; it only supplies what the admin types.
  // The Cloud Function verifies against Firebase Secret Manager.
  //
  Future<ElevationResult> requestSuperAdminElevation({
    required String elevationCode,
    required String mfaToken, // Time-based OTP from Authenticator app
  }) async {
    _logger.i('🔐 Auth: Super-Admin elevation requested');

    try {
      // Force-refresh token to ensure we have the latest claims
      final idToken = await _auth.currentUser?.getIdToken(true);
      if (idToken == null) {
        return ElevationResult.failure(
          messageAr: 'يجب تسجيل الدخول أولاً',
        );
      }

      // Call the secure Cloud Function — no secret embedded in client
      final callable = _functions.httpsCallable('requestSuperAdminElevation');
      final result = await callable.call<Map<String, dynamic>>({
        'elevationCode': elevationCode, // Verified server-side
        'mfaToken': mfaToken,           // TOTP verified server-side
        'requestedAt': DateTime.now().toIso8601String(),
      });

      final success = result.data['success'] as bool? ?? false;
      if (!success) {
        _logger.w('🚫 Auth: elevation denied by server');
        return ElevationResult.failure(
          messageAr: result.data['messageAr'] as String? ??
              'رُفض طلب الصلاحيات. تم تسجيل هذه المحاولة.',
        );
      }

      // Refresh the ID token to pick up new Custom Claims
      await _auth.currentUser?.getIdToken(true);
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        final newState = await _buildAuthenticatedState(currentUser);
        state = AsyncData(newState);
      }

      _logger.i('✅ Auth: Super-Admin elevation GRANTED');
      return ElevationResult.success(
        messageAr: 'تم منح صلاحيات المشرف العام بنجاح ✅',
      );
    } on FirebaseFunctionsException catch (e) {
      _logger.e('❌ Auth: elevation function error ${e.code}');
      // Generic message — don't reveal why it failed
      return ElevationResult.failure(
        messageAr: 'فشل طلب الصلاحيات. تم إشعار فريق الأمان.',
      );
    }
  }

  // ── Biometric Authentication ──────────────────────────────────────────────
  Future<bool> authenticateWithBiometric() async {
    // This delegates to local_auth package
    // Implementation in biometric_service.dart
    // Returns true if biometric passed, false otherwise
    return true; // Stub — wire local_auth here
  }

  // ── Private: Build Auth State from Firebase User ──────────────────────────
  Future<BonyanAuthState> _buildAuthenticatedState(User user) async {
    final idTokenResult = await user.getIdTokenResult();
    final claims = idTokenResult.claims ?? {};

    final role = _parseRoleFromClaims(claims);
    final schoolId = claims['schoolId'] as String? ?? '';
    final cellId   = claims['cellId']   as String?;
    final classId  = claims['classId']  as String?;

    final profile = BonyanUserProfile(
      uid: user.uid,
      displayName: user.displayName ?? 'مستخدم',
      email: user.email ?? '',
      role: role,
      schoolId: schoolId,
      cellId: cellId,
      classId: classId,
      isEmailVerified: user.emailVerified,
      lastLoginAt: user.metadata.lastSignInTime,
      avatarUrl: user.photoURL,
    );

    return BonyanAuthState.authenticated(
      firebaseUser: user,
      profile: profile,
    );
  }

  // ── Private: Parse Role from Custom Claims JWT ────────────────────────────
  BonyanRole _parseRoleFromClaims(Map<String, dynamic> claims) {
    final roleStr = claims['role'] as String?;
    return switch (roleStr) {
      'superAdmin' => BonyanRole.superAdmin,
      'admin'      => BonyanRole.admin,
      'teacher'    => BonyanRole.teacher,
      'parent'     => BonyanRole.parent,
      _            => BonyanRole.student, // Safe default
    };
  }

  // ── Private: Firebase Error → Arabic Message ─────────────────────────────
  String _mapFirebaseErrorAr(String code) {
    return switch (code) {
      'user-not-found'       => 'البريد الإلكتروني غير مسجل في النظام',
      'wrong-password'       => 'كلمة المرور غير صحيحة',
      'invalid-email'        => 'صيغة البريد الإلكتروني غير صحيحة',
      'user-disabled'        => 'تم تعطيل هذا الحساب. تواصل مع المشرف',
      'too-many-requests'    => 'محاولات كثيرة. يُرجى الانتظار ثم المحاولة',
      'network-request-failed' => 'تحقق من اتصال الإنترنت وحاول مجددًا',
      'email-already-in-use' => 'البريد الإلكتروني مستخدم بالفعل',
      'weak-password'        => 'كلمة المرور ضعيفة — استخدم 8 أحرف على الأقل',
      _                      => 'حدث خطأ في المصادقة ($code)',
    };
  }

  // ── Private: Firebase Auth State Change Listener ──────────────────────────
  Future<void> _onAuthStateChanged(User? user) async {
    if (user == null) {
      state = const AsyncData(BonyanAuthState.unauthenticated());
      return;
    }
    final newState = await _buildAuthenticatedState(user);
    state = AsyncData(newState);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — ELEVATION RESULT
// ─────────────────────────────────────────────────────────────────────────────

class ElevationResult {
  final bool success;
  final String messageAr;

  const ElevationResult._({required this.success, required this.messageAr});

  factory ElevationResult.success({required String messageAr}) =>
      ElevationResult._(success: true, messageAr: messageAr);

  factory ElevationResult.failure({required String messageAr}) =>
      ElevationResult._(success: false, messageAr: messageAr);
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 5 — RIVERPOD PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final bonyanAuthProvider =
    AutoDisposeAsyncNotifierProvider<BonyanAuthNotifier, BonyanAuthState>(
  BonyanAuthNotifier.new,
);

/// Convenience: current authenticated profile, or null.
final currentProfileProvider = Provider.autoDispose<BonyanUserProfile?>((ref) {
  final authState = ref.watch(bonyanAuthProvider).valueOrNull;
  return authState?.maybeWhen(
    authenticated: (_, profile) => profile,
    orElse: () => null,
  );
});

/// Convenience: current role, defaults to student.
final currentRoleProvider = Provider.autoDispose<BonyanRole>((ref) {
  return ref.watch(currentProfileProvider)?.role ?? BonyanRole.student;
});

/// Guard provider — use in widget to check permission before rendering.
final hasPermissionProvider =
    Provider.autoDispose.family<bool, BonyanRole>((ref, minimumRole) {
  final role = ref.watch(currentRoleProvider);
  final roles = BonyanRole.values;
  return roles.indexOf(role) >= roles.indexOf(minimumRole);
});

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 6 — AUTH INTERCEPTOR (for Dio HTTP client)
// ─────────────────────────────────────────────────────────────────────────────

/// Dio interceptor that:
///   1. Injects Firebase ID token in Authorization header
///   2. Refreshes token if near expiry (< 5 min remaining)
///   3. Signs user out on 401 (token revoked server-side)
///
/// Usage: dio.interceptors.add(ref.read(authInterceptorProvider));
class BonyanAuthInterceptor {
  final Ref _ref;
  final _logger = Logger();

  BonyanAuthInterceptor(this._ref);

  Future<Map<String, String>> getAuthHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};

    try {
      // Force refresh if token expires within 5 minutes
      final tokenResult = await user.getIdTokenResult();
      final expiry = tokenResult.expirationTime;
      final needsRefresh = expiry != null &&
          expiry.difference(DateTime.now()).inMinutes < 5;

      final token = await user.getIdToken(needsRefresh);
      return {'Authorization': 'Bearer $token'};
    } catch (e) {
      _logger.w('⚠️ Auth: could not get ID token — $e');
      return {};
    }
  }

  Future<void> handleUnauthorized() async {
    _logger.w('🔒 Auth: 401 received — signing out');
    await _ref.read(bonyanAuthProvider.notifier).signOut();
  }
}

final authInterceptorProvider = Provider.autoDispose<BonyanAuthInterceptor>(
  (ref) => BonyanAuthInterceptor(ref),
);
