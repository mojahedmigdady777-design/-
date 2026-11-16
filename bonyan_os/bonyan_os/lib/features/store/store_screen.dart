// lib/features/store/store_screen.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║      بنيان OS — متجر سُمُوّ                                 ║
// ║  Bonyan Coins · Cafeteria · Badges Showcase                 ║
// ╚══════════════════════════════════════════════════════════════╝

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/bonyan_theme.dart';
import '../auth/master_auth_provider.dart';
import '../gamification/sumou_provider.dart';

class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});
  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  static const _categories = [
    (label: 'الكل',      cat: null),
    (label: 'المقصف',    cat: StoreCategory.cafeteria),
    (label: 'امتيازات',  cat: StoreCategory.privilege),
    (label: 'رقمية',     cat: StoreCategory.digital),
    (label: 'تبرعات',    cat: StoreCategory.charity),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(coinBalanceProvider);
    final badges  = ref.watch(earnedBadgesProvider);

    return Scaffold(
      backgroundColor: BonyanColors.black,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: BonyanColors.black,
            expandedHeight: 160,
            flexibleSpace: FlexibleSpaceBar(
              background: _StoreHeader(balance: balance),
              collapseMode: CollapseMode.pin,
            ),
            title: const Text('متجر سُمُوّ',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 20,
                    fontWeight: FontWeight.w800, color: BonyanColors.white)),
            bottom: TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              indicatorColor: BonyanColors.emerald500,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontFamily: 'Cairo',
                  fontSize: 13, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 13),
              labelColor: BonyanColors.emerald500,
              unselectedLabelColor: BonyanColors.grey400,
              tabs: _categories.map((c) => Tab(text: c.label)).toList(),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: _categories.map((c) =>
              _StoreGrid(category: c.cat, balance: balance)
          ).toList(),
        ),
      ),
    );
  }
}

class _StoreHeader extends StatelessWidget {
  final int balance;
  const _StoreHeader({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 16),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('رصيدك الحالي',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 13,
                      color: BonyanColors.grey400)),
              const SizedBox(height: 4),
              Row(children: [
                const Text('🪙', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 8),
                Text(
                  balance.toString(),
                  style: const TextStyle(
                    fontFamily: 'Cairo', fontSize: 36,
                    fontWeight: FontWeight.w900, color: BonyanColors.goldAccent,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('عملة بنيان',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 14,
                        color: BonyanColors.grey400)),
              ]),
            ],
          ),
        ],
      ),
    );
  }
}

class _StoreGrid extends ConsumerWidget {
  final StoreCategory? category;
  final int balance;
  const _StoreGrid({required this.category, required this.balance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(storeItemsProvider(category));
    final profile = ref.watch(currentProfileProvider);

    if (items.isEmpty) {
      return const Center(
        child: Text('لا توجد عناصر في هذا القسم',
            style: TextStyle(fontFamily: 'Cairo', color: BonyanColors.grey400)));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.78,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) => _StoreItemCard(
        item: items[i],
        balance: balance,
        onRedeem: profile == null ? null : () async {
          await BonyanHaptics.softConfirm();
          final result = await ref.read(sumouProvider.notifier).redeemItem(
            itemId: items[i].itemId,
            studentId: profile.uid,
          );
          if (!ctx.mounted) return;
          _showRedeemResult(ctx, result);
        },
      ).animate(delay: Duration(milliseconds: i * 60)).fadeIn().slideY(begin: 0.1),
    );
  }

  void _showRedeemResult(BuildContext context, RedeemResult result) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        result.success
            ? '✅ تم الاسترداد! كود: ${result.codeAr}'
            : '❌ ${result.reasonAr}',
        style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
      ),
      backgroundColor: result.success
          ? BonyanColors.emerald700 : BonyanColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}

class _StoreItemCard extends StatelessWidget {
  final StoreItem item;
  final int balance;
  final VoidCallback? onRedeem;

  const _StoreItemCard({
    required this.item,
    required this.balance,
    required this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    final canAfford = balance >= item.priceCoins;
    final catIcon = switch (item.category) {
      StoreCategory.cafeteria  => '🥪',
      StoreCategory.privilege  => '⭐',
      StoreCategory.digital    => '📱',
      StoreCategory.charity    => '🤲',
    };

    return Container(
      decoration: BoxDecoration(
        color: BonyanColors.surface900,
        borderRadius: BorderRadius.circular(BonyanRadius.lg),
        border: Border.all(
          color: canAfford
              ? BonyanColors.emerald700
              : BonyanColors.surface500,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Icon area
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: BonyanColors.surface800,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(BonyanRadius.lg)),
              ),
              child: Center(
                child: Text(catIcon, style: const TextStyle(fontSize: 44)),
              ),
            ),
          ),

          // Info
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nameAr,
                    style: const TextStyle(
                      fontFamily: 'Cairo', fontSize: 13,
                      fontWeight: FontWeight.w700, color: BonyanColors.white,
                    ),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  const Text('🪙', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 3),
                  Text(
                    item.priceCoins.toString(),
                    style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: canAfford
                          ? BonyanColors.goldAccent
                          : BonyanColors.grey400,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: ElevatedButton(
                    onPressed: canAfford ? onRedeem : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canAfford
                          ? BonyanColors.emerald600
                          : BonyanColors.surface600,
                      foregroundColor: BonyanColors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      canAfford ? 'استرداد' : 'رصيد غير كافٍ',
                      style: const TextStyle(
                          fontFamily: 'Cairo', fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
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
