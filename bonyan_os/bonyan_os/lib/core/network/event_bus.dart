// lib/core/network/event_bus.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║         بنيان OS — المحور المركزي للأحداث                    ║
// ║  Central Event Bus: Cross-Feature Reactive Communication      ║
// ╚══════════════════════════════════════════════════════════════╝
//
// Every domain fires typed events here. Riverpod Listeners in each
// feature subscribe and react — keeping modules decoupled but fully
// interconnected. This replaces spaghetti direct calls between features.

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — BASE EVENT
// ─────────────────────────────────────────────────────────────────────────────

abstract class BonyanEvent {
  final DateTime timestamp;
  final String? sourceUserId;

  const BonyanEvent({
    required this.timestamp,
    this.sourceUserId,
  });

  @override
  String toString() =>
      '[${runtimeType}] at $timestamp from ${sourceUserId ?? "system"}';
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — PRAYER & SPIRITUALITY EVENTS
// ─────────────────────────────────────────────────────────────────────────────

class PrayerCheckedInEvent extends BonyanEvent {
  final String prayerName;   // e.g. "فجر", "ظهر"
  final bool isOnTime;
  final int streakDays;

  const PrayerCheckedInEvent({
    required this.prayerName,
    required this.isOnTime,
    required this.streakDays,
    required super.timestamp,
    super.sourceUserId,
  });
}

class PrayerMissedEvent extends BonyanEvent {
  final String prayerName;
  final int consecutiveMisses;

  const PrayerMissedEvent({
    required this.prayerName,
    required this.consecutiveMisses,
    required super.timestamp,
    super.sourceUserId,
  });
}

class AzkarCompletedEvent extends BonyanEvent {
  final String azkarSet;     // "صباح" | "مساء" | "نوم"
  final int durationSeconds;

  const AzkarCompletedEvent({
    required this.azkarSet,
    required this.durationSeconds,
    required super.timestamp,
    super.sourceUserId,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — ACADEMIC EVENTS
// ─────────────────────────────────────────────────────────────────────────────

class GradeDropDetectedEvent extends BonyanEvent {
  final String subjectId;
  final String subjectName;
  final double previousGrade;
  final double currentGrade;
  final double dropPercentage;

  const GradeDropDetectedEvent({
    required this.subjectId,
    required this.subjectName,
    required this.previousGrade,
    required this.currentGrade,
    required this.dropPercentage,
    required super.timestamp,
    super.sourceUserId,
  });
}

class StudySessionCompletedEvent extends BonyanEvent {
  final String subjectId;
  final int durationMinutes;
  final bool wasAiAssisted;
  final int focusScore; // 0–100

  const StudySessionCompletedEvent({
    required this.subjectId,
    required this.durationMinutes,
    required this.wasAiAssisted,
    required this.focusScore,
    required super.timestamp,
    super.sourceUserId,
  });
}

class AttendanceMarkedEvent extends BonyanEvent {
  final String classId;
  final bool isPresent;
  final bool geofenceVerified;
  final bool qrVerified;

  const AttendanceMarkedEvent({
    required this.classId,
    required this.isPresent,
    required this.geofenceVerified,
    required this.qrVerified,
    required super.timestamp,
    super.sourceUserId,
  });
}

class RescuePlanGeneratedEvent extends BonyanEvent {
  final String planId;
  final String subjectId;
  final int recommendedDailyMinutes;
  final List<String> topicIds;

  const RescuePlanGeneratedEvent({
    required this.planId,
    required this.subjectId,
    required this.recommendedDailyMinutes,
    required this.topicIds,
    required super.timestamp,
    super.sourceUserId,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — GAMIFICATION & ECONOMY EVENTS
// ─────────────────────────────────────────────────────────────────────────────

enum CoinSource {
  earlyArrival,
  azkarComplete,
  prayerOnTime,
  peerHelp,
  quizWin,
  studyStreak,
  cellGroupBonus,
  adminGrant,
}

class BonyanCoinEarnedEvent extends BonyanEvent {
  final int amount;
  final CoinSource source;
  final String? reason; // Arabic display label

  const BonyanCoinEarnedEvent({
    required this.amount,
    required this.source,
    this.reason,
    required super.timestamp,
    super.sourceUserId,
  });
}

class BadgeEarnedEvent extends BonyanEvent {
  final String badgeId;
  final String badgeNameAr;
  final String iconPath;
  final BadgeTier tier;

  const BadgeEarnedEvent({
    required this.badgeId,
    required this.badgeNameAr,
    required this.iconPath,
    required this.tier,
    required super.timestamp,
    super.sourceUserId,
  });
}

class BadgeDegradedEvent extends BonyanEvent {
  final String badgeId;
  final String badgeNameAr;
  final int missedDays;
  final bool isRevoked; // false = warning, true = removed

  const BadgeDegradedEvent({
    required this.badgeId,
    required this.badgeNameAr,
    required this.missedDays,
    required this.isRevoked,
    required super.timestamp,
    super.sourceUserId,
  });
}

class LeaderboardUpdatedEvent extends BonyanEvent {
  final String cellId;
  final int newRank;
  final double collectiveScore;

  const LeaderboardUpdatedEvent({
    required this.cellId,
    required this.newRank,
    required this.collectiveScore,
    required super.timestamp,
    super.sourceUserId,
  });
}

enum BadgeTier { bronze, silver, gold, diamond, legendary }

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 5 — CELL-OF-5 ALARM & SOCIAL EVENTS
// ─────────────────────────────────────────────────────────────────────────────

enum AlarmType { fajr, study, group, emergency }
enum CellAlarmStatus { pending, checkedIn, missed, cascading }

class CellAlarmTriggeredEvent extends BonyanEvent {
  final String cellId;
  final AlarmType alarmType;
  final String alarmLabel;       // Arabic label e.g. "صلاة الفجر"
  final List<String> memberIds;

  const CellAlarmTriggeredEvent({
    required this.cellId,
    required this.alarmType,
    required this.alarmLabel,
    required this.memberIds,
    required super.timestamp,
    super.sourceUserId,
  });
}

class MemberMissedAlarmEvent extends BonyanEvent {
  final String cellId;
  final String missedByUserId;
  final AlarmType alarmType;
  final List<String> remainingMemberIds; // who will be notified

  const MemberMissedAlarmEvent({
    required this.cellId,
    required this.missedByUserId,
    required this.alarmType,
    required this.remainingMemberIds,
    required super.timestamp,
    super.sourceUserId,
  });
}

class MemberCheckedInEvent extends BonyanEvent {
  final String cellId;
  final AlarmType alarmType;
  final int checkInDelaySeconds; // 0 = on time

  const MemberCheckedInEvent({
    required this.cellId,
    required this.alarmType,
    required this.checkInDelaySeconds,
    required super.timestamp,
    super.sourceUserId,
  });
}

class VoipCallInitiatedEvent extends BonyanEvent {
  final String cellId;
  final String targetUserId;
  final String channelId; // Agora channel

  const VoipCallInitiatedEvent({
    required this.cellId,
    required this.targetUserId,
    required this.channelId,
    required super.timestamp,
    super.sourceUserId,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 6 — MUEEN AI EVENTS
// ─────────────────────────────────────────────────────────────────────────────

enum MueenTrigger {
  gradeDropDetected,
  spiritualStreakLow,
  prayerMissedRepeatedly,
  studyPlanGenerated,
  quizReady,
  lectureTranscribed,
  parentAlert,
}

class MueenMessageReadyEvent extends BonyanEvent {
  final String messageId;
  final MueenTrigger trigger;
  final String messageAr;         // The actual Arabic message
  final String? deepLinkRoute;    // Optional navigation target
  final bool requiresAck;         // Does student need to confirm reading?

  const MueenMessageReadyEvent({
    required this.messageId,
    required this.trigger,
    required this.messageAr,
    this.deepLinkRoute,
    required this.requiresAck,
    required super.timestamp,
    super.sourceUserId,
  });
}

class LectureTranscribedEvent extends BonyanEvent {
  final String transcriptId;
  final String subjectId;
  final String summaryAr;
  final List<String> quizQuestionIds;

  const LectureTranscribedEvent({
    required this.transcriptId,
    required this.subjectId,
    required this.summaryAr,
    required this.quizQuestionIds,
    required super.timestamp,
    super.sourceUserId,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 7 — THE BUS ITSELF
// ─────────────────────────────────────────────────────────────────────────────

class BonyanEventBus {
  static final BonyanEventBus _instance = BonyanEventBus._internal();
  factory BonyanEventBus() => _instance;
  BonyanEventBus._internal();

  final _logger = Logger(
    printer: PrettyPrinter(methodCount: 0, noBoxingByDefault: true),
  );

  // Single broadcast stream for all events
  final StreamController<BonyanEvent> _controller =
      StreamController<BonyanEvent>.broadcast();

  Stream<BonyanEvent> get stream => _controller.stream;

  /// Emit any [BonyanEvent] to all subscribers.
  void fire(BonyanEvent event) {
    if (_controller.isClosed) return;
    _logger.d('🔥 EventBus → ${event.toString()}');
    _controller.add(event);
  }

  /// Subscribe to a specific event type [T].
  /// Returns a [StreamSubscription] — caller must cancel on dispose.
  StreamSubscription<T> on<T extends BonyanEvent>(
    void Function(T event) handler,
  ) {
    return stream.where((e) => e is T).cast<T>().listen(handler);
  }

  /// Subscribe to multiple event types via a filter predicate.
  StreamSubscription<BonyanEvent> onWhere(
    bool Function(BonyanEvent) predicate,
    void Function(BonyanEvent event) handler,
  ) {
    return stream.where(predicate).listen(handler);
  }

  void dispose() {
    _controller.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 8 — RIVERPOD PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

final bonyanEventBusProvider = Provider<BonyanEventBus>((ref) {
  final bus = BonyanEventBus();
  ref.onDispose(bus.dispose);
  return bus;
});

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 9 — CROSS-FEATURE REACTION RULES (Wiring Layer)
//
// This is where the "magic connections" live. Each Riverpod listener
// subscribes to the bus and fires secondary effects. Keep domain logic
// in its own feature; only cross-cutting reactions live here.
// ─────────────────────────────────────────────────────────────────────────────

/// Call once from main.dart after ProviderContainer is initialized.
/// Wires all cross-feature reactions.
void initEventBusReactions(ProviderContainer container) {
  final bus = container.read(bonyanEventBusProvider);
  final logger = Logger();

  // ── RULE 1: Prayer on time → +15 Bonyan Coins ────────────────────────────
  bus.on<PrayerCheckedInEvent>((e) {
    if (!e.isOnTime) return;
    bus.fire(BonyanCoinEarnedEvent(
      amount: 15,
      source: CoinSource.prayerOnTime,
      reason: 'صليت ${e.prayerName} في وقتها ✨',
      timestamp: DateTime.now(),
      sourceUserId: e.sourceUserId,
    ));
    logger.i('💰 Prayer on time → +15 coins for ${e.sourceUserId}');
  });

  // ── RULE 2: Azkar completed → +10 coins + refresh leaderboard ────────────
  bus.on<AzkarCompletedEvent>((e) {
    bus.fire(BonyanCoinEarnedEvent(
      amount: 10,
      source: CoinSource.azkarComplete,
      reason: 'أتممت أذكار ${e.azkarSet} 🌿',
      timestamp: DateTime.now(),
      sourceUserId: e.sourceUserId,
    ));
  });

  // ── RULE 3: Grade drop → trigger Mueen AI message + rescue plan ──────────
  bus.on<GradeDropDetectedEvent>((e) {
    if (e.dropPercentage < 10) return; // Only significant drops
    bus.fire(MueenMessageReadyEvent(
      messageId: 'mueen_grade_${e.subjectId}_${e.timestamp.millisecondsSinceEpoch}',
      trigger: MueenTrigger.gradeDropDetected,
      messageAr:
          'لاحظت تراجعًا في ${e.subjectName}. لا تقلق — أعددت لك خطة إنقاذ مخصصة 📚',
      deepLinkRoute: '/rescue-plan/${e.subjectId}',
      requiresAck: true,
      timestamp: DateTime.now(),
      sourceUserId: e.sourceUserId,
    ));
    logger.w('🚨 Grade drop ${e.dropPercentage.toStringAsFixed(1)}% → Mueen activated');
  });

  // ── RULE 4: Prayer missed repeatedly → Mueen supportive message ──────────
  bus.on<PrayerMissedEvent>((e) {
    if (e.consecutiveMisses < 2) return;
    bus.fire(MueenMessageReadyEvent(
      messageId: 'mueen_prayer_${e.timestamp.millisecondsSinceEpoch}',
      trigger: MueenTrigger.prayerMissedRepeatedly,
      messageAr:
          'أخي، فاتتك صلاة ${e.prayerName} ${e.consecutiveMisses} مرات. '
          'تذكر: الصلاة عماد الدين. أنا هنا لمساعدتك 🤍',
      requiresAck: false,
      timestamp: DateTime.now(),
      sourceUserId: e.sourceUserId,
    ));
  });

  // ── RULE 5: Study session → coins proportional to duration ───────────────
  bus.on<StudySessionCompletedEvent>((e) {
    final coins = (e.durationMinutes / 15).floor().clamp(1, 20) *
        (e.wasAiAssisted ? 2 : 1);
    bus.fire(BonyanCoinEarnedEvent(
      amount: coins,
      source: CoinSource.studyStreak,
      reason: 'جلسة مذاكرة ${e.durationMinutes} دقيقة 📖',
      timestamp: DateTime.now(),
      sourceUserId: e.sourceUserId,
    ));
  });

  // ── RULE 6: Member missed alarm → cascade to cell + maybe VOIP ───────────
  bus.on<MemberMissedAlarmEvent>((e) {
    if (e.alarmType == AlarmType.fajr && e.remainingMemberIds.isNotEmpty) {
      // Fire VOIP to first available member (the engine handles escalation)
      bus.fire(VoipCallInitiatedEvent(
        cellId: e.cellId,
        targetUserId: e.missedByUserId,
        channelId: 'cell_${e.cellId}_${e.timestamp.millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        sourceUserId: 'system',
      ));
      logger.w('📞 VOIP cascade for missed Fajr in cell ${e.cellId}');
    }
  });

  // ── RULE 7: Lecture transcribed → auto-quiz ready → notify cell ──────────
  bus.on<LectureTranscribedEvent>((e) {
    bus.fire(MueenMessageReadyEvent(
      messageId: 'mueen_quiz_${e.transcriptId}',
      trigger: MueenTrigger.quizReady,
      messageAr: 'تم تحويل المحاضرة إلى اختبار تنافسي! تحدَّ مجموعتك الآن 🏆',
      deepLinkRoute: '/cell-quiz/${e.subjectId}',
      requiresAck: false,
      timestamp: DateTime.now(),
      sourceUserId: e.sourceUserId,
    ));
    // Bonus coins for the student who submitted the lecture
    bus.fire(BonyanCoinEarnedEvent(
      amount: 25,
      source: CoinSource.peerHelp,
      reason: 'سجّلت محاضرة وشاركتها مع المجموعة 🎙️',
      timestamp: DateTime.now(),
      sourceUserId: e.sourceUserId,
    ));
  });

  // ── RULE 8: Early attendance → +20 coins + badge progress ───────────────
  bus.on<AttendanceMarkedEvent>((e) {
    if (!e.isPresent || !e.geofenceVerified) return;
    bus.fire(BonyanCoinEarnedEvent(
      amount: 20,
      source: CoinSource.earlyArrival,
      reason: 'حضرت في الوقت وتم التحقق من موقعك ✅',
      timestamp: DateTime.now(),
      sourceUserId: e.sourceUserId,
    ));
  });

  logger.i('✅ BonyanEventBus: All cross-feature reactions initialized');
}
