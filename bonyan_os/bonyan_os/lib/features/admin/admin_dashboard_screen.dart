// lib/features/admin/admin_dashboard_screen.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║      بنيان OS — لوحة تحكم المشرف                           ║
// ║  Correlation Graph · Live Timetable · Risk Students         ║
// ╚══════════════════════════════════════════════════════════════╝

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/bonyan_theme.dart';
import '../auth/master_auth_provider.dart';
import 'admin_dashboard_provider.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(adminDashboardProvider);
    final profile   = ref.watch(currentProfileProvider);

    // Guard
    if (profile == null || !profile.role.canAccessAdminDashboard) {
      return const Scaffold(
        backgroundColor: BonyanColors.black,
        body: Center(
          child: Text('⛔ غير مصرح', style: TextStyle(fontFamily: 'Cairo', color: BonyanColors.error, fontSize: 20)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: BonyanColors.black,
      body: dashAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: BonyanColors.emerald500)),
        error: (e, _) => Center(
          child: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo', color: BonyanColors.error))),
        data: (dash) => _AdminBody(dash: dash, profile: profile),
      ),
    );
  }
}

class _AdminBody extends ConsumerWidget {
  final AdminDashboardState dash;
  final BonyanUserProfile profile;
  const _AdminBody({required this.dash, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── AppBar ──────────────────────────────────────────────────────
        SliverAppBar(
          pinned: true,
          backgroundColor: BonyanColors.black,
          title: Text(
            'لوحة الإدارة',
            style: const TextStyle(
              fontFamily: 'Cairo', fontSize: 20, fontWeight: FontWeight.w800,
              color: BonyanColors.white,
            ),
          ),
          actions: [
            if (profile.role == BonyanRole.superAdmin)
              Container(
                margin: const EdgeInsets.only(left: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: BonyanColors.purpleAcc.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(BonyanRadius.full),
                  border: Border.all(color: BonyanColors.purpleAcc),
                ),
                child: const Text('مشرف عام',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
                        color: BonyanColors.purpleAcc, fontWeight: FontWeight.w700)),
              ),
          ],
        ),

        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // ── KPI row ────────────────────────────────────────────────
              _KpiRow(dash: dash).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 20),

              // ── Alerts ─────────────────────────────────────────────────
              if (dash.alerts.isNotEmpty) ...[
                _AlertsSection(alerts: dash.alerts).animate().fadeIn(delay: 150.ms),
                const SizedBox(height: 20),
              ],

              // ── Correlation chart ───────────────────────────────────────
              _CorrelationChart(data: dash.correlationData)
                  .animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 20),

              // ── Today's timetable ───────────────────────────────────────
              _TimetableSection(
                slots: dash.todayTimetable,
                notifier: ProviderScope.containerOf(context)
                    .read(adminDashboardProvider.notifier),
                schoolId: profile.schoolId,
              ).animate().fadeIn(delay: 250.ms),
              const SizedBox(height: 20),

              // ── Critical students ───────────────────────────────────────
              _CriticalStudentsSection(students: dash.criticalStudents)
                  .animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 80),
            ]),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI ROW
// ─────────────────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final AdminDashboardState dash;
  const _KpiRow({required this.dash});

  @override
  Widget build(BuildContext context) {
    final kpis = [
      _Kpi('الطلاب', dash.totalStudents.toString(), '👨‍🎓', BonyanColors.info),
      _Kpi('في خطر', dash.atRiskCount.toString(), '⚠️', BonyanColors.warning),
      _Kpi('المعدل', '${dash.schoolAverageGpa.round()}%', '📊', BonyanColors.emerald500),
      _Kpi('الحضور', '${(dash.schoolAttendanceRate * 100).round()}%', '✅', BonyanColors.emerald500),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: kpis.map((k) => _KpiCard(kpi: k)).toList(),
    );
  }
}

class _Kpi {
  final String label, value, icon;
  final Color color;
  const _Kpi(this.label, this.value, this.icon, this.color);
}

class _KpiCard extends StatelessWidget {
  final _Kpi kpi;
  const _KpiCard({required this.kpi});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BonyanColors.surface900,
        borderRadius: BorderRadius.circular(BonyanRadius.md),
        border: Border.all(color: BonyanColors.surface500),
      ),
      child: Row(
        children: [
          Text(kpi.icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(kpi.value,
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 22,
                      fontWeight: FontWeight.w800, color: kpi.color)),
              Text(kpi.label,
                  style: const TextStyle(
                      fontFamily: 'Cairo', fontSize: 11, color: BonyanColors.grey400)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CORRELATION CHART (Spiritual × Academic scatter plot)
// ─────────────────────────────────────────────────────────────────────────────

class _CorrelationChart extends StatelessWidget {
  final List<CorrelationDataPoint> data;
  const _CorrelationChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BonyanColors.surface900,
        borderRadius: BorderRadius.circular(BonyanRadius.lg),
        border: Border.all(color: BonyanColors.surface500),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('📈', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text(
                'الارتباط: الانتظام الروحي × الأداء الأكاديمي',
                style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w700,
                    color: BonyanColors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (data.isNotEmpty)
            Text(
              'كلما ارتفع الانتظام الروحي ارتفع المعدل الأكاديمي',
              style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 11, color: BonyanColors.emerald400),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: data.isEmpty
                ? const Center(child: Text('لا توجد بيانات كافية بعد',
                    style: TextStyle(fontFamily: 'Cairo', color: BonyanColors.grey400)))
                : ScatterChart(
                    ScatterChartData(
                      minX: 0, maxX: 1,
                      minY: 0, maxY: 1,
                      backgroundColor: Colors.transparent,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        getDrawingHorizontalLine: (_) => FlLine(
                            color: BonyanColors.surface500, strokeWidth: 0.5),
                        getDrawingVerticalLine: (_) => FlLine(
                            color: BonyanColors.surface500, strokeWidth: 0.5),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          axisNameWidget: const Text('الانتظام الروحي',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 10,
                                  color: BonyanColors.grey400)),
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, _) => Text('${(v * 100).round()}%',
                                style: const TextStyle(fontSize: 9, color: BonyanColors.grey400)),
                          ),
                        ),
                        leftTitles: AxisTitles(
                          axisNameWidget: const Text('الأداء الأكاديمي',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 10,
                                  color: BonyanColors.grey400)),
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, _) => Text('${(v * 100).round()}%',
                                style: const TextStyle(fontSize: 9, color: BonyanColors.grey400)),
                          ),
                        ),
                      ),
                      scatterSpots: data.map((d) => ScatterSpot(
                        d.spiritualScore,
                        d.academicScore,
                        dotPainter: FlDotCirclePainter(
                          radius: 5,
                          color: switch (d.risk) {
                            RiskLevel.safe     => BonyanColors.emerald500,
                            RiskLevel.watch    => BonyanColors.info,
                            RiskLevel.warning  => BonyanColors.warning,
                            RiskLevel.critical => BonyanColors.error,
                          },
                          strokeColor: Colors.transparent,
                        ),
                      )).toList(),
                    ),
                  ),
          ),
          // Legend
          const SizedBox(height: 8),
          Wrap(
            spacing: 12, runSpacing: 4,
            children: RiskLevel.values.map((r) {
              final color = switch (r) {
                RiskLevel.safe     => BonyanColors.emerald500,
                RiskLevel.watch    => BonyanColors.info,
                RiskLevel.warning  => BonyanColors.warning,
                RiskLevel.critical => BonyanColors.error,
              };
              return Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(
                    shape: BoxShape.circle, color: color)),
                const SizedBox(width: 4),
                Text(r.labelAr, style: const TextStyle(
                    fontFamily: 'Cairo', fontSize: 10, color: BonyanColors.grey400)),
              ]);
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIMETABLE SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _TimetableSection extends StatelessWidget {
  final List<TimetableSlot> slots;
  final AdminDashboardNotifier notifier;
  final String schoolId;

  const _TimetableSection({
    required this.slots, required this.notifier, required this.schoolId});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text('🗓️', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('جدول اليوم',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 15,
                    fontWeight: FontWeight.w700, color: BonyanColors.white)),
          ],
        ),
        const SizedBox(height: 12),
        if (slots.isEmpty)
          const Center(child: Text('لا توجد حصص اليوم',
              style: TextStyle(fontFamily: 'Cairo', color: BonyanColors.grey400)))
        else
          ...slots.map((slot) => _TimetableCard(
                slot: slot,
                onMarkAbsent: () => notifier.markTeacherAbsent(
                  teacherId: slot.teacherId,
                  teacherNameAr: slot.teacherNameAr,
                  schoolId: schoolId,
                ),
              )),
      ],
    );
  }
}

class _TimetableCard extends StatelessWidget {
  final TimetableSlot slot;
  final VoidCallback onMarkAbsent;

  const _TimetableCard({required this.slot, required this.onMarkAbsent});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: slot.isCancelled
            ? const Color(0xFF1A0000)
            : BonyanColors.surface800,
        borderRadius: BorderRadius.circular(BonyanRadius.md),
        border: Border.all(
          color: slot.isCancelled
              ? BonyanColors.error.withOpacity(0.5)
              : BonyanColors.surface500,
        ),
      ),
      child: Row(
        children: [
          // Period number
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: slot.isCancelled
                  ? BonyanColors.error.withOpacity(0.15)
                  : BonyanColors.surface700,
            ),
            child: Center(
              child: Text(
                slot.periodNumber.toString(),
                style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.w700,
                  color: slot.isCancelled ? BonyanColors.error : BonyanColors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.subjectNameAr,
                  style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w700,
                    color: slot.isCancelled ? BonyanColors.error : BonyanColors.white,
                    decoration: slot.isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  '${slot.teacherNameAr} · ${slot.startTime}–${slot.endTime}',
                  style: const TextStyle(
                    fontFamily: 'Cairo', fontSize: 11, color: BonyanColors.grey400),
                ),
                if (slot.isCancelled && slot.cancellationReasonAr != null)
                  Text(
                    '❌ ${slot.cancellationReasonAr}',
                    style: const TextStyle(
                        fontFamily: 'Cairo', fontSize: 11, color: BonyanColors.error),
                  ),
                if (slot.substituteTeacherId != null)
                  const Text('🔄 يوجد معلم بديل',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
                          color: BonyanColors.emerald400)),
              ],
            ),
          ),
          if (!slot.isCancelled)
            IconButton(
              icon: const Icon(Icons.person_off_outlined, color: BonyanColors.warning, size: 20),
              tooltip: 'تسجيل غياب المعلم',
              onPressed: onMarkAbsent,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALERTS SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _AlertsSection extends StatelessWidget {
  final List<SchoolAlert> alerts;
  const _AlertsSection({required this.alerts});

  @override
  Widget build(BuildContext context) {
    final critical = alerts.where((a) => a.severity == AlertSeverity.critical).take(3).toList();
    if (critical.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text('🚨', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('تنبيهات عاجلة', style: TextStyle(
                fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.w700,
                color: BonyanColors.white)),
          ],
        ),
        const SizedBox(height: 10),
        ...critical.map((a) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0800),
            borderRadius: BorderRadius.circular(BonyanRadius.md),
            border: Border.all(color: BonyanColors.error.withOpacity(0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.titleAr, style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w700,
                  color: BonyanColors.error)),
              const SizedBox(height: 4),
              Text(a.bodyAr, style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 12, color: BonyanColors.grey300)),
            ],
          ),
        )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CRITICAL STUDENTS
// ─────────────────────────────────────────────────────────────────────────────

class _CriticalStudentsSection extends StatelessWidget {
  final List<StudentSummary> students;
  const _CriticalStudentsSection({required this.students});

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🔴 طلاب يحتاجون تدخلًا (${students.length})',
          style: const TextStyle(
              fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.w700,
              color: BonyanColors.white),
        ),
        const SizedBox(height: 12),
        ...students.take(5).map((s) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: BonyanColors.surface800,
            borderRadius: BorderRadius.circular(BonyanRadius.md),
            border: Border.all(color: BonyanColors.error.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: BonyanColors.error.withOpacity(0.15),
                child: Text(s.nameAr[0],
                    style: const TextStyle(fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700, color: BonyanColors.error)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.nameAr, style: const TextStyle(
                        fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w700,
                        color: BonyanColors.white)),
                    Row(children: [
                      Text('معدل: ${s.gpa.round()}%',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11,
                              color: BonyanColors.grey400)),
                      const SizedBox(width: 8),
                      Text('حضور: ${(s.attendanceRate * 100).round()}%',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11,
                              color: BonyanColors.grey400)),
                      const SizedBox(width: 8),
                      Text('صلاة: ${(s.prayerConsistency * 100).round()}%',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11,
                              color: BonyanColors.grey400)),
                    ]),
                  ],
                ),
              ),
              Text(s.overallRisk.labelAr,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
            ],
          ),
        )),
      ],
    );
  }
}
