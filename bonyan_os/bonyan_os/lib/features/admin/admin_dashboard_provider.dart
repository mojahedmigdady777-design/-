// lib/features/admin/admin_dashboard_provider.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║      بنيان OS — لوحة الإدارة الذكية                        ║
// ║  OpenEMIS-style · Correlation Analytics · Dynamic Schedule  ║
// ╚══════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logger/logger.dart';

import '../../core/network/event_bus.dart';
import '../auth/master_auth_provider.dart';
import '../prayer/prayer_heatmap_provider.dart';

part 'admin_dashboard_provider.freezed.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — MODELS
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class StudentSummary with _$StudentSummary {
  const factory StudentSummary({
    required String studentId,
    required String nameAr,
    required String classId,
    required String cellId,
    required double gpa,              // 0–100
    required double attendanceRate,   // 0.0–1.0
    required double prayerConsistency, // 0.0–1.0
    required double azkarConsistency,  // 0.0–1.0
    required int coinBalance,
    required List<String> atRiskSubjects,
    required RiskLevel overallRisk,
    DateTime? lastActiveAt,
  }) = _StudentSummary;

  const StudentSummary._();

  double get spiritualScore => (prayerConsistency * 0.7 + azkarConsistency * 0.3);
  double get academicScore  => (gpa / 100 * 0.6 + attendanceRate * 0.4);
}

enum RiskLevel { safe, watch, warning, critical }

extension RiskLevelX on RiskLevel {
  String get labelAr => switch (this) {
        RiskLevel.safe     => '🟢 مستقر',
        RiskLevel.watch    => '🔵 متابعة',
        RiskLevel.warning  => '🟡 تحذير',
        RiskLevel.critical => '🔴 حرج',
      };
}

@freezed
class CorrelationDataPoint with _$CorrelationDataPoint {
  const factory CorrelationDataPoint({
    required double spiritualScore,  // X axis (0.0–1.0)
    required double academicScore,   // Y axis (0.0–1.0)
    required String studentId,
    required String nameAr,
    required RiskLevel risk,
  }) = _CorrelationDataPoint;
}

@freezed
class TimetableSlot with _$TimetableSlot {
  const factory TimetableSlot({
    required String slotId,
    required String classId,
    required String subjectId,
    required String subjectNameAr,
    required String teacherId,
    required String teacherNameAr,
    required int dayOfWeek,      // 0=Sun ... 5=Fri
    required int periodNumber,   // 1–8
    required String startTime,   // HH:mm
    required String endTime,
    @Default(false) bool isCancelled,
    String? substituteTeacherId,
    String? cancellationReasonAr,
    String? roomNumber,
  }) = _TimetableSlot;
}

@freezed
class SchoolAlert with _$SchoolAlert {
  const factory SchoolAlert({
    required String alertId,
    required AlertType type,
    required String titleAr,
    required String bodyAr,
    required AlertSeverity severity,
    required DateTime createdAt,
    required List<String> targetRoles, // ['student','parent','teacher']
    @Default(false) bool isRead,
    String? relatedStudentId,
    String? relatedClassId,
  }) = _SchoolAlert;
}

enum AlertType {
  teacherAbsent,
  gradeDropCritical,
  attendanceAlert,
  behaviorConcern,
  systemUpdate,
  celebration,
}

enum AlertSeverity { info, warning, critical }

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — ADMIN DASHBOARD STATE
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class AdminDashboardState with _$AdminDashboardState {
  const factory AdminDashboardState({
    @Default([]) List<StudentSummary> students,
    @Default([]) List<CorrelationDataPoint> correlationData,
    @Default([]) List<TimetableSlot> todayTimetable,
    @Default([]) List<SchoolAlert> alerts,
    @Default(0) int totalStudents,
    @Default(0) int atRiskCount,
    @Default(0.0) double schoolAverageGpa,
    @Default(0.0) double schoolAttendanceRate,
    @Default(0.0) double schoolPrayerConsistency,
    @Default(false) bool isLoading,
    @Default(false) bool isUpdatingSchedule,
    String? selectedClassId,
    String? errorAr,
  }) = _AdminDashboardState;

  const AdminDashboardState._();

  List<StudentSummary> get criticalStudents =>
      students.where((s) => s.overallRisk == RiskLevel.critical).toList();

  double get correlationCoefficient {
    if (correlationData.length < 2) return 0;
    // Pearson correlation between spiritual and academic scores
    final n = correlationData.length.toDouble();
    final sumX = correlationData.map((d) => d.spiritualScore).reduce((a, b) => a + b);
    final sumY = correlationData.map((d) => d.academicScore).reduce((a, b) => a + b);
    final sumXY = correlationData.map((d) => d.spiritualScore * d.academicScore).reduce((a, b) => a + b);
    final sumX2 = correlationData.map((d) => d.spiritualScore * d.spiritualScore).reduce((a, b) => a + b);
    final sumY2 = correlationData.map((d) => d.academicScore * d.academicScore).reduce((a, b) => a + b);
    final num = sumXY - (sumX * sumY / n);
    final den = ((sumX2 - sumX * sumX / n) * (sumY2 - sumY * sumY / n));
    if (den <= 0) return 0;
    return (num / (den.abs() > 0 ? (den.abs() * den.abs() > 0 ? den.abs() : 1) : 1))
        .clamp(-1.0, 1.0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — ADMIN NOTIFIER
// ─────────────────────────────────────────────────────────────────────────────

class AdminDashboardNotifier
    extends AutoDisposeAsyncNotifier<AdminDashboardState> {
  final _logger = Logger();
  final _firestore = FirebaseFirestore.instance;

  @override
  Future<AdminDashboardState> build() async {
    final profile = ref.watch(currentProfileProvider);

    // Guard: only admin+ can use this
    if (profile == null || !profile.role.canAccessAdminDashboard) {
      return const AdminDashboardState(errorAr: 'غير مصرح لك بالوصول إلى لوحة الإدارة');
    }

    // Wire event bus for live updates
    final bus = ref.watch(bonyanEventBusProvider);
    final sub1 = bus.on<GradeDropDetectedEvent>(_onGradeAlert);
    final sub2 = bus.on<AttendanceMarkedEvent>(_onAttendanceUpdate);
    ref.onDispose(() {
      sub1.cancel();
      sub2.cancel();
    });

    return _loadDashboardData(profile.schoolId);
  }

  // ── LOAD ALL DASHBOARD DATA ───────────────────────────────────────────────
  Future<AdminDashboardState> _loadDashboardData(String schoolId) async {
    final [students, timetable, alerts] = await Future.wait([
      _loadStudents(schoolId),
      _loadTodayTimetable(schoolId),
      _loadAlerts(schoolId),
    ]);

    final studentList  = students  as List<StudentSummary>;
    final slots        = timetable as List<TimetableSlot>;
    final alertList    = alerts    as List<SchoolAlert>;

    final correlation = studentList.map((s) => CorrelationDataPoint(
      spiritualScore: s.spiritualScore,
      academicScore: s.academicScore,
      studentId: s.studentId,
      nameAr: s.nameAr,
      risk: s.overallRisk,
    )).toList();

    final avgGpa = studentList.isEmpty ? 0.0
        : studentList.map((s) => s.gpa).reduce((a, b) => a + b) / studentList.length;
    final avgAttendance = studentList.isEmpty ? 0.0
        : studentList.map((s) => s.attendanceRate).reduce((a, b) => a + b) / studentList.length;
    final avgPrayer = studentList.isEmpty ? 0.0
        : studentList.map((s) => s.prayerConsistency).reduce((a, b) => a + b) / studentList.length;

    return AdminDashboardState(
      students: studentList,
      correlationData: correlation,
      todayTimetable: slots,
      alerts: alertList,
      totalStudents: studentList.length,
      atRiskCount: studentList.where((s) => s.overallRisk != RiskLevel.safe).length,
      schoolAverageGpa: avgGpa,
      schoolAttendanceRate: avgAttendance,
      schoolPrayerConsistency: avgPrayer,
    );
  }

  // ── DYNAMIC SCHEDULE: TEACHER ABSENT ─────────────────────────────────────
  Future<void> markTeacherAbsent({
    required String teacherId,
    required String teacherNameAr,
    required String schoolId,
    String? reasonAr,
  }) async {
    state = AsyncData(state.valueOrNull?.copyWith(isUpdatingSchedule: true)
        ?? const AdminDashboardState());

    try {
      final today = DateTime.now().weekday; // 1=Mon...7=Sun
      // Find all slots for this teacher today
      final affectedSlots = state.valueOrNull?.todayTimetable
          .where((s) => s.teacherId == teacherId && s.dayOfWeek == today)
          .toList() ?? [];

      // Mark all affected slots as cancelled in Firestore
      final batch = _firestore.batch();
      for (final slot in affectedSlots) {
        final ref = _firestore.collection('timetable').doc(slot.slotId);
        batch.update(ref, {
          'isCancelled': true,
          'cancellationReasonAr': reasonAr ?? 'غياب المعلم',
        });
      }
      await batch.commit();

      // Create school-wide alert
      await _createAlert(
        schoolId: schoolId,
        type: AlertType.teacherAbsent,
        titleAr: 'تغيير في الجدول الدراسي',
        bodyAr: 'المعلم/ة $teacherNameAr غائب/ة اليوم. '
            'تم إلغاء ${affectedSlots.length} حصص. '
            'ستصلكم تفاصيل الجدول البديل.',
        severity: AlertSeverity.warning,
        targetRoles: ['student', 'parent'],
      );

      // Update local state
      state = AsyncData(state.valueOrNull?.copyWith(
            isUpdatingSchedule: false,
            todayTimetable: state.valueOrNull!.todayTimetable.map((s) {
              if (s.teacherId == teacherId) {
                return s.copyWith(
                    isCancelled: true,
                    cancellationReasonAr: reasonAr ?? 'غياب المعلم');
              }
              return s;
            }).toList(),
          ) ?? const AdminDashboardState());

      _logger.w('📅 Teacher $teacherId marked absent — ${affectedSlots.length} slots cancelled');
    } catch (e) {
      state = AsyncData(state.valueOrNull?.copyWith(
            isUpdatingSchedule: false,
            errorAr: 'فشل تحديث الجدول: $e',
          ) ?? const AdminDashboardState());
    }
  }

  // ── ASSIGN SUBSTITUTE TEACHER ─────────────────────────────────────────────
  Future<void> assignSubstitute({
    required String slotId,
    required String substituteTeacherId,
    required String substituteNameAr,
  }) async {
    await _firestore.collection('timetable').doc(slotId).update({
      'substituteTeacherId': substituteTeacherId,
      'isCancelled': false,
    });

    state = AsyncData(state.valueOrNull?.copyWith(
          todayTimetable: state.valueOrNull!.todayTimetable.map((s) {
            if (s.slotId == slotId) {
              return s.copyWith(
                substituteTeacherId: substituteTeacherId,
                isCancelled: false,
              );
            }
            return s;
          }).toList(),
        ) ?? const AdminDashboardState());

    _logger.i('✅ Substitute $substituteNameAr assigned to slot $slotId');
  }

  // ── FILTER BY CLASS ───────────────────────────────────────────────────────
  void filterByClass(String? classId) {
    state = AsyncData(state.valueOrNull?.copyWith(selectedClassId: classId)
        ?? const AdminDashboardState());
  }

  // ── LIVE TIMETABLE STREAM ─────────────────────────────────────────────────
  Stream<List<TimetableSlot>> watchTodayTimetable(String schoolId) {
    final today = DateTime.now().weekday;
    return _firestore
        .collection('timetable')
        .where('schoolId', isEqualTo: schoolId)
        .where('dayOfWeek', isEqualTo: today)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final d = doc.data();
              return TimetableSlot(
                slotId: doc.id,
                classId: d['classId'] as String,
                subjectId: d['subjectId'] as String,
                subjectNameAr: d['subjectNameAr'] as String,
                teacherId: d['teacherId'] as String,
                teacherNameAr: d['teacherNameAr'] as String,
                dayOfWeek: d['dayOfWeek'] as int,
                periodNumber: d['periodNumber'] as int,
                startTime: d['startTime'] as String,
                endTime: d['endTime'] as String,
                isCancelled: d['isCancelled'] as bool? ?? false,
                substituteTeacherId: d['substituteTeacherId'] as String?,
                cancellationReasonAr: d['cancellationReasonAr'] as String?,
                roomNumber: d['roomNumber'] as String?,
              );
            }).toList());
  }

  // ── LOAD STUDENTS ─────────────────────────────────────────────────────────
  Future<List<StudentSummary>> _loadStudents(String schoolId) async {
    final snap = await _firestore
        .collection('students')
        .where('schoolId', isEqualTo: schoolId)
        .where('role', isEqualTo: 'student')
        .get();

    return snap.docs.map((doc) {
      final d = doc.data();
      final gpa = (d['gpa'] as num? ?? 0).toDouble();
      final attendance = (d['attendanceRate'] as num? ?? 0).toDouble();
      final prayer = (d['prayerConsistency'] as num? ?? 0).toDouble();
      final azkar  = (d['azkarConsistency']  as num? ?? 0).toDouble();

      // Risk calculation
      final risk = switch (true) {
        _ when gpa < 50 || prayer < 0.3 => RiskLevel.critical,
        _ when gpa < 65 || prayer < 0.5 => RiskLevel.warning,
        _ when gpa < 75 || attendance < 0.8 => RiskLevel.watch,
        _ => RiskLevel.safe,
      };

      return StudentSummary(
        studentId: doc.id,
        nameAr: d['displayName'] as String? ?? 'طالب',
        classId: d['classId'] as String? ?? '',
        cellId: d['cellId'] as String? ?? '',
        gpa: gpa,
        attendanceRate: attendance,
        prayerConsistency: prayer,
        azkarConsistency: azkar,
        coinBalance: d['coinBalance'] as int? ?? 0,
        atRiskSubjects: List<String>.from(d['atRiskSubjects'] as List? ?? []),
        overallRisk: risk,
        lastActiveAt: (d['lastActiveAt'] as Timestamp?)?.toDate(),
      );
    }).toList();
  }

  Future<List<TimetableSlot>> _loadTodayTimetable(String schoolId) async {
    final today = DateTime.now().weekday;
    final snap = await _firestore
        .collection('timetable')
        .where('schoolId', isEqualTo: schoolId)
        .where('dayOfWeek', isEqualTo: today)
        .orderBy('periodNumber')
        .get();

    return snap.docs.map((doc) {
      final d = doc.data();
      return TimetableSlot(
        slotId: doc.id,
        classId: d['classId'] as String,
        subjectId: d['subjectId'] as String? ?? '',
        subjectNameAr: d['subjectNameAr'] as String,
        teacherId: d['teacherId'] as String,
        teacherNameAr: d['teacherNameAr'] as String,
        dayOfWeek: today,
        periodNumber: d['periodNumber'] as int,
        startTime: d['startTime'] as String,
        endTime: d['endTime'] as String,
        isCancelled: d['isCancelled'] as bool? ?? false,
        substituteTeacherId: d['substituteTeacherId'] as String?,
        roomNumber: d['roomNumber'] as String?,
      );
    }).toList();
  }

  Future<List<SchoolAlert>> _loadAlerts(String schoolId) async {
    final snap = await _firestore
        .collection('schoolAlerts')
        .where('schoolId', isEqualTo: schoolId)
        .where('createdAt',
            isGreaterThan: Timestamp.fromDate(
                DateTime.now().subtract(const Duration(days: 7))))
        .orderBy('createdAt', descending: true)
        .limit(30)
        .get();

    return snap.docs.map((doc) {
      final d = doc.data();
      return SchoolAlert(
        alertId: doc.id,
        type: AlertType.values.firstWhere(
          (t) => t.name == d['type'],
          orElse: () => AlertType.systemUpdate,
        ),
        titleAr: d['titleAr'] as String,
        bodyAr: d['bodyAr'] as String,
        severity: AlertSeverity.values.firstWhere(
          (s) => s.name == d['severity'],
          orElse: () => AlertSeverity.info,
        ),
        createdAt: (d['createdAt'] as Timestamp).toDate(),
        targetRoles: List<String>.from(d['targetRoles'] as List? ?? []),
        isRead: d['isRead'] as bool? ?? false,
        relatedStudentId: d['relatedStudentId'] as String?,
        relatedClassId: d['relatedClassId'] as String?,
      );
    }).toList();
  }

  Future<void> _createAlert({
    required String schoolId,
    required AlertType type,
    required String titleAr,
    required String bodyAr,
    required AlertSeverity severity,
    required List<String> targetRoles,
    String? relatedStudentId,
    String? relatedClassId,
  }) async {
    final ref = _firestore.collection('schoolAlerts').doc();
    await ref.set({
      'schoolId': schoolId,
      'type': type.name,
      'titleAr': titleAr,
      'bodyAr': bodyAr,
      'severity': severity.name,
      'targetRoles': targetRoles,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
      if (relatedStudentId != null) 'relatedStudentId': relatedStudentId,
      if (relatedClassId != null) 'relatedClassId': relatedClassId,
    });
  }

  // ── EVENT BUS REACTIONS ───────────────────────────────────────────────────
  Future<void> _onGradeAlert(GradeDropDetectedEvent event) async {
    if (event.dropPercentage < 20) return;
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;

    await _createAlert(
      schoolId: profile.schoolId,
      type: AlertType.gradeDropCritical,
      titleAr: 'تراجع حاد في ${event.subjectName}',
      bodyAr: 'تراجع الطالب ${event.dropPercentage.round()}% في ${event.subjectName}. '
          'يُنصح بالتدخل المبكر.',
      severity: AlertSeverity.critical,
      targetRoles: ['teacher', 'admin'],
      relatedStudentId: event.sourceUserId,
    );
  }

  Future<void> _onAttendanceUpdate(AttendanceMarkedEvent event) async {
    // Update live attendance stats in state
    _logger.d('📊 Admin: attendance update received for class ${event.classId}');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final adminDashboardProvider =
    AutoDisposeAsyncNotifierProvider<AdminDashboardNotifier, AdminDashboardState>(
  AdminDashboardNotifier.new,
);

final criticalStudentsProvider = Provider.autoDispose<List<StudentSummary>>(
  (ref) => ref.watch(adminDashboardProvider).valueOrNull?.criticalStudents ?? [],
);

final correlationDataProvider = Provider.autoDispose<List<CorrelationDataPoint>>(
  (ref) => ref.watch(adminDashboardProvider).valueOrNull?.correlationData ?? [],
);

final liveScheduleProvider =
    StreamProvider.autoDispose.family<List<TimetableSlot>, String>(
  (ref, schoolId) =>
      ref.watch(adminDashboardProvider.notifier).watchTodayTimetable(schoolId),
);

final alertsProvider =
    Provider.autoDispose.family<List<SchoolAlert>, AlertSeverity?>((ref, severity) {
  final alerts = ref.watch(adminDashboardProvider).valueOrNull?.alerts ?? [];
  if (severity == null) return alerts;
  return alerts.where((a) => a.severity == severity).toList();
});
