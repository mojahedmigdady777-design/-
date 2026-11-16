// lib/features/alarm/alarm_screen.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║      بنيان OS — شاشة تنبيه الفجر                           ║
// ║  Full-screen wake-up · Cell check-in · Pulse animation      ║
// ╚══════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/bonyan_theme.dart';
import '../alarm/logic/cascade_alarm_engine.dart';
import '../auth/master_auth_provider.dart';
import '../prayer/prayer_heatmap_provider.dart';

class AlarmScreen extends ConsumerStatefulWidget {
  final String cellId;
  final String alarmId;
  final String labelAr;
  final AlarmType alarmType;

  const AlarmScreen({
    super.key,
    required this.cellId,
    required this.alarmId,
    required this.labelAr,
    required this.alarmType,
  });

  @override
  ConsumerState<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends ConsumerState<AlarmScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rippleController;
  late final AnimationController _countdownController;

  int _secondsLeft = AlarmEngineConfig.checkInWindowSeconds;
  Timer? _countdownTimer;
  bool _hasCheckedIn = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _countdownController = AnimationController(
      vsync: this,
      duration: Duration(seconds: AlarmEngineConfig.checkInWindowSeconds),
    )..forward();

    _startCountdown();
    BonyanHaptics.urgentAlarm();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _onWindowExpired();
      }
    });
  }

  Future<void> _onCheckIn() async {
    if (_hasCheckedIn) return;
    setState(() => _hasCheckedIn = true);
    _countdownTimer?.cancel();
    _pulseController.stop();

    await BonyanHaptics.achievementUnlocked();

    final profile = ref.read(currentProfileProvider);
    if (profile != null) {
      await ref.read(cascadeAlarmEngineProvider.notifier).memberCheckIn(
        cellId: widget.cellId,
        alarmId: widget.alarmId,
        userId: profile.uid,
      );

      // Also mark prayer
      if (widget.alarmType == AlarmType.fajr) {
        await ref.read(prayerHeatmapProvider.notifier).markPrayer(
          prayerName: 'فجر',
          status: PrayerStatus.onTime,
        );
      }
    }

    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) _dismissScreen();
  }

  void _onWindowExpired() {
    if (!_hasCheckedIn && mounted) {
      _dismissScreen();
    }
  }

  void _dismissScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rippleController.dispose();
    _countdownController.dispose();
    _countdownTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final checkIns = ref.watch(
      alarmCheckInsProvider(AlarmKey(cellId: widget.cellId, alarmId: widget.alarmId)),
    );

    return WillPopScope(
      onWillPop: () async => _hasCheckedIn, // prevent back during alarm
      child: Scaffold(
        backgroundColor: BonyanColors.black,
        body: Stack(
          children: [
            // ── Ripple background ─────────────────────────────────────────
            ...List.generate(4, (i) => _RippleCircle(
              controller: _rippleController,
              delay: i * 0.25,
            )),

            // ── Ambient glow ──────────────────────────────────────────────
            Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (_, __) => Container(
                  width: 400, height: 400,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      BonyanColors.emerald500.withOpacity(
                          0.12 + _pulseController.value * 0.08),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 40),

                  // ── Label ───────────────────────────────────────────────
                  Text(
                    widget.labelAr,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: BonyanColors.white,
                    ),
                  ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2),

                  const SizedBox(height: 8),

                  Text(
                    'وقت الصلاة — أشعر مجموعتك',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      color: BonyanColors.grey400,
                    ),
                  ).animate().fadeIn(delay: 200.ms),

                  const Spacer(),

                  // ── Cell member check-in status ─────────────────────────
                  checkIns.when(
                    data: (data) => _CellCheckInGrid(checkIns: data),
                    loading: () => const CircularProgressIndicator(
                        color: BonyanColors.emerald500),
                    error: (_, __) => const SizedBox.shrink(),
                  ).animate().fadeIn(delay: 300.ms),

                  const Spacer(),

                  // ── Countdown ring ──────────────────────────────────────
                  _CountdownRing(
                    secondsLeft: _secondsLeft,
                    totalSeconds: AlarmEngineConfig.checkInWindowSeconds,
                    pulseController: _pulseController,
                  ).animate().scale(delay: 400.ms),

                  const Spacer(),

                  // ── Check-in button ─────────────────────────────────────
                  if (!_hasCheckedIn)
                    _CheckInButton(onTap: _onCheckIn, pulse: _pulseController)
                        .animate().fadeIn(delay: 500.ms).slideY(begin: 0.3),

                  if (_hasCheckedIn)
                    _CheckedInConfirmation()
                        .animate().scale().fadeIn(),

                  const SizedBox(height: 60),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _RippleCircle extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  const _RippleCircle({required this.controller, required this.delay});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = ((controller.value + delay) % 1.0);
        return Center(
          child: Opacity(
            opacity: (1 - t) * 0.15,
            child: Container(
              width: 100 + t * 300,
              height: 100 + t * 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: BonyanColors.emerald500,
                  width: 1.5,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CellCheckInGrid extends StatelessWidget {
  final Map<String, MemberCheckIn> checkIns;
  const _CellCheckInGrid({required this.checkIns});

  @override
  Widget build(BuildContext context) {
    if (checkIns.isEmpty) {
      return Text(
        'في انتظار استجابة المجموعة...',
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 14,
          color: BonyanColors.grey400,
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: checkIns.entries.map((e) {
        final ci = e.value;
        final done = ci.isPresent;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? BonyanColors.emerald500
                      : BonyanColors.surface700,
                  border: Border.all(
                    color: done
                        ? BonyanColors.emerald400
                        : BonyanColors.surface500,
                    width: 2,
                  ),
                  boxShadow: done ? BonyanShadow.emeraldGlow : null,
                ),
                child: Center(
                  child: Text(
                    done ? '✓' : '⏳',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ci.userId.length > 4
                    ? ci.userId.substring(0, 4)
                    : ci.userId,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  color: BonyanColors.grey400,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _CountdownRing extends StatelessWidget {
  final int secondsLeft;
  final int totalSeconds;
  final AnimationController pulseController;

  const _CountdownRing({
    required this.secondsLeft,
    required this.totalSeconds,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    final progress = secondsLeft / totalSeconds;
    final mins = secondsLeft ~/ 60;
    final secs = secondsLeft % 60;
    final timeStr = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    final ringColor = progress > 0.5
        ? BonyanColors.emerald500
        : progress > 0.25
            ? BonyanColors.warning
            : BonyanColors.error;

    return AnimatedBuilder(
      animation: pulseController,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          // Glow behind ring
          Container(
            width: 160 + pulseController.value * 10,
            height: 160 + pulseController.value * 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: ringColor.withOpacity(0.3 + pulseController.value * 0.2),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),
          // Progress ring
          SizedBox(
            width: 150, height: 150,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 6,
              backgroundColor: BonyanColors.surface600,
              valueColor: AlwaysStoppedAnimation(ringColor),
              strokeCap: StrokeCap.round,
            ),
          ),
          // Time text
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timeStr,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: ringColor,
                ),
              ),
              const Text(
                'متبقي',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: BonyanColors.grey400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckInButton extends StatelessWidget {
  final VoidCallback onTap;
  final AnimationController pulse;

  const _CheckInButton({required this.onTap, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, child) => Transform.scale(
        scale: 1.0 + pulse.value * 0.04,
        child: child,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 220, height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: BonyanGradients.emerald,
            boxShadow: BonyanShadow.emeraldGlow,
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('🕌', style: TextStyle(fontSize: 48)),
              SizedBox(height: 8),
              Text(
                'حاضر',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: BonyanColors.white,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'اضغط للتأكيد',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  color: BonyanColors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckedInConfirmation extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: BonyanColors.emerald500,
            boxShadow: BonyanShadow.emeraldGlow,
          ),
          child: const Center(
            child: Text('✓', style: TextStyle(fontSize: 60, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'تم تسجيل حضورك! 🌟',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: BonyanColors.emerald400,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '+15 عملة بنيان',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 16,
            color: BonyanColors.goldAccent,
          ),
        ),
      ],
    );
  }
}
