// lib/features/attendance/smart_attendance_provider.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║      بنيان OS — نظام الحضور الذكي                           ║
// ║  QR Code + Geofencing (100m) + Anti-Spoofing                ║
// ╚══════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/event_bus.dart';
import '../auth/master_auth_provider.dart';

part 'smart_attendance_provider.freezed.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — MODELS
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class SchoolLocation with _$SchoolLocation {
  const factory SchoolLocation({
    required String schoolId,
    required double latitude,
    required double longitude,
    @Default(100.0) double radiusMeters, // 100m geofence
    required String nameAr,
  }) = _SchoolLocation;
}

@freezed
class AttendanceSession with _$AttendanceSession {
  const factory AttendanceSession({
    required String sessionId,
    required String classId,
    required String teacherId,
    required String subjectNameAr,
    required DateTime openedAt,
    DateTime? closedAt,
    @Default(15) int validWindowMinutes,
    required String qrToken,           // One-time rotating token
    required SchoolLocation location,
    @Default({}) Map<String, StudentRecord> records,
  }) = _AttendanceSession;

  const AttendanceSession._();

  bool get isOpen =>
      closedAt == null &&
      DateTime.now().difference(openedAt).inMinutes < validWindowMinutes;

  int get presentCount =>
      records.values.where((r) => r.isPresent).length;
  int get absentCount =>
      records.values.where((r) => !r.isPresent).length;
}

@freezed
class StudentRecord with _$StudentRecord {
  const factory StudentRecord({
    required String studentId,
    required String studentNameAr,
    required AttendanceStatus status,
    DateTime? markedAt,
    @Default(false) bool geofenceVerified,
    @Default(false) bool qrVerified,
    double? distanceMeters,
    String? deviceId,
  }) = _StudentRecord;

  const StudentRecord._();
  bool get isPresent => status == AttendanceStatus.present;
}

enum AttendanceStatus { present, absent, late, excused }

@freezed
class AttendanceResult with _$AttendanceResult {
  const factory AttendanceResult.success({
    required String message,
    required bool isLate,
    required double distanceMeters,
  }) = _Success;

  const factory AttendanceResult.failed({
    required String reasonAr,
    required AttendanceFailReason reason,
  }) = _Failed;
}

enum AttendanceFailReason {
  outsideGeofence,
  invalidQr,
  sessionClosed,
  alreadyMarked,
  locationPermissionDenied,
  spoofingDetected,
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — ATTENDANCE STATE
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class AttendanceState with _$AttendanceState {
  const factory AttendanceState({
    @Default([]) List<AttendanceSession> todaySessions,
    @Default(false) bool isMarking,
    @Default(false) bool isLoadingSessions,
    AttendanceResult? lastResult,
    Position? currentPosition,
    String? errorAr,
  }) = _AttendanceState;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — SMART ATTENDANCE NOTIFIER
// ─────────────────────────────────────────────────────────────────────────────

class SmartAttendanceNotifier
    extends AutoDisposeAsyncNotifier<AttendanceState> {
  final _logger = Logger();
  final _firestore = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  @override
  Future<AttendanceState> build() async {
    return const AttendanceState();
  }

  // ── MARK ATTENDANCE (Student side) ───────────────────────────────────────
  // Called after QR scan: validate geofence THEN token THEN write record.
  Future<AttendanceResult> markAttendance({
    required String scannedQrPayload, // JSON from QR
    required String studentId,
    required String studentNameAr,
  }) async {
    state = AsyncData(state.valueOrNull?.copyWith(isMarking: true) ?? const AttendanceState());

    try {
      // Step 1: Parse QR payload
      final qrData = _parseQrPayload(scannedQrPayload);
      if (qrData == null) {
        return _fail(AttendanceFailReason.invalidQr, 'رمز QR غير صالح أو منتهي الصلاحية');
      }

      // Step 2: Fetch session from Firestore
      final sessionDoc = await _firestore
          .collection('attendanceSessions')
          .doc(qrData['sessionId'] as String)
          .get();

      if (!sessionDoc.exists) {
        return _fail(AttendanceFailReason.sessionClosed, 'الجلسة غير موجودة');
      }

      final sessionData = sessionDoc.data()!;
      final openedAt = (sessionData['openedAt'] as Timestamp).toDate();
      final windowMin = sessionData['validWindowMinutes'] as int? ?? 15;
      final sessionClosed = DateTime.now().difference(openedAt).inMinutes > windowMin;

      if (sessionClosed) {
        return _fail(AttendanceFailReason.sessionClosed, 'انتهت نافذة تسجيل الحضور');
      }

      // Step 3: Check if already marked
      final alreadyMarked = (sessionData['records'] as Map<String, dynamic>?)
              ?.containsKey(studentId) ??
          false;
      if (alreadyMarked) {
        return _fail(AttendanceFailReason.alreadyMarked, 'تم تسجيل حضورك مسبقًا');
      }

      // Step 4: Verify QR token matches (one-time token)
      final storedToken = sessionData['qrToken'] as String?;
      final scannedToken = qrData['token'] as String?;
      if (storedToken != scannedToken) {
        _logger.w('⚠️ QR token mismatch for session ${qrData['sessionId']} — possible spoofing');
        return _fail(AttendanceFailReason.spoofingDetected,
            'رمز QR لا يطابق الجلسة. تم تسجيل هذه المحاولة');
      }

      // Step 5: Geofence verification
      final geoResult = await _verifyGeofence(
        schoolLat: (sessionData['schoolLat'] as num).toDouble(),
        schoolLng: (sessionData['schoolLng'] as num).toDouble(),
        radiusMeters: (sessionData['radiusMeters'] as num? ?? 100).toDouble(),
      );

      if (!geoResult.isInside) {
        _logger.w('📍 Student $studentId outside geofence: ${geoResult.distance.round()}m');
        return _fail(
          AttendanceFailReason.outsideGeofence,
          'أنت خارج نطاق المدرسة (${geoResult.distance.round()} متر). '
          'يجب أن تكون داخل ${geoResult.requiredRadius.round()} متر',
        );
      }

      // Step 6: Determine if on time or late
      final isLate = DateTime.now().difference(openedAt).inMinutes > 5;
      final status = isLate ? AttendanceStatus.late : AttendanceStatus.present;

      // Step 7: Write to Firestore (atomic update)
      await _firestore
          .collection('attendanceSessions')
          .doc(qrData['sessionId'] as String)
          .update({
        'records.$studentId': {
          'studentId': studentId,
          'studentNameAr': studentNameAr,
          'status': status.name,
          'markedAt': FieldValue.serverTimestamp(),
          'geofenceVerified': true,
          'qrVerified': true,
          'distanceMeters': geoResult.distance,
        },
      });

      _logger.i('✅ Attendance marked: $studentId — ${status.name}');

      // Fire event bus → Gamification listens
      ref.read(bonyanEventBusProvider).fire(AttendanceMarkedEvent(
        classId: sessionData['classId'] as String? ?? '',
        isPresent: true,
        geofenceVerified: true,
        qrVerified: true,
        timestamp: DateTime.now(),
        sourceUserId: studentId,
      ));

      final result = AttendanceResult.success(
        message: isLate ? 'سُجِّل حضورك متأخرًا ⏰' : 'سُجِّل حضورك بنجاح ✅',
        isLate: isLate,
        distanceMeters: geoResult.distance,
      );

      state = AsyncData(state.valueOrNull?.copyWith(
            isMarking: false,
            lastResult: result,
          ) ?? const AttendanceState());

      return result;
    } catch (e) {
      _logger.e('❌ Attendance error: $e');
      state = AsyncData(state.valueOrNull?.copyWith(isMarking: false) ?? const AttendanceState());
      return _fail(AttendanceFailReason.invalidQr, 'خطأ غير متوقع: $e');
    }
  }

  // ── OPEN SESSION (Teacher side) ───────────────────────────────────────────
  Future<AttendanceSession?> openAttendanceSession({
    required String classId,
    required String teacherId,
    required String subjectNameAr,
    required SchoolLocation schoolLocation,
    int validWindowMinutes = 15,
  }) async {
    final sessionId = _uuid.v4();
    final qrToken   = _uuid.v4(); // One-time token

    final session = AttendanceSession(
      sessionId: sessionId,
      classId: classId,
      teacherId: teacherId,
      subjectNameAr: subjectNameAr,
      openedAt: DateTime.now(),
      validWindowMinutes: validWindowMinutes,
      qrToken: qrToken,
      location: schoolLocation,
    );

    await _firestore.collection('attendanceSessions').doc(sessionId).set({
      'sessionId': sessionId,
      'classId': classId,
      'teacherId': teacherId,
      'subjectNameAr': subjectNameAr,
      'openedAt': FieldValue.serverTimestamp(),
      'validWindowMinutes': validWindowMinutes,
      'qrToken': qrToken,
      'schoolLat': schoolLocation.latitude,
      'schoolLng': schoolLocation.longitude,
      'radiusMeters': schoolLocation.radiusMeters,
      'records': {},
    });

    _logger.i('📋 Session opened: $sessionId for $subjectNameAr');
    return session;
  }

  // ── CLOSE SESSION (Teacher side) ──────────────────────────────────────────
  Future<void> closeSession(String sessionId) async {
    await _firestore.collection('attendanceSessions').doc(sessionId).update({
      'closedAt': FieldValue.serverTimestamp(),
    });
    _logger.i('🔒 Session closed: $sessionId');
  }

  // ── QR PAYLOAD BUILDER (for display on teacher screen) ───────────────────
  String buildQrPayload(AttendanceSession session) {
    return '{"sessionId":"${session.sessionId}","token":"${session.qrToken}",'
        '"exp":${session.openedAt.add(Duration(minutes: session.validWindowMinutes)).millisecondsSinceEpoch}}';
  }

  // ── LIVE SESSION STREAM ───────────────────────────────────────────────────
  Stream<AttendanceSession> watchSession(String sessionId) {
    return _firestore
        .collection('attendanceSessions')
        .doc(sessionId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) throw Exception('session_not_found');
      final d = snap.data()!;
      final records = (d['records'] as Map<String, dynamic>? ?? {}).map(
        (k, v) {
          final vm = v as Map<String, dynamic>;
          return MapEntry(
            k,
            StudentRecord(
              studentId: vm['studentId'] as String,
              studentNameAr: vm['studentNameAr'] as String,
              status: AttendanceStatus.values.firstWhere(
                (s) => s.name == vm['status'],
                orElse: () => AttendanceStatus.absent,
              ),
              markedAt: (vm['markedAt'] as Timestamp?)?.toDate(),
              geofenceVerified: vm['geofenceVerified'] as bool? ?? false,
              qrVerified: vm['qrVerified'] as bool? ?? false,
              distanceMeters: (vm['distanceMeters'] as num?)?.toDouble(),
            ),
          );
        },
      );

      return AttendanceSession(
        sessionId: sessionId,
        classId: d['classId'] as String,
        teacherId: d['teacherId'] as String,
        subjectNameAr: d['subjectNameAr'] as String,
        openedAt: (d['openedAt'] as Timestamp).toDate(),
        closedAt: (d['closedAt'] as Timestamp?)?.toDate(),
        validWindowMinutes: d['validWindowMinutes'] as int,
        qrToken: d['qrToken'] as String,
        location: SchoolLocation(
          schoolId: '',
          latitude: (d['schoolLat'] as num).toDouble(),
          longitude: (d['schoolLng'] as num).toDouble(),
          radiusMeters: (d['radiusMeters'] as num).toDouble(),
          nameAr: '',
        ),
        records: records,
      );
    });
  }

  // ── PRIVATE: Geofence Check ───────────────────────────────────────────────
  Future<_GeofenceResult> _verifyGeofence({
    required double schoolLat,
    required double schoolLng,
    required double radiusMeters,
  }) async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await Geolocator.requestPermission();
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      schoolLat,
      schoolLng,
    );

    state = AsyncData(state.valueOrNull?.copyWith(currentPosition: position) ?? const AttendanceState());

    return _GeofenceResult(
      isInside: distance <= radiusMeters,
      distance: distance,
      requiredRadius: radiusMeters,
    );
  }

  // ── PRIVATE: Parse QR JSON payload ───────────────────────────────────────
  Map<String, dynamic>? _parseQrPayload(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final exp = data['exp'] as int?;
      if (exp != null && DateTime.fromMillisecondsSinceEpoch(exp).isBefore(DateTime.now())) {
        return null; // Expired
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  AttendanceResult _fail(AttendanceFailReason reason, String messageAr) {
    state = AsyncData(state.valueOrNull?.copyWith(isMarking: false) ?? const AttendanceState());
    return AttendanceResult.failed(reasonAr: messageAr, reason: reason);
  }
}

class _GeofenceResult {
  final bool isInside;
  final double distance;
  final double requiredRadius;
  const _GeofenceResult({
    required this.isInside,
    required this.distance,
    required this.requiredRadius,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final smartAttendanceProvider =
    AutoDisposeAsyncNotifierProvider<SmartAttendanceNotifier, AttendanceState>(
  SmartAttendanceNotifier.new,
);

final sessionWatcherProvider =
    StreamProvider.autoDispose.family<AttendanceSession, String>((ref, sessionId) {
  return ref
      .watch(smartAttendanceProvider.notifier)
      .watchSession(sessionId);
});
