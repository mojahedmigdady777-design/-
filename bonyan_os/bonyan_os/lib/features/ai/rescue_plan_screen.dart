// lib/features/ai/rescue_plan_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/bonyan_theme.dart';
import 'mueen_ai_provider.dart';

class RescuePlanScreen extends ConsumerWidget {
  final String planId;
  const RescuePlanScreen({super.key, required this.planId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(activeRescuePlansProvider);
    final plan = plans.where((p) => p.planId == planId).firstOrNull;

    if (plan == null) {
      return const Scaffold(backgroundColor: BonyanColors.black,
        body: Center(child: CircularProgressIndicator(color: BonyanColors.emerald500)));
    }

    return Scaffold(
      backgroundColor: BonyanColors.black,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: BonyanColors.black,
          title: Text(plan.subjectNameAr, style: const TextStyle(
            fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.w700,
            color: BonyanColors.white)),
          actions: [
            Container(margin: const EdgeInsets.only(left: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: BonyanColors.error.withOpacity(0.15),
                borderRadius: BorderRadius.circular(BonyanRadius.full),
                border: Border.all(color: BonyanColors.error)),
              child: const Text('خطة إنقاذ', style: TextStyle(
                fontFamily: 'Cairo', fontSize: 11, color: BonyanColors.error,
                fontWeight: FontWeight.w700))),
          ],
        ),

        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(delegate: SliverChildListDelegate([

            // Motivational message
            if (plan.motivationalMessageAr != null) ...[
              Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    BonyanColors.emerald900.withOpacity(0.6), BonyanColors.surface800]),
                  borderRadius: BorderRadius.circular(BonyanRadius.lg),
                  border: Border.all(color: BonyanColors.emerald700)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('💬', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(plan.motivationalMessageAr!,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 14,
                      color: BonyanColors.white, height: 1.7))),
                ])).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 20),
            ],

            // Stats row
            Row(children: [
              _StatCard('⏱️', '${plan.dailyMinutes} دقيقة', 'يوميًا', BonyanColors.emerald500),
              const SizedBox(width: 10),
              _StatCard('📅', '${plan.estimatedDays} يوم', 'تقديري', BonyanColors.info),
              const SizedBox(width: 10),
              _StatCard('📝', '${plan.topics.length}', 'مواضيع', BonyanColors.warning),
            ]).animate().fadeIn(delay: 150.ms),

            const SizedBox(height: 24),

            const Text('المواضيع حسب الأولوية', style: TextStyle(
              fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.w700,
              color: BonyanColors.white)),
            const SizedBox(height: 12),

            // Topics
            ...plan.topics.asMap().entries.map((e) {
              final t = e.value;
              return _TopicCard(topic: t, index: e.key)
                  .animate(delay: Duration(milliseconds: 200 + e.key * 80))
                  .fadeIn().slideX(begin: 0.1);
            }),

            const SizedBox(height: 80),
          ])),
        ),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String icon, value, label;
  final Color color;
  const _StatCard(this.icon, this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: BonyanColors.surface900,
        borderRadius: BorderRadius.circular(BonyanRadius.md),
        border: Border.all(color: BonyanColors.surface500)),
      child: Column(children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontFamily: 'Cairo', fontSize: 16,
          fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 10,
          color: BonyanColors.grey400)),
      ])));
  }
}

class _TopicCard extends ConsumerStatefulWidget {
  final RescueTopic topic;
  final int index;
  const _TopicCard({required this.topic, required this.index});

  @override
  ConsumerState<_TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends ConsumerState<_TopicCard> {
  bool _expanded = false;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.topic;
    final (priorityLabel, priorityColor) = switch (t.priority) {
      TopicPriority.critical => ('🔴 حرج', BonyanColors.error),
      TopicPriority.high     => ('🟠 عالي', BonyanColors.warning),
      TopicPriority.medium   => ('🟡 متوسط', const Color(0xFFEAB308)),
      TopicPriority.low      => ('🟢 منخفض', BonyanColors.emerald500),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _done ? BonyanColors.emerald900.withOpacity(0.3) : BonyanColors.surface800,
        borderRadius: BorderRadius.circular(BonyanRadius.md),
        border: Border.all(color: _done ? BonyanColors.emerald700 : BonyanColors.surface500)),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(BonyanRadius.md),
          child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            // Checkbox
            GestureDetector(
              onTap: () => setState(() { _done = !_done; BonyanHaptics.rewardPulse(); }),
              child: AnimatedContainer(duration: 300.ms,
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _done ? BonyanColors.emerald500 : BonyanColors.surface600,
                  border: Border.all(color: _done
                      ? BonyanColors.emerald500 : BonyanColors.surface500)),
                child: _done ? const Icon(Icons.check, size: 16, color: Colors.white) : null)),
            const SizedBox(width: 12),

            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.titleAr, style: TextStyle(
                fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w700,
                color: _done ? BonyanColors.grey400 : BonyanColors.white,
                decoration: _done ? TextDecoration.lineThrough : null)),
              const SizedBox(height: 4),
              Row(children: [
                Text(priorityLabel, style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 11, color: priorityColor)),
                const SizedBox(width: 8),
                Text('⏱ ${t.estimatedMinutes} دقيقة', style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 11, color: BonyanColors.grey400)),
              ]),
            ])),

            Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                color: BonyanColors.grey400, size: 20),
          ])),
        ),

        if (_expanded) Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Text(t.descriptionAr, style: const TextStyle(
            fontFamily: 'Cairo', fontSize: 13, color: BonyanColors.grey300, height: 1.7))
          .animate().fadeIn(duration: 250.ms).slideY(begin: -0.1)),
      ]),
    );
  }
}
