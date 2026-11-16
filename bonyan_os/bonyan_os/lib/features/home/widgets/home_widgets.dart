// lib/features/home/widgets/mueen_message_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/bonyan_theme.dart';
import '../../ai/mueen_ai_provider.dart';

class MueenMessageCard extends ConsumerWidget {
  const MueenMessageCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mueenState = ref.watch(mueenAiProvider).valueOrNull;
    final message = mueenState?.activeMessage;
    if (message == null || message.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            BonyanColors.emerald900.withOpacity(0.8),
            BonyanColors.surface800,
          ],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        borderRadius: BorderRadius.circular(BonyanRadius.lg),
        border: Border.all(color: BonyanColors.emerald700, width: 1.5),
        boxShadow: BonyanShadow.emeraldGlow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mueen avatar
          Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: BonyanGradients.emerald,
            ),
            child: const Center(
              child: Text('🤖', style: TextStyle(fontSize: 20)),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
           .shimmer(duration: 2.seconds, color: BonyanColors.neonEmerald.withOpacity(0.3)),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'مُعين',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: BonyanColors.emerald400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    color: BonyanColors.white,
                    height: 1.6,
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

// ─────────────────────────────────────────────────────────────────────────────
// lib/features/home/widgets/prayer_ring_widget.dart
// ─────────────────────────────────────────────────────────────────────────────

// ignore_for_file: library_private_types_in_public_api
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/bonyan_theme.dart';
import '../../prayer/prayer_heatmap_provider.dart';

class PrayerRingWidget extends ConsumerWidget {
  const PrayerRingWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayPrayerRecordProvider);
    final prayers = today?.prayers ?? {};
    final completed = prayers.values
        .where((p) => p.status != PrayerStatus.missed && p.status != PrayerStatus.unknown)
        .length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: BonyanColors.surface900,
        borderRadius: BorderRadius.circular(BonyanRadius.lg),
        border: Border.all(color: BonyanColors.surface500),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Row(
            children: [
              Text('🕌', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text(
                'صلوات اليوم',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: BonyanColors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 5 prayer pills
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: kPrayers.map((name) {
              final entry = prayers[name];
              final status = entry?.status ?? PrayerStatus.unknown;
              return _PrayerPill(name: name, status: status);
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Progress summary
          Row(
            children: [
              Text(
                '$completed / 5 صلوات',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  color: BonyanColors.grey400,
                ),
              ),
              const Spacer(),
              if (today != null)
                Text(
                  'نقاط اليوم: ${today.totalScore}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: BonyanColors.emerald500,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: completed / 5,
              backgroundColor: BonyanColors.surface600,
              valueColor: const AlwaysStoppedAnimation(BonyanColors.emerald500),
              minHeight: 6,
            ),
          ),

          const SizedBox(height: 16),
          // Azkar section
          _AzkarRow(azkar: today?.azkar ?? {}),
        ],
      ),
    );
  }
}

class _PrayerPill extends StatelessWidget {
  final String name;
  final PrayerStatus status;
  const _PrayerPill({required this.name, required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, border, textColor, icon) = switch (status) {
      PrayerStatus.onTime => (
          BonyanColors.emerald900,
          BonyanColors.emerald500,
          BonyanColors.emerald400,
          '✓'
        ),
      PrayerStatus.late   => (
          const Color(0xFF2D2000),
          BonyanColors.warning,
          BonyanColors.warning,
          '⏰'
        ),
      PrayerStatus.missed => (
          const Color(0xFF2D0000),
          BonyanColors.error,
          BonyanColors.error,
          '✗'
        ),
      _                   => (
          BonyanColors.surface700,
          BonyanColors.surface500,
          BonyanColors.grey400,
          '○'
        ),
    };

    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(BonyanRadius.md),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Column(
        children: [
          Text(icon, style: TextStyle(fontSize: 14, color: textColor)),
          const SizedBox(height: 4),
          Text(
            name,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AzkarRow extends StatelessWidget {
  final Map<String, bool> azkar;
  const _AzkarRow({required this.azkar});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: kAzkarSets.map((set) {
        final done = azkar[set] ?? false;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: done ? BonyanColors.emerald900 : BonyanColors.surface700,
            borderRadius: BorderRadius.circular(BonyanRadius.full),
            border: Border.all(
              color: done ? BonyanColors.emerald600 : BonyanColors.surface500,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(done ? '📿' : '○', style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                'أذكار $set',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: done ? BonyanColors.emerald400 : BonyanColors.grey400,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// lib/features/home/widgets/quick_stats_row.dart
// ─────────────────────────────────────────────────────────────────────────────

class QuickStatsRow extends ConsumerWidget {
  const QuickStatsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coins    = ref.watch(coinBalanceProvider);
    final weekly   = ref.watch(weeklyConsistencyProvider);
    final monthly  = ref.watch(monthlyConsistencyProvider);
    final badges   = ref.watch(earnedBadgesProvider).length;

    final stats = [
      _Stat(label: 'العملات',   value: coins.toString(),         icon: '🪙',  color: BonyanColors.goldAccent),
      _Stat(label: 'أسبوعي',   value: '${(weekly * 100).round()}%', icon: '📊', color: BonyanColors.emerald500),
      _Stat(label: 'شهري',     value: '${(monthly * 100).round()}%', icon: '📅', color: BonyanColors.info),
      _Stat(label: 'الشارات',  value: badges.toString(),          icon: '🏅',  color: BonyanColors.purpleAcc),
    ];

    return Row(
      children: stats.asMap().entries.map((e) {
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: e.key < stats.length - 1 ? 8 : 0),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: BonyanColors.surface900,
              borderRadius: BorderRadius.circular(BonyanRadius.md),
              border: Border.all(color: BonyanColors.surface500),
            ),
            child: Column(
              children: [
                Text(e.value.icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 4),
                Text(
                  e.value.value,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: e.value.color,
                  ),
                ),
                Text(
                  e.value.label,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10,
                    color: BonyanColors.grey400,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _Stat {
  final String label, value, icon;
  final Color color;
  const _Stat({required this.label, required this.value, required this.icon, required this.color});
}

// ─────────────────────────────────────────────────────────────────────────────
// lib/features/home/widgets/rescue_plan_banner.dart
// ─────────────────────────────────────────────────────────────────────────────

class RescuePlanBanner extends StatelessWidget {
  final List<GradePrediction> predictions;
  const RescuePlanBanner({super.key, required this.predictions});

  @override
  Widget build(BuildContext context) {
    final critical = predictions.where((p) => p.isCritical).toList();
    if (critical.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0000),
        borderRadius: BorderRadius.circular(BonyanRadius.md),
        border: Border.all(color: BonyanColors.error, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BonyanColors.error.withOpacity(0.15),
            ),
            child: const Center(
              child: Text('📚', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'خطة إنقاذ جاهزة!',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: BonyanColors.error,
                  ),
                ),
                Text(
                  '${critical.map((p) => p.subjectNameAr).join(' · ')} — تراجع ملحوظ',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: BonyanColors.grey400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {}, // navigate to rescue plan screen
            style: TextButton.styleFrom(
              backgroundColor: BonyanColors.error.withOpacity(0.15),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('افتح',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: BonyanColors.error)),
          ),
        ],
      ),
    );
  }
}
