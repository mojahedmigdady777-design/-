// lib/features/prayer/prayer_heatmap_provider.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║      بنيان OS — خريطة حرارة الصلاة والأذكار                ║
// ║  Prayer Tracker · Heatmap · Streak Engine · Azkar Timer     ║
// ╚══════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logger/logger.dart';

import '../../core/network/event_bus.dart';
import '../auth/master_auth_provider.dart';

part 'prayer_heatmap_provider.freezed.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — MODELS
// ─────────────────────────────────────────────────────────────────────────────

const List<String> kPrayers = ['فجر', 'ظهر', 'عصر', 'مغرب', 'عشاء'];
const List<String> kAzkarSets = ['الصباح', 'المساء', 'النوم'];

@freezed
class DailyPrayerRecord with _$DailyPrayerRecord {
  const factory DailyPrayerRecord({
    required String date,         // 'yyyy-MM-dd'
    required Map<String, PrayerEntry> prayers,
    required Map<String, bool> azkar,
    @Default(0) int totalScore,  // 0–100 computed score for heatmap
  }) = _DailyPrayerRecord;

  const DailyPrayerRecord._();

  int get prayersOnTime =>
      prayers.values.where((p) => p.status == PrayerStatus.onTime).length;
  int get prayersCompleted =>
      prayers.values.where((p) => p.status != PrayerStatus.missed).length;
  int get azkarCompleted => azkar.values.where((v) => v).length;
}

@freezed
class PrayerEntry with _$PrayerEntry {
  const factory PrayerEntry({
    required String prayerName,
    required PrayerStatus status,
    DateTime? completedAt,
    @Default(0) int delayMinutes,
  }) = _PrayerEntry;
}

enum PrayerStatus { onTime, late, missed, unknown }

@freezed
class PrayerStreak with _$PrayerStreak {
  const factory PrayerStreak({
    required String prayerName,     // '' = all prayers combined
    required int currentStreak,
    required int longestStreak,
    required DateTime lastCompletedDate,
  }) = _PrayerStreak;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — HEATMAP CELL MODEL
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class HeatmapCell with _$HeatmapCell {
  const factory HeatmapCell({
    required DateTime date,
    required int score,         // 0–100
    required HeatLevel level,
  }) = _HeatmapCell;

  factory HeatmapCell.fromRecord(DailyPrayerRecord r) {
    final d = DateTime.parse(r.date);
    final score = r.totalScore;
    return HeatmapCell(
      date: d,
      score: score,
      level: score == 0
          ? HeatLevel.none
          : score < 30
              ? HeatLevel.low
              : score < 60
                  ? HeatLevel.medium
                  : score < 85
                      ? HeatLevel.high
                      : HeatLevel.perfect,
    );
  }
}

enum HeatLevel { none, low, medium, high, perfect }

extension HeatLevelX on HeatLevel {
  String get labelAr => switch (this) {
        HeatLevel.none    => 'لا يوجد',
        HeatLevel.low     => 'منخفض',
        HeatLevel.medium  => 'متوسط',
        HeatLevel.high    => 'جيد',
        HeatLevel.perfect => 'مثالي ✨',
      };

  // Emerald intensity scale for heatmap
  int get alpha => switch (this) {
        HeatLevel.none    => 20,
        HeatLevel.low     => 80,
        HeatLevel.medium  => 140,
        HeatLevel.high    => 200,
        HeatLevel.perfect => 255,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — PRAYER STATE
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class PrayerState with _$PrayerState {
  const factory PrayerState({
    @Default({}) Map<String, DailyPrayerRecord> records, // keyed by 'yyyy-MM-dd'
    @Default([]) List<HeatmapCell> heatmapCells,
    @Default([]) List<PrayerStreak> streaks,
    DailyPrayerRecord? todayRecord,
    @Default(0.0) double weeklyConsistency,  // 0.0–1.0
    @Default(0.0) double monthlyConsistency,
    @Default(false) bool isLoading,
    @Default(false) bool isSaving,
  }) = _PrayerState;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — PRAYER NOTIFIER
// ─────────────────────────────────────────────────────────────────────────────

class PrayerHeatmapNotifier extends AutoDisposeAsyncNotifier<PrayerState> {
  final _logger = Logger();
  final _firestore = FirebaseFirestore.instance;

  @override
  Future<PrayerState> build() async {
    final profile = ref.watch(currentProfileProvider);
    if (profile == null) return const PrayerState();

    return _loadPrayerData(profile.uid);
  }

  // ── MARK PRAYER ───────────────────────────────────────────────────────────
  Future<void> markPrayer({
    required String prayerName,
    required PrayerStatus status,
    int delayMinutes = 0,
  }) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;

    final today = _todayKey();
    state = AsyncData(state.valueOrNull?.copyWith(isSaving: true) ?? const PrayerState());

    try {
      final entry = PrayerEntry(
        prayerName: prayerName,
        status: status,
        completedAt: DateTime.now(),
        delayMinutes: delayMinutes,
      );

      // Atomic update using merge
      await _firestore
          .collection('students')
          .doc(profile.uid)
          .collection('prayerRecords')
          .doc(today)
          .set({
        'date': today,
        'prayers': {
          prayerName: {
            'prayerName': prayerName,
            'status': status.name,
            'completedAt': FieldValue.serverTimestamp(),
            'delayMinutes': delayMinutes,
          },
        },
      }, SetOptions(merge: true));

      // Update local state
      final current = state.valueOrNull ?? const PrayerState();
      final todayRecord = current.todayRecord ?? DailyPrayerRecord(
        date: today, prayers: {}, azkar: {},
      );
      final updatedRecord = todayRecord.copyWith(
        prayers: {...todayRecord.prayers, prayerName: entry},
      );
      final scored = _scoreRecord(updatedRecord);

      // Update streak
      await _updateStreak(profile.uid, prayerName, status == PrayerStatus.onTime);

      state = AsyncData(current.copyWith(
        isSaving: false,
        todayRecord: scored,
      ));

      _logger.i('🙏 Prayer marked: $prayerName — ${status.name}');

      // Fire event bus
      final bus = ref.read(bonyanEventBusProvider);
      if (status != PrayerStatus.missed) {
        bus.fire(PrayerCheckedInEvent(
          prayerName: prayerName,
          isOnTime: status == PrayerStatus.onTime,
          streakDays: await _getStreak(profile.uid, prayerName),
          timestamp: DateTime.now(),
          sourceUserId: profile.uid,
        ));
      } else {
        final consecutive = await _getConsecutiveMisses(profile.uid, prayerName);
        bus.fire(PrayerMissedEvent(
          prayerName: prayerName,
          consecutiveMisses: consecutive,
          timestamp: DateTime.now(),
          sourceUserId: profile.uid,
        ));
      }
    } catch (e) {
      _logger.e('❌ Prayer mark error: $e');
      state = AsyncData(state.valueOrNull?.copyWith(isSaving: false) ?? const PrayerState());
    }
  }

  // ── MARK AZKAR ────────────────────────────────────────────────────────────
  Future<void> markAzkarCompleted({
    required String azkarSet,     // 'الصباح' | 'المساء' | 'النوم'
    required int durationSeconds,
  }) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;

    final today = _todayKey();

    await _firestore
        .collection('students')
        .doc(profile.uid)
        .collection('prayerRecords')
        .doc(today)
        .set({
      'azkar': {azkarSet: true},
    }, SetOptions(merge: true));

    final current = state.valueOrNull ?? const PrayerState();
    final todayRecord = current.todayRecord ?? DailyPrayerRecord(
      date: today, prayers: {}, azkar: {},
    );
    final updated = todayRecord.copyWith(
      azkar: {...todayRecord.azkar, azkarSet: true},
    );

    state = AsyncData(current.copyWith(todayRecord: _scoreRecord(updated)));

    ref.read(bonyanEventBusProvider).fire(AzkarCompletedEvent(
      azkarSet: azkarSet,
      durationSeconds: durationSeconds,
      timestamp: DateTime.now(),
      sourceUserId: profile.uid,
    ));

    _logger.i('📿 Azkar completed: $azkarSet (${durationSeconds}s)');
  }

  // ── LOAD 90-DAY HISTORY (for heatmap) ────────────────────────────────────
  Future<PrayerState> _loadPrayerData(String uid) async {
    final nineDaysAgo = DateTime.now().subtract(const Duration(days: 90));
    final fromKey = _dateKey(nineDaysAgo);

    final snap = await _firestore
        .collection('students')
        .doc(uid)
        .collection('prayerRecords')
        .where('date', isGreaterThanOrEqualTo: fromKey)
        .orderBy('date', descending: false)
        .get();

    final records = <String, DailyPrayerRecord>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final prayersRaw = data['prayers'] as Map<String, dynamic>? ?? {};
      final azkarRaw   = data['azkar']   as Map<String, dynamic>? ?? {};

      final prayers = prayersRaw.map((k, v) {
        final vm = v as Map<String, dynamic>;
        return MapEntry(k, PrayerEntry(
          prayerName: vm['prayerName'] as String,
          status: PrayerStatus.values.firstWhere(
            (s) => s.name == vm['status'],
            orElse: () => PrayerStatus.unknown,
          ),
          completedAt: (vm['completedAt'] as Timestamp?)?.toDate(),
          delayMinutes: vm['delayMinutes'] as int? ?? 0,
        ));
      });

      final azkar = azkarRaw.map((k, v) => MapEntry(k, v as bool));
      final rec = _scoreRecord(DailyPrayerRecord(
        date: doc.id,
        prayers: prayers,
        azkar: azkar,
      ));
      records[doc.id] = rec;
    }

    final heatmap = records.values.map(HeatmapCell.fromRecord).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final todayKey = _todayKey();
    final todayRecord = records[todayKey];

    final weeklyConsistency = _calcConsistency(records, 7);
    final monthlyConsistency = _calcConsistency(records, 30);

    return PrayerState(
      records: records,
      heatmapCells: heatmap,
      todayRecord: todayRecord,
      weeklyConsistency: weeklyConsistency,
      monthlyConsistency: monthlyConsistency,
    );
  }

  // ── SCORING ALGORITHM ─────────────────────────────────────────────────────
  // Weights: 5 prayers × 14pts each = 70pts max
  //          3 azkar sets × 10pts each = 30pts max
  //          Total = 100pts
  DailyPrayerRecord _scoreRecord(DailyPrayerRecord record) {
    int score = 0;
    for (final p in kPrayers) {
      final entry = record.prayers[p];
      score += switch (entry?.status) {
        PrayerStatus.onTime => 14,
        PrayerStatus.late   => 8,
        PrayerStatus.missed => 0,
        _                   => 0,
      };
    }
    for (final az in kAzkarSets) {
      if (record.azkar[az] == true) score += 10;
    }
    return record.copyWith(totalScore: score.clamp(0, 100));
  }

  double _calcConsistency(Map<String, DailyPrayerRecord> records, int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final relevant = records.values
        .where((r) => DateTime.parse(r.date).isAfter(cutoff))
        .toList();
    if (relevant.isEmpty) return 0;
    final avg = relevant.map((r) => r.totalScore).reduce((a, b) => a + b) / relevant.length;
    return (avg / 100).clamp(0.0, 1.0);
  }

  Future<void> _updateStreak(String uid, String prayer, bool isOnTime) async {
    final streakRef = _firestore
        .collection('students')
        .doc(uid)
        .collection('streaks')
        .doc('prayer_$prayer');

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(streakRef);
      final current = snap.data()?['count'] as int? ?? 0;
      final longest = snap.data()?['longest'] as int? ?? 0;
      final newStreak = isOnTime ? current + 1 : 0;
      tx.set(streakRef, {
        'count': newStreak,
        'longest': newStreak > longest ? newStreak : longest,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<int> _getStreak(String uid, String prayer) async {
    final doc = await _firestore
        .collection('students')
        .doc(uid)
        .collection('streaks')
        .doc('prayer_$prayer')
        .get();
    return doc.data()?['count'] as int? ?? 0;
  }

  Future<int> _getConsecutiveMisses(String uid, String prayer) async {
    final snap = await _firestore
        .collection('students')
        .doc(uid)
        .collection('prayerRecords')
        .orderBy('date', descending: true)
        .limit(7)
        .get();

    int count = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      final prayerData = (data['prayers'] as Map<String, dynamic>?)?[prayer]
          as Map<String, dynamic>?;
      if (prayerData?['status'] == PrayerStatus.missed.name) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  String _todayKey() => _dateKey(DateTime.now());
  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 5 — PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final prayerHeatmapProvider =
    AutoDisposeAsyncNotifierProvider<PrayerHeatmapNotifier, PrayerState>(
  PrayerHeatmapNotifier.new,
);

final todayPrayerRecordProvider = Provider.autoDispose<DailyPrayerRecord?>(
  (ref) => ref.watch(prayerHeatmapProvider).valueOrNull?.todayRecord,
);

final heatmapCellsProvider = Provider.autoDispose<List<HeatmapCell>>(
  (ref) => ref.watch(prayerHeatmapProvider).valueOrNull?.heatmapCells ?? [],
);

final weeklyConsistencyProvider = Provider.autoDispose<double>(
  (ref) => ref.watch(prayerHeatmapProvider).valueOrNull?.weeklyConsistency ?? 0,
);

final monthlyConsistencyProvider = Provider.autoDispose<double>(
  (ref) => ref.watch(prayerHeatmapProvider).valueOrNull?.monthlyConsistency ?? 0,
);
