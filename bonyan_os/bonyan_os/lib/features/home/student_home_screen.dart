// lib/features/home/student_home_screen.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║      بنيان OS — الشاشة الرئيسية للطالب                     ║
// ║  OLED Neo-brutalism · Cairo · Emerald Glow · RTL            ║
// ╚══════════════════════════════════════════════════════════════╝

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

import '../../core/theme/bonyan_theme.dart';
import '../auth/master_auth_provider.dart';
import '../gamification/sumou_provider.dart';
import '../prayer/prayer_heatmap_provider.dart';
import '../ai/mueen_ai_provider.dart';
import '../alarm/logic/cascade_alarm_engine.dart';
import 'widgets/cell_status_widget.dart';
import 'widgets/mueen_message_card.dart';
import 'widgets/prayer_ring_widget.dart';
import 'widgets/quick_stats_row.dart';
import 'widgets/rescue_plan_banner.dart';

class StudentHomeScreen extends ConsumerStatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final ScrollController _scrollController;
  double _headerOpacity = 1.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scrollController = ScrollController()
      ..addListener(() {
        final opacity = (1 - _scrollController.offset / 120).clamp(0.0, 1.0);
        if (mounted) setState(() => _headerOpacity = opacity);
      });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile   = ref.watch(currentProfileProvider);
    final coins     = ref.watch(coinBalanceProvider);
    final warnings  = ref.watch(warnedBadgesProvider);
    final atRisk    = ref.watch(atRiskSubjectsProvider);
    final weekly    = ref.watch(weeklyConsistencyProvider);

    return Scaffold(
      backgroundColor: BonyanColors.black,
      body: Stack(
        children: [
          // ── Ambient emerald glow top-right ────────────────────────────────
          Positioned(
            top: -80, right: -60,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  BonyanColors.emerald500.withOpacity(0.18),
                  Colors.transparent,
                ]),
              ),
            ),
          ),

          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── SliverAppBar ───────────────────────────────────────────────
              SliverAppBar(
                expandedHeight: 180,
                collapsedHeight: 64,
                pinned: true,
                backgroundColor: BonyanColors.black,
                elevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildHeroHeader(profile, weekly, _headerOpacity),
                  collapseMode: CollapseMode.pin,
                ),
                title: Opacity(
                  opacity: 1 - _headerOpacity,
                  child: Row(
                    children: [
                      Text(
                        'بنيان',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: BonyanColors.emerald500,
                        ),
                      ),
                      const Spacer(),
                      _CoinChip(coins: coins),
                    ],
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 8),

                    // ── Mueen AI message (if any) ──────────────────────────
                    const MueenMessageCard()
                        .animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),

                    const SizedBox(height: 16),

                    // ── Rescue plan banner (if at risk) ───────────────────
                    if (atRisk.isNotEmpty)
                      RescuePlanBanner(predictions: atRisk)
                          .animate().fadeIn(delay: 150.ms).slideY(begin: 0.1),

                    if (atRisk.isNotEmpty) const SizedBox(height: 16),

                    // ── Quick stats row ───────────────────────────────────
                    const QuickStatsRow()
                        .animate().fadeIn(delay: 200.ms),

                    const SizedBox(height: 20),

                    // ── Prayer ring + today's prayers ─────────────────────
                    const PrayerRingWidget()
                        .animate().fadeIn(delay: 250.ms).slideY(begin: 0.05),

                    const SizedBox(height: 20),

                    // ── Cell of 5 status ──────────────────────────────────
                    const CellStatusWidget()
                        .animate().fadeIn(delay: 300.ms).slideY(begin: 0.05),

                    const SizedBox(height: 20),

                    // ── Badge warnings ────────────────────────────────────
                    if (warnings.isNotEmpty) ...[
                      _BadgeWarningSection(warnings: warnings)
                          .animate().fadeIn(delay: 350.ms),
                      const SizedBox(height: 20),
                    ],

                    // ── Heatmap preview ───────────────────────────────────
                    _HeatmapPreviewCard()
                        .animate().fadeIn(delay: 400.ms),

                    const SizedBox(height: 100), // nav bar clearance
                  ]),
                ),
              ),
            ],
          ),

          // ── Bottom Navigation ──────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _BottomNav(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(
    BonyanUserProfile? profile,
    double weekly,
    double opacity,
  ) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: BonyanColors.grey400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile?.displayName ?? 'الطالب',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: BonyanColors.white,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _CoinChip(coins: ref.watch(coinBalanceProvider)),
              ],
            ),
            const SizedBox(height: 12),
            // Weekly consistency bar
            _WeeklyBar(consistency: weekly),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6)  return 'طاب سهرك 🌙';
    if (h < 12) return 'صباح الخير 🌅';
    if (h < 18) return 'مساء الخير ☀️';
    return 'مساء النور 🌆';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _CoinChip extends StatelessWidget {
  final int coins;
  const _CoinChip({required this.coins});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BonyanRadius.full),
        gradient: BonyanGradients.coinShimmer,
        boxShadow: [
          BoxShadow(
            color: BonyanColors.goldAccent.withOpacity(0.35),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪙', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            coins.toString(),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: BonyanColors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyBar extends StatelessWidget {
  final double consistency; // 0.0–1.0
  const _WeeklyBar({required this.consistency});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'الانتظام الأسبوعي',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: BonyanColors.grey400,
              ),
            ),
            const Spacer(),
            Text(
              '${(consistency * 100).round()}%',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _color(consistency),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: consistency,
            backgroundColor: BonyanColors.surface600,
            valueColor: AlwaysStoppedAnimation(_color(consistency)),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Color _color(double v) {
    if (v > 0.8) return BonyanColors.emerald500;
    if (v > 0.5) return BonyanColors.warning;
    return BonyanColors.error;
  }
}

class _BadgeWarningSection extends StatelessWidget {
  final List<BonyanBadge> warnings;
  const _BadgeWarningSection({required this.warnings});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '⚠️ شاراتك في خطر',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: BonyanColors.warning,
            ),
          ),
        ),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            reverse: true, // RTL
            itemCount: warnings.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              final b = warnings[i];
              return Container(
                width: 160,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BonyanColors.surface800,
                  borderRadius: BorderRadius.circular(BonyanRadius.md),
                  border: Border.all(color: BonyanColors.warning, width: 1.5),
                ),
                child: Row(
                  children: [
                    Text(b.iconPath.contains('fajr') ? '🌙' : '🏅',
                        style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        b.nameAr,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: BonyanColors.white,
                        ),
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HeatmapPreviewCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cells = ref.watch(heatmapCellsProvider);
    final recent = cells.length > 35 ? cells.sublist(cells.length - 35) : cells;

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
          Row(
            children: [
              const Text('📿', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text(
                'خريطة الانتظام — آخر 35 يومًا',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: BonyanColors.white,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {},
                child: const Text('التفاصيل',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: BonyanColors.emerald500)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: recent.map((cell) {
              return Tooltip(
                message: '${cell.date.day}/${cell.date.month} — ${cell.score}%',
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: BonyanColors.emerald500.withAlpha(cell.level.alpha),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: HeatLevel.values.map((l) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: BonyanColors.emerald500.withAlpha(l.alpha),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(l.labelAr,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 9,
                          color: BonyanColors.grey400)),
                ],
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends ConsumerStatefulWidget {
  @override
  ConsumerState<_BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends ConsumerState<_BottomNav> {
  int _selected = 0;

  static const _items = [
    (icon: Icons.home_rounded,       label: 'الرئيسية'),
    (icon: Icons.mosque_rounded,     label: 'الصلاة'),
    (icon: Icons.psychology_rounded, label: 'مُعين'),
    (icon: Icons.people_rounded,     label: 'خليتي'),
    (icon: Icons.storefront_rounded, label: 'المتجر'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72 + MediaQuery.of(context).padding.bottom,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: BonyanColors.surface900,
        border: const Border(top: BorderSide(color: BonyanColors.surface500)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_items.length, (i) {
          final item = _items[i];
          final active = i == _selected;
          return GestureDetector(
            onTap: () {
              setState(() => _selected = i);
              BonyanHaptics.softConfirm();
            },
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: active
                  ? BoxDecoration(
                      color: BonyanColors.emerald500.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.icon,
                    color: active ? BonyanColors.emerald500 : BonyanColors.grey400,
                    size: 22,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      color: active ? BonyanColors.emerald500 : BonyanColors.grey400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
