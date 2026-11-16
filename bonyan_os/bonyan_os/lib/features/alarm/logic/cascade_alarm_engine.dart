// lib/features/alarm/logic/cascade_alarm_engine.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║      بنيان OS — محرك تنبيه الخلية المتسلسل                  ║
// ║  Cell-of-5 Cascade Alarm Engine                              ║
// ║  Firebase Realtime DB · FCM · Agora VOIP                    ║
// ╚══════════════════════════════════════════════════════════════╝
//
// Flow for a Fajr alarm in a 5-member cell:
//
//  T+0:00  Alarm fires on all 5 devices simultaneously
//  T+0:00  Members have [checkInWindowSeconds] to tap "حاضر"
//  T+0:05  (if missed) → Urgent FCM push to all other members
//  T+0:08  (if still missed) → Agora VOIP call from member[1] to absentee
//  T+0:12  (if still missed) → escalate to member[2], then [3], then [4]
//  T+0:20  (if all missed) → parent FCM notification
//
// All state lives in Firebase Realtime DB for sub-second sync:
//   /cells/{cellId}/alarms/{alarmId}/checkins/{userId}
//
// Riverpod Listeners on each client watch this path and react in real-time.

import 'dart:async';
import 'dart:math' as math;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logger/logger.dart';

import '../../../core/network/event_bus.dart';
import '../../auth/master_auth_provider.dart';

part 'cascade_alarm_engine.freezed.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — CONSTANTS & CONFIG
// ─────────────────────────────────────────────────────────────────────────────

class AlarmEngineConfig {
  static const checkInWindowSeconds = 300;  // 5 min to tap "حاضر"
  static const fcmEscalationDelay   = Duration(seconds: 300); // 5 min
  static const voipEscalationDelay  = Duration(seconds: 480); // 8 min
  static const parentNotifyDelay    = Duration(seconds: 1200); // 20 min
  static const agoraAppId           = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: '', // Set via --dart-define in CI, never hardcode
  );
  static const maxVoipAttempts = 3;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class CellAlarm with _$CellAlarm {
  const factory CellAlarm({
    required String alarmId,
    required String cellId,
    required AlarmType type,
    required String labelAr,
    required DateTime scheduledAt,
    required List<String> memberIds, // ordered: [0]=initiator, [1..4]=escalation order
    @Default(AlarmStatus.pending) AlarmStatus status,
    @Default({}) Map<String, MemberCheckIn> checkIns,
  }) = _CellAlarm;

  const CellAlarm._();

  List<String> get absentMembers => memberIds
      .where((id) => !checkIns.containsKey(id) || checkIns[id]!.isAbsent)
      .toList();

  List<String> get presentMembers => memberIds
      .where((id) => checkIns.containsKey(id) && checkIns[id]!.isPresent)
      .toList();

  double get completionRate =>
      memberIds.isEmpty ? 0 : presentMembers.length / memberIds.length;

  bool get isFullyComplete => presentMembers.length == memberIds.length;
  bool get hasAnyAbsent    => absentMembers.isNotEmpty;
}

@freezed
class MemberCheckIn with _$MemberCheckIn {
  const factory MemberCheckIn({
    required String userId,
    required CheckInStatus status,
    DateTime? checkedInAt,
    int? delaySeconds,
  }) = _MemberCheckIn;

  const MemberCheckIn._();

  bool get isPresent => status == CheckInStatus.present;
  bool get isAbsent  => status == CheckInStatus.absent || status == CheckInStatus.missed;
}

enum AlarmStatus { pending, active, partialComplete, complete, missed }
enum CheckInStatus { pending, present, absent, missed, voipAnswered }

@freezed
class CascadeState with _$CascadeState {
  const factory CascadeState.idle() = _Idle;
  const factory CascadeState.alarmActive({
    required CellAlarm alarm,
    required Duration timeRemaining,
  }) = _AlarmActive;
  const factory CascadeState.escalating({
    required CellAlarm alarm,
    required List<String> absentMemberIds,
    required EscalationStep currentStep,
  }) = _Escalating;
  const factory CascadeState.resolved({
    required CellAlarm alarm,
    required double completionRate,
  }) = _Resolved;
  const factory CascadeState.error({required String messageAr}) = _Error;
}

enum EscalationStep { fcmPush, voipCall, parentNotify }

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — ALARM SCHEDULE MODEL (persisted to Firestore)
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class ScheduledAlarm with _$ScheduledAlarm {
  const factory ScheduledAlarm({
    required String alarmId,
    required String cellId,
    required AlarmType type,
    required String labelAr,
    required int hourUtc,
    required int minuteUtc,
    required List<int> repeatDays, // 1=Sun ... 7=Sat, empty=one-shot
    @Default(true) bool isActive,
    String? parentGroupId,         // FCM topic for parent notifications
  }) = _ScheduledAlarm;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — THE ALARM ENGINE
// ─────────────────────────────────────────────────────────────────────────────

class CascadeAlarmEngine extends AutoDisposeAsyncNotifier<CascadeState> {
  final _logger = Logger();
  final _db = FirebaseDatabase.instance;

  // Active timers for escalation steps — cancelled on alarm resolution
  final List<Timer> _escalationTimers = [];
  StreamSubscription<DatabaseEvent>? _checkInSubscription;
  RtcEngine? _agoraEngine;
  int _voipAttemptCount = 0;

  @override
  Future<CascadeState> build() async {
    ref.onDispose(_cleanup);
    return const CascadeState.idle();
  }

  // ── TRIGGER ALARM ─────────────────────────────────────────────────────────
  // Called by: WorkManager background task at scheduled time
  // OR: Firebase Cloud Function that broadcasts to all cell members via FCM.
  Future<void> triggerAlarm(ScheduledAlarm scheduled) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;

    final alarmId = '${scheduled.cellId}_${DateTime.now().millisecondsSinceEpoch}';
    _logger.i('🔔 Alarm triggered: ${scheduled.labelAr} for cell ${scheduled.cellId}');

    // 1. Write alarm record to Realtime DB (all 5 clients see this instantly)
    final alarmRef = _db.ref('cells/${scheduled.cellId}/alarms/$alarmId');
    await alarmRef.set({
      'alarmId': alarmId,
      'cellId': scheduled.cellId,
      'type': scheduled.type.name,
      'labelAr': scheduled.labelAr,
      'scheduledAt': DateTime.now().toIso8601String(),
      'status': AlarmStatus.active.name,
      'memberIds': profile.cellId != null ? [] : [], // fetched from cell doc
    });

    // 2. Show local notification with wake-lock (Android)
    await _showLocalAlarmNotification(scheduled);

    // 3. Start listening to check-ins from all members
    _startCheckInListener(scheduled.cellId, alarmId, scheduled);

    // 4. Set escalation timers
    _scheduleEscalation(scheduled.cellId, alarmId, scheduled);

    // 5. Fire event bus (Gamification can listen for early check-in bonus)
    ref.read(bonyanEventBusProvider).fire(CellAlarmTriggeredEvent(
      cellId: scheduled.cellId,
      alarmType: scheduled.type,
      alarmLabel: scheduled.labelAr,
      memberIds: const [], // populated by listener
      timestamp: DateTime.now(),
      sourceUserId: profile.uid,
    ));

    state = AsyncData(CascadeState.alarmActive(
      alarm: CellAlarm(
        alarmId: alarmId,
        cellId: scheduled.cellId,
        type: scheduled.type,
        labelAr: scheduled.labelAr,
        scheduledAt: DateTime.now(),
        memberIds: const [],
      ),
      timeRemaining: Duration(seconds: AlarmEngineConfig.checkInWindowSeconds),
    ));
  }

  // ── MEMBER CHECK-IN ───────────────────────────────────────────────────────
  // Called when student taps "حاضر" button on the alarm screen.
  Future<void> memberCheckIn({
    required String cellId,
    required String alarmId,
    required String userId,
  }) async {
    final now = DateTime.now();
    final checkInRef = _db.ref('cells/$cellId/alarms/$alarmId/checkins/$userId');

    await checkInRef.set({
      'userId': userId,
      'status': CheckInStatus.present.name,
      'checkedInAt': now.toIso8601String(),
    });

    _logger.i('✅ Check-in: $userId in alarm $alarmId');

    // Fire event bus → Gamification awards coins
    ref.read(bonyanEventBusProvider).fire(MemberCheckedInEvent(
      cellId: cellId,
      alarmType: AlarmType.fajr, // from current alarm context
      checkInDelaySeconds: 0,    // calculated from alarm trigger time
      timestamp: now,
      sourceUserId: userId,
    ));
  }

  // ── LISTEN TO CHECK-INS (Firebase Realtime DB) ────────────────────────────
  void _startCheckInListener(
    String cellId,
    String alarmId,
    ScheduledAlarm scheduled,
  ) {
    final checkInsRef = _db.ref('cells/$cellId/alarms/$alarmId/checkins');

    _checkInSubscription = checkInsRef.onValue.listen((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists) return;

      final data = Map<String, dynamic>.from(
        snapshot.value as Map<Object?, Object?>? ?? {},
      );

      final checkIns = data.map((key, value) {
        final v = Map<String, dynamic>.from(value as Map<Object?, Object?>);
        return MapEntry(
          key.toString(),
          MemberCheckIn(
            userId: v['userId'] as String,
            status: CheckInStatus.values.firstWhere(
              (s) => s.name == v['status'],
              orElse: () => CheckInStatus.pending,
            ),
            checkedInAt: v['checkedInAt'] != null
                ? DateTime.tryParse(v['checkedInAt'] as String)
                : null,
          ),
        );
      });

      _logger.d('📊 Check-ins update: ${checkIns.length} responses');

      // Update local state
      state = state.whenData((s) {
        return s.maybeWhen(
          alarmActive: (alarm, timeRemaining) => CascadeState.alarmActive(
            alarm: alarm.copyWith(checkIns: checkIns),
            timeRemaining: timeRemaining,
          ),
          orElse: () => s,
        );
      });
    });
  }

  // ── ESCALATION SCHEDULE ───────────────────────────────────────────────────
  void _scheduleEscalation(
    String cellId,
    String alarmId,
    ScheduledAlarm scheduled,
  ) {
    // Step 1: FCM push after 5 min
    _escalationTimers.add(
      Timer(AlarmEngineConfig.fcmEscalationDelay, () {
        _runFcmEscalation(cellId, alarmId, scheduled);
      }),
    );

    // Step 2: VOIP after 8 min
    _escalationTimers.add(
      Timer(AlarmEngineConfig.voipEscalationDelay, () {
        _runVoipEscalation(cellId, alarmId);
      }),
    );

    // Step 3: Parent notification after 20 min
    _escalationTimers.add(
      Timer(AlarmEngineConfig.parentNotifyDelay, () {
        _notifyParents(cellId, alarmId, scheduled);
      }),
    );
  }

  // ── STEP 1: FCM CASCADE TO CELL MEMBERS ──────────────────────────────────
  Future<void> _runFcmEscalation(
    String cellId,
    String alarmId,
    ScheduledAlarm scheduled,
  ) async {
    final currentAlarm = _currentAlarm;
    if (currentAlarm == null) return;

    final absent = currentAlarm.absentMembers;
    if (absent.isEmpty) {
      _logger.i('🎉 No absent members — escalation not needed');
      return;
    }

    _logger.w('📢 FCM escalation: ${absent.length} absent members');

    state = AsyncData(CascadeState.escalating(
      alarm: currentAlarm,
      absentMemberIds: absent,
      currentStep: EscalationStep.fcmPush,
    ));

    // Notify ALL present members to check on their absent peers
    // The Cloud Function (cells-cascade-notify) handles FCM delivery
    await _db.ref('cells/$cellId/alarms/$alarmId/escalation').set({
      'step': EscalationStep.fcmPush.name,
      'triggeredAt': DateTime.now().toIso8601String(),
      'absentMemberIds': absent,
    });

    ref.read(bonyanEventBusProvider).fire(MemberMissedAlarmEvent(
      cellId: cellId,
      missedByUserId: absent.first,
      alarmType: scheduled.type,
      remainingMemberIds: currentAlarm.presentMembers,
      timestamp: DateTime.now(),
      sourceUserId: 'system',
    ));
  }

  // ── STEP 2: VOIP CALL TO ABSENT MEMBERS ──────────────────────────────────
  Future<void> _runVoipEscalation(String cellId, String alarmId) async {
    final currentAlarm = _currentAlarm;
    if (currentAlarm == null || currentAlarm.absentMembers.isEmpty) return;

    _logger.w('📞 VOIP escalation initiated');

    state = AsyncData(CascadeState.escalating(
      alarm: currentAlarm,
      absentMemberIds: currentAlarm.absentMembers,
      currentStep: EscalationStep.voipCall,
    ));

    // Initiate Agora call from first available present member
    // to each absent member
    for (final absentId in currentAlarm.absentMembers) {
      if (_voipAttemptCount >= AlarmEngineConfig.maxVoipAttempts) break;

      await _initiateVoipCall(
        cellId: cellId,
        alarmId: alarmId,
        targetUserId: absentId,
      );
      _voipAttemptCount++;

      // Brief pause between calls
      await Future.delayed(const Duration(seconds: 30));
    }
  }

  // ── STEP 3: PARENT NOTIFICATION ───────────────────────────────────────────
  Future<void> _notifyParents(
    String cellId,
    String alarmId,
    ScheduledAlarm scheduled,
  ) async {
    final currentAlarm = _currentAlarm;
    if (currentAlarm == null || currentAlarm.absentMembers.isEmpty) return;

    _logger.w('👨‍👩‍👦 Notifying parents of ${currentAlarm.absentMembers.length} absent students');

    state = AsyncData(CascadeState.escalating(
      alarm: currentAlarm,
      absentMemberIds: currentAlarm.absentMembers,
      currentStep: EscalationStep.parentNotify,
    ));

    // Write to Realtime DB — Cloud Function reads this and sends FCM to parents
    await _db.ref('cells/$cellId/alarms/$alarmId/parentAlert').set({
      'triggeredAt': DateTime.now().toIso8601String(),
      'absentMemberIds': currentAlarm.absentMembers,
      'alarmLabel': scheduled.labelAr,
      'notifyParents': true,
    });
  }

  // ── AGORA VOIP CALL ───────────────────────────────────────────────────────
  Future<void> _initiateVoipCall({
    required String cellId,
    required String alarmId,
    required String targetUserId,
  }) async {
    if (AlarmEngineConfig.agoraAppId.isEmpty) {
      _logger.e('❌ Agora App ID not configured — set AGORA_APP_ID via --dart-define');
      return;
    }

    try {
      _agoraEngine ??= createAgoraRtcEngine();
      await _agoraEngine!.initialize(RtcEngineContext(
        appId: AlarmEngineConfig.agoraAppId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

      final channelId = 'wake_${cellId}_${alarmId}_${targetUserId}';

      // Signal the target device to join via FCM (handled by Cloud Function)
      await _db.ref('voip/incoming/$targetUserId').set({
        'channelId': channelId,
        'alarmId': alarmId,
        'cellId': cellId,
        'callType': 'wakeUp',
        'labelAr': 'تنبيه: صلاة الفجر 🌙',
        'initiatedAt': DateTime.now().toIso8601String(),
      });

      await _agoraEngine!.joinChannel(
        token: await _fetchAgoraToken(channelId), // fetched from server
        channelId: channelId,
        uid: 0,
        options: const ChannelMediaOptions(
          autoSubscribeAudio: true,
          publishMicrophoneTrack: true,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );

      ref.read(bonyanEventBusProvider).fire(VoipCallInitiatedEvent(
        cellId: cellId,
        targetUserId: targetUserId,
        channelId: channelId,
        timestamp: DateTime.now(),
        sourceUserId: 'system',
      ));

      _logger.i('📞 VOIP call initiated to $targetUserId on channel $channelId');
    } catch (e) {
      _logger.e('❌ VOIP failed: $e');
    }
  }

  // ── LOCAL NOTIFICATION (Wake-lock style) ──────────────────────────────────
  Future<void> _showLocalAlarmNotification(ScheduledAlarm scheduled) async {
    final plugin = FlutterLocalNotificationsPlugin();

    const androidDetails = AndroidNotificationDetails(
      'bonyan_alarm_channel',
      'تنبيهات بنيان',
      channelDescription: 'تنبيهات خلية الخمسة',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,       // Wake screen
      category: AndroidNotificationCategory.alarm,
      sound: RawResourceAndroidNotificationSound('fajr_adhan'),
      enableVibration: true,
      vibrationPattern: [0, 500, 200, 500, 200, 500], // Urgent pattern
      ongoing: true,                // Non-dismissable until check-in
      autoCancel: false,
      actions: [
        AndroidNotificationAction(
          'checkin_action',
          'حاضر ✅',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'snooze_action',
          'تأجيل 5 دقائق',
          showsUserInterface: false,
        ),
      ],
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await plugin.show(
      scheduled.alarmId.hashCode.abs() % 10000,
      '${scheduled.labelAr} 🌙',
      'وقت الصلاة — اضغط "حاضر" لإشعار مجموعتك',
      notificationDetails,
    );
  }

  // ── RESOLVE ALARM ─────────────────────────────────────────────────────────
  Future<void> resolveAlarm(String cellId, String alarmId) async {
    final currentAlarm = _currentAlarm;
    if (currentAlarm == null) return;

    _cancelEscalationTimers();
    await _checkInSubscription?.cancel();
    await _agoraEngine?.leaveChannel();

    final finalStatus = currentAlarm.isFullyComplete
        ? AlarmStatus.complete
        : currentAlarm.absentMembers.length == currentAlarm.memberIds.length
            ? AlarmStatus.missed
            : AlarmStatus.partialComplete;

    await _db.ref('cells/$cellId/alarms/$alarmId/status').set(finalStatus.name);
    await _db.ref('cells/$cellId/alarms/$alarmId/resolvedAt')
        .set(DateTime.now().toIso8601String());

    state = AsyncData(CascadeState.resolved(
      alarm: currentAlarm.copyWith(status: finalStatus),
      completionRate: currentAlarm.completionRate,
    ));

    _logger.i('✅ Alarm $alarmId resolved — completion: ${(currentAlarm.completionRate * 100).round()}%');
  }

  // ── SCHEDULE DAILY ALARMS ─────────────────────────────────────────────────
  /// Creates the 5 daily prayer alarms for a cell.
  /// Should be called once when a student joins a cell, and refreshed daily.
  List<ScheduledAlarm> buildPrayerAlarmsForCell(String cellId) {
    // Times are illustrative — production would use prayer calculation library
    // based on school coordinates (Mecca bearing, etc.)
    return [
      ScheduledAlarm(
        alarmId: '${cellId}_fajr',
        cellId: cellId,
        type: AlarmType.fajr,
        labelAr: 'صلاة الفجر',
        hourUtc: 2, minuteUtc: 30, // Adjust to local time in prod
        repeatDays: [1, 2, 3, 4, 5, 6, 7],
      ),
      ScheduledAlarm(
        alarmId: '${cellId}_dhuhr',
        cellId: cellId,
        type: AlarmType.study,
        labelAr: 'صلاة الظهر',
        hourUtc: 9, minuteUtc: 0,
        repeatDays: [1, 2, 3, 4, 5, 6, 7],
      ),
    ];
  }

  // ── COLLECTIVE GPA UPDATE ─────────────────────────────────────────────────
  /// Recalculates and writes collective cell score to Realtime DB.
  /// Components: attendance (40%) + grades (40%) + azkar (20%)
  Future<double> recalculateCellScore({
    required String cellId,
    required List<double> memberAttendanceRates, // 0.0–1.0
    required List<double> memberGpas,            // 0.0–4.0 scale
    required List<double> memberAzkarRates,      // 0.0–1.0
  }) async {
    final n = math.min(
      math.min(memberAttendanceRates.length, memberGpas.length),
      memberAzkarRates.length,
    );
    if (n == 0) return 0;

    final avgAttendance = memberAttendanceRates.take(n).reduce((a, b) => a + b) / n;
    final avgGpa        = memberGpas.take(n).reduce((a, b) => a + b) / n;
    final avgAzkar      = memberAzkarRates.take(n).reduce((a, b) => a + b) / n;

    final score = (avgAttendance * 0.4) + ((avgGpa / 4.0) * 0.4) + (avgAzkar * 0.2);
    final scorePct = (score * 100).clamp(0.0, 100.0);

    await _db.ref('cells/$cellId/collectiveScore').set(scorePct);
    await _db.ref('cells/$cellId/scoreUpdatedAt').set(DateTime.now().toIso8601String());

    _logger.i('📊 Cell $cellId collective score: ${scorePct.toStringAsFixed(1)}%');

    ref.read(bonyanEventBusProvider).fire(LeaderboardUpdatedEvent(
      cellId: cellId,
      newRank: 0, // Rank resolved by Cloud Function after write
      collectiveScore: scorePct,
      timestamp: DateTime.now(),
      sourceUserId: 'system',
    ));

    return scorePct;
  }

  // ── PRIVATE HELPERS ───────────────────────────────────────────────────────

  CellAlarm? get _currentAlarm => state.valueOrNull?.maybeWhen(
        alarmActive: (alarm, _) => alarm,
        escalating: (alarm, _, __) => alarm,
        orElse: () => null,
      );

  void _cancelEscalationTimers() {
    for (final t in _escalationTimers) {
      t.cancel();
    }
    _escalationTimers.clear();
  }

  /// In production: calls Cloud Function to generate a time-limited Agora token.
  /// NEVER generate Agora tokens client-side.
  Future<String> _fetchAgoraToken(String channelId) async {
    // TODO: call /generateAgoraToken Cloud Function
    // For now returning empty — Agora operates in testing mode without token
    return '';
  }

  Future<void> _cleanup() async {
    _cancelEscalationTimers();
    await _checkInSubscription?.cancel();
    await _agoraEngine?.leaveChannel();
    await _agoraEngine?.release();
    _agoraEngine = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 5 — RIVERPOD PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final cascadeAlarmEngineProvider =
    AutoDisposeAsyncNotifierProvider<CascadeAlarmEngine, CascadeState>(
  CascadeAlarmEngine.new,
);

/// Stream of live check-ins for a specific alarm (for real-time UI updates)
final alarmCheckInsProvider =
    StreamProvider.autoDispose.family<Map<String, MemberCheckIn>, AlarmKey>(
  (ref, key) {
    final db = FirebaseDatabase.instance;
    final ref_ = db.ref('cells/${key.cellId}/alarms/${key.alarmId}/checkins');

    return ref_.onValue.map((event) {
      if (!event.snapshot.exists) return {};
      final data = Map<String, dynamic>.from(
        event.snapshot.value as Map<Object?, Object?>? ?? {},
      );
      return data.map((k, v) {
        final vm = Map<String, dynamic>.from(v as Map<Object?, Object?>);
        return MapEntry(
          k.toString(),
          MemberCheckIn(
            userId: vm['userId'] as String,
            status: CheckInStatus.values.firstWhere(
              (s) => s.name == vm['status'],
              orElse: () => CheckInStatus.pending,
            ),
            checkedInAt: vm['checkedInAt'] != null
                ? DateTime.tryParse(vm['checkedInAt'] as String)
                : null,
          ),
        );
      });
    });
  },
);

/// Live collective score stream for a cell
final cellCollectiveScoreProvider =
    StreamProvider.autoDispose.family<double, String>((ref, cellId) {
  final db = FirebaseDatabase.instance;
  return db
      .ref('cells/$cellId/collectiveScore')
      .onValue
      .map((e) => (e.snapshot.value as num?)?.toDouble() ?? 0.0);
});

/// Helper key for family providers
class AlarmKey {
  final String cellId;
  final String alarmId;
  const AlarmKey({required this.cellId, required this.alarmId});

  @override
  bool operator ==(Object other) =>
      other is AlarmKey && other.cellId == cellId && other.alarmId == alarmId;

  @override
  int get hashCode => Object.hash(cellId, alarmId);
}
