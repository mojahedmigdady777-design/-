// lib/features/home/widgets/cell_status_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bonyan_theme.dart';
import '../../alarm/logic/cascade_alarm_engine.dart';
import '../../auth/master_auth_provider.dart';

class CellStatusWidget extends ConsumerWidget {
  const CellStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final cellId  = profile?.cellId ?? '';

    final scoreAsync = cellId.isNotEmpty
        ? ref.watch(cellCollectiveScoreProvider(cellId))
        : const AsyncData(0.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: BonyanColors.surface900,
        borderRadius: BorderRadius.circular(BonyanRadius.lg),
        border: Border.all(color: BonyanColors.surface500),
        boxShadow: BonyanShadow.cardDark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: BonyanGradients.emerald,
                ),
                child: const Center(
                  child: Text('🕌', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'خلية الخمسة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: BonyanColors.white,
                  ),
                ),
              ),
              scoreAsync.when(
                data: (score) => _ScoreBadge(score: score),
                loading: () => const SizedBox(width: 48, height: 24,
                    child: LinearProgressIndicator()),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 5 member avatar slots  (data would come from Firestore stream)
          _FiveMemberRow(),

          const SizedBox(height: 14),

          // Collective score breakdown
          scoreAsync.when(
            data: (score) => _ScoreBar(score: score),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final double score;
  const _ScoreBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? BonyanColors.emerald500
        : score >= 50
            ? BonyanColors.warning
            : BonyanColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(BonyanRadius.full),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        '${score.round()}%',
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _FiveMemberRow extends StatelessWidget {
  // In production: watch a Firestore stream for live check-in status
  final List<_MemberStatus> members = const [
    _MemberStatus(name: 'أحمد', isOnline: true, hasCheckedIn: true),
    _MemberStatus(name: 'محمد', isOnline: true, hasCheckedIn: true),
    _MemberStatus(name: 'خالد', isOnline: false, hasCheckedIn: false),
    _MemberStatus(name: 'عمر', isOnline: true, hasCheckedIn: false),
    _MemberStatus(name: 'يوسف', isOnline: true, hasCheckedIn: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: members.map((m) => _MemberAvatar(member: m)).toList(),
    );
  }
}

class _MemberStatus {
  final String name;
  final bool isOnline;
  final bool hasCheckedIn;
  const _MemberStatus({
    required this.name,
    required this.isOnline,
    required this.hasCheckedIn,
  });
}

class _MemberAvatar extends StatelessWidget {
  final _MemberStatus member;
  const _MemberAvatar({required this.member});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: member.hasCheckedIn
                    ? BonyanColors.emerald900
                    : BonyanColors.surface700,
                border: Border.all(
                  color: member.hasCheckedIn
                      ? BonyanColors.emerald500
                      : BonyanColors.surface500,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  member.name[0],
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: member.hasCheckedIn
                        ? BonyanColors.emerald400
                        : BonyanColors.grey400,
                  ),
                ),
              ),
            ),
            // Online indicator
            Positioned(
              bottom: 1, left: 1,
              child: Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: member.isOnline
                      ? BonyanColors.emerald500
                      : BonyanColors.grey600,
                  border: const Border.fromBorderSide(
                    BorderSide(color: BonyanColors.black, width: 2),
                  ),
                ),
              ),
            ),
            // Check mark if checked in
            if (member.hasCheckedIn)
              Positioned(
                top: -2, right: -2,
                child: Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: BonyanColors.emerald500,
                    border: const Border.fromBorderSide(
                      BorderSide(color: BonyanColors.black, width: 1.5),
                    ),
                  ),
                  child: const Center(
                    child: Text('✓',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: BonyanColors.black)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          member.name,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11,
            color: BonyanColors.grey400,
          ),
        ),
      ],
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final double score;
  const _ScoreBar({required this.score});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('النقاط الجماعية',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: BonyanColors.grey400)),
            const Spacer(),
            Text('${score.round()} / 100',
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: BonyanColors.white)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 100,
            backgroundColor: BonyanColors.surface600,
            valueColor: AlwaysStoppedAnimation(
              score >= 80
                  ? BonyanColors.emerald500
                  : score >= 50
                      ? BonyanColors.warning
                      : BonyanColors.error,
            ),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}
