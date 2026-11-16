// lib/features/gamification/store_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/bonyan_theme.dart';
import '../auth/master_auth_provider.dart';
import 'sumou_provider.dart';

class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});
  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _categories = [
    (label: 'الكل', cat: null),
    (label: '🍔 المقصف', cat: StoreCategory.cafeteria),
    (label: '⭐ امتيازات', cat: StoreCategory.privilege),
    (label: '📚 تعليمي', cat: StoreCategory.digital),
    (label: '🤲 تبرع', cat: StoreCategory.charity),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(coinBalanceProvider);
    final profile = ref.watch(currentProfileProvider);

    return Scaffold(
      backgroundColor: BonyanColors.black,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: BonyanColors.black,
            title: const Text('متجر سُمُوّ', style: TextStyle(
              fontFamily: 'Cairo', fontSize: 20, fontWeight: FontWeight.w800,
              color: BonyanColors.white)),
            actions: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: _CoinDisplay(balance: balance)),
            ],
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: BonyanColors.emerald500,
              labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo'),
              tabs: _categories.map((c) => Tab(text: c.label)).toList(),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: _categories.map((c) => _StoreGrid(
            category: c.cat,
            studentId: profile?.uid ?? '',
          )).toList(),
        ),
      ),
    );
  }
}

class _CoinDisplay extends StatelessWidget {
  final int balance;
  const _CoinDisplay({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BonyanRadius.full),
        gradient: BonyanGradients.coinShimmer,
        boxShadow: [BoxShadow(color: BonyanColors.goldAccent.withOpacity(0.35), blurRadius: 12)]),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('🪙', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Text(balance.toString(), style: const TextStyle(
          fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.w800,
          color: BonyanColors.black)),
      ]));
  }
}

class _StoreGrid extends ConsumerWidget {
  final StoreCategory? category;
  final String studentId;
  const _StoreGrid({required this.category, required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(storeItemsProvider(category));
    final balance = ref.watch(coinBalanceProvider);

    if (items.isEmpty) {
      return const Center(child: Text('لا توجد عناصر في هذه الفئة',
        style: TextStyle(fontFamily: 'Cairo', color: BonyanColors.grey400)));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: 0.85),
      itemCount: items.length,
      itemBuilder: (ctx, i) => _StoreCard(
        item: items[i],
        canAfford: balance >= items[i].priceCoins,
        onRedeem: () => _redeem(ctx, ref, items[i]),
      ).animate(delay: Duration(milliseconds: i * 80)).fadeIn().slideY(begin: 0.1),
    );
  }

  Future<void> _redeem(BuildContext ctx, WidgetRef ref, StoreItem item) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: BonyanColors.surface700,
        title: Text('تأكيد الاستبدال', style: const TextStyle(
          fontFamily: 'Cairo', fontWeight: FontWeight.w700, color: BonyanColors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(item.nameAr, style: const TextStyle(
            fontFamily: 'Cairo', fontSize: 16, color: BonyanColors.white)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🪙', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 4),
            Text('${item.priceCoins} عملة', style: const TextStyle(
              fontFamily: 'Cairo', fontWeight: FontWeight.w700, color: BonyanColors.goldAccent,
              fontSize: 16)),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: BonyanColors.grey400))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استبدل', style: TextStyle(fontFamily: 'Cairo'))),
        ],
      ),
    );

    if (confirm != true || !ctx.mounted) return;

    final result = await ref.read(sumouProvider.notifier).redeemItem(
      itemId: item.itemId, studentId: studentId);

    if (!ctx.mounted) return;

    if (result.success) {
      await BonyanHaptics.achievementUnlocked();
      showDialog(
        context: ctx,
        builder: (_) => AlertDialog(
          backgroundColor: BonyanColors.surface700,
          title: const Text('🎉 تم الاستبدال!', style: TextStyle(
            fontFamily: 'Cairo', color: BonyanColors.emerald400, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(result.itemNameAr ?? '', style: const TextStyle(
              fontFamily: 'Cairo', color: BonyanColors.white, fontSize: 15)),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: BonyanColors.surface800,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BonyanColors.emerald500)),
              child: Text(result.codeAr ?? '', style: const TextStyle(
                fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.w800,
                color: BonyanColors.emerald400, letterSpacing: 2))),
            const SizedBox(height: 8),
            const Text('أرِ هذا الرمز لموظف المقصف', style: TextStyle(
              fontFamily: 'Cairo', fontSize: 12, color: BonyanColors.grey400)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('حسنًا', style: TextStyle(fontFamily: 'Cairo')))],
        ),
      );
    } else {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(result.reasonAr ?? 'خطأ', style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: BonyanColors.error, behavior: SnackBarBehavior.floating));
    }
  }
}

class _StoreCard extends StatelessWidget {
  final StoreItem item;
  final bool canAfford;
  final VoidCallback onRedeem;
  const _StoreCard({required this.item, required this.canAfford, required this.onRedeem});

  @override
  Widget build(BuildContext context) {
    final catEmoji = switch (item.category) {
      StoreCategory.cafeteria  => '🍔',
      StoreCategory.privilege  => '⭐',
      StoreCategory.digital    => '📚',
      StoreCategory.charity    => '🤲',
    };

    return Container(
      decoration: BoxDecoration(
        color: BonyanColors.surface900,
        borderRadius: BorderRadius.circular(BonyanRadius.lg),
        border: Border.all(
          color: canAfford ? BonyanColors.surface500 : BonyanColors.surface600,
          width: 1.5),
        boxShadow: canAfford ? BonyanShadow.cardDark : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Icon area
        Container(
          width: double.infinity, height: 90,
          decoration: BoxDecoration(
            color: BonyanColors.surface800,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(BonyanRadius.lg)),
            gradient: canAfford ? LinearGradient(colors: [
              BonyanColors.emerald900.withOpacity(0.5), BonyanColors.surface800]) : null),
          child: Center(child: Text(catEmoji, style: const TextStyle(fontSize: 40)))),

        Padding(padding: const EdgeInsets.all(10), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.nameAr, style: TextStyle(
            fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w700,
            color: canAfford ? BonyanColors.white : BonyanColors.grey400),
            maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              const Text('🪙', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 3),
              Text(item.priceCoins.toString(), style: TextStyle(
                fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w800,
                color: canAfford ? BonyanColors.goldAccent : BonyanColors.grey600)),
            ]),
            GestureDetector(
              onTap: canAfford ? onRedeem : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: canAfford
                      ? BonyanColors.emerald500
                      : BonyanColors.surface600,
                  borderRadius: BorderRadius.circular(BonyanRadius.full)),
                child: Text(canAfford ? 'استبدل' : 'لا يكفي',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: canAfford ? BonyanColors.black : BonyanColors.grey600)))),
          ]),
        ])),
      ]),
    );
  }
}
