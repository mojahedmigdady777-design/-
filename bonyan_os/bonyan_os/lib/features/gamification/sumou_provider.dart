// lib/features/gamification/sumou_provider.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║      بنيان OS — سُمُوّ: محرك التحفيز والاقتصاد             ║
// ║  Bonyan Coin · Dynamic Badges · School Cafeteria Store       ║
// ╚══════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logger/logger.dart';

import '../../core/network/event_bus.dart';
import '../../core/theme/bonyan_theme.dart';
import '../auth/master_auth_provider.dart';

part 'sumou_provider.freezed.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — BADGE DEFINITIONS
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class BonyanBadge with _$BonyanBadge {
  const factory BonyanBadge({
    required String badgeId,
    required String nameAr,
    required String descriptionAr,
    required String iconPath,
    required BadgeTier tier,
    required BadgeCategory category,
    // Earn conditions
    required int requiredStreak,     // Days of consecutive habit
    // Degradation rules
    @Default(3) int degradeAfterDays, // Badge warns after N missed days
    @Default(5) int revokeAfterDays,  // Badge removed after N missed days
    // Dynamic state (per-student, fetched separately)
    @Default(false) bool isEarned,
    @Default(false) bool isWarned,
    @Default(false) bool isRevoked,
    int? currentStreak,
    DateTime? earnedAt,
    DateTime? lastActivityAt,
  }) = _BonyanBadge;
}

enum BadgeCategory { prayer, academic, social, attendance, special }

// ─────────────────────────────────────────────────────────────────────────────
// ALL BADGE DEFINITIONS (static catalogue)
// ─────────────────────────────────────────────────────────────────────────────

class BadgeCatalogue {
  static const List<BonyanBadge> all = [
    // ── Prayer ──────────────────────────────────────────────────────────────
    BonyanBadge(
      badgeId: 'fajr_knight',
      nameAr: 'فارس الفجر',
      descriptionAr: 'صلّيت الفجر في وقتها 7 أيام متواصلة',
      iconPath: 'assets/icons/badges/fajr_knight.svg',
      tier: BadgeTier.gold,
      category: BadgeCategory.prayer,
      requiredStreak: 7,
      degradeAfterDays: 3,
      revokeAfterDays: 5,
    ),
    BonyanBadge(
      badgeId: 'prayers_guardian',
      nameAr: 'حارس الصلوات',
      descriptionAr: 'حافظت على الصلوات الخمس 30 يومًا',
      iconPath: 'assets/icons/badges/guardian.svg',
      tier: BadgeTier.diamond,
      category: BadgeCategory.prayer,
      requiredStreak: 30,
      degradeAfterDays: 2,
      revokeAfterDays: 4,
    ),
    BonyanBadge(
      badgeId: 'azkar_master',
      nameAr: 'حصن الأذكار',
      descriptionAr: 'أتممت أذكار الصباح والمساء 14 يومًا متواصلة',
      iconPath: 'assets/icons/badges/azkar.svg',
      tier: BadgeTier.silver,
      category: BadgeCategory.prayer,
      requiredStreak: 14,
      degradeAfterDays: 3,
      revokeAfterDays: 6,
    ),

    // ── Academic ─────────────────────────────────────────────────────────────
    BonyanBadge(
      badgeId: 'scholar',
      nameAr: 'طالب العلم',
      descriptionAr: 'حافظت على معدل 90% لمدة شهر',
      iconPath: 'assets/icons/badges/scholar.svg',
      tier: BadgeTier.gold,
      category: BadgeCategory.academic,
      requiredStreak: 30,
      degradeAfterDays: 7,
      revokeAfterDays: 14,
    ),
    BonyanBadge(
      badgeId: 'study_warrior',
      nameAr: 'محارب المذاكرة',
      descriptionAr: 'ذاكرت 60 دقيقة يوميًا لأسبوع كامل',
      iconPath: 'assets/icons/badges/warrior.svg',
      tier: BadgeTier.silver,
      category: BadgeCategory.academic,
      requiredStreak: 7,
      degradeAfterDays: 3,
      revokeAfterDays: 5,
    ),
    BonyanBadge(
      badgeId: 'quiz_champion',
      nameAr: 'بطل الاختبارات',
      descriptionAr: 'فزت بـ 5 مسابقات متتالية مع مجموعتك',
      iconPath: 'assets/icons/badges/champion.svg',
      tier: BadgeTier.legendary,
      category: BadgeCategory.academic,
      requiredStreak: 5,
      degradeAfterDays: 30, // Competition-based, degrades slowly
      revokeAfterDays: 60,
    ),

    // ── Social ───────────────────────────────────────────────────────────────
    BonyanBadge(
      badgeId: 'cell_anchor',
      nameAr: 'عماد الخلية',
      descriptionAr: 'كنت أول من يسجّل حضوره في مجموعتك 10 مرات',
      iconPath: 'assets/icons/badges/anchor.svg',
      tier: BadgeTier.bronze,
      category: BadgeCategory.social,
      requiredStreak: 10,
      degradeAfterDays: 7,
      revokeAfterDays: 14,
    ),
    BonyanBadge(
      badgeId: 'peer_mentor',
      nameAr: 'المرشد',
      descriptionAr: 'ساعدت زميلًا في المذاكرة 5 مرات',
      iconPath: 'assets/icons/badges/mentor.svg',
      tier: BadgeTier.gold,
      category: BadgeCategory.social,
      requiredStreak: 5,
      degradeAfterDays: 14,
      revokeAfterDays: 30,
    ),

    // ── Attendance ────────────────────────────────────────────────────────────
    BonyanBadge(
      badgeId: 'punctual',
      nameAr: 'دائم الحضور',
      descriptionAr: 'حضرت في الوقت المحدد 20 يومًا متواصلة',
      iconPath: 'assets/icons/badges/punctual.svg',
      tier: BadgeTier.diamond,
      category: BadgeCategory.attendance,
      requiredStreak: 20,
      degradeAfterDays: 2,
      revokeAfterDays: 3,
    ),
  ];

  static BonyanBadge? findById(String id) =>
      all.where((b) => b.badgeId == id).firstOrNull;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — STORE ITEM & TRANSACTION MODELS
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class StoreItem with _$StoreItem {
  const factory StoreItem({
    required String itemId,
    required String nameAr,
    required String descriptionAr,
    required int priceCoins,
    required StoreCategory category,
    @Default(true) bool isAvailable,
    int? stockRemaining,          // null = unlimited
    String? iconPath,
    String? partnerLogoPath,      // Cafeteria / partner branding
  }) = _StoreItem;
}

enum StoreCategory { cafeteria, digital, privilege, charity }

@freezed
class CoinTransaction with _$CoinTransaction {
  const factory CoinTransaction({
    required String txId,
    required String studentId,
    required int amount,           // Positive = earn, negative = spend
    required CoinSource source,
    required DateTime at,
    String? descriptionAr,
    String? relatedItemId,
  }) = _CoinTransaction;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — GAMIFICATION STATE
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class SumouState with _$SumouState {
  const factory SumouState({
    @Default(0) int coinBalance,
    @Default([]) List<BonyanBadge> earnedBadges,
    @Default([]) List<BonyanBadge> warnedBadges,   // About to degrade
    @Default([]) List<CoinTransaction> recentTxs,
    @Default([]) List<StoreItem> storeItems,
    @Default(false) bool isRedeeming,
    String? latestEarnMessageAr,
    String? errorAr,
  }) = _SumouState;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — SUMOU NOTIFIER
// ─────────────────────────────────────────────────────────────────────────────

class SumouNotifier extends AutoDisposeAsyncNotifier<SumouState> {
  final _logger = Logger();
  final _firestore = FirebaseFirestore.instance;

  // Mock cafeteria API endpoint
  late final Dio _cafeteriaApi;
  final _subscriptions = <StreamSubscription>[];

  @override
  Future<SumouState> build() async {
    _cafeteriaApi = Dio(BaseOptions(
      baseUrl: const String.fromEnvironment('CAFETERIA_API_URL',
          defaultValue: 'https://api.bonyan-school.sa/cafeteria/v1'),
      connectTimeout: const Duration(seconds: 10),
    ));

    final profile = ref.watch(currentProfileProvider);
    if (profile == null) return const SumouState();

    // Wire event bus reactions
    _wireBusReactions(profile.uid);

    // Load initial data
    final [balance, badges, items] = await Future.wait([
      _fetchBalance(profile.uid),
      _fetchBadges(profile.uid),
      _fetchStoreItems(),
    ]);

    ref.onDispose(() {
      for (final s in _subscriptions) s.cancel();
    });

    return SumouState(
      coinBalance: balance as int,
      earnedBadges: badges as List<BonyanBadge>,
      storeItems: items as List<StoreItem>,
    );
  }

  // ── EARN COINS ────────────────────────────────────────────────────────────
  Future<void> awardCoins(BonyanCoinEarnedEvent event) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;

    final uid = event.sourceUserId ?? profile.uid;
    final amount = event.amount;

    _logger.i('💰 Awarding $amount coins to $uid — ${event.source.name}');

    try {
      // Atomic increment in Firestore
      await _firestore.collection('students').doc(uid).update({
        'coinBalance': FieldValue.increment(amount),
      });

      // Log transaction
      await _firestore
          .collection('students')
          .doc(uid)
          .collection('coinTransactions')
          .add({
        'amount': amount,
        'source': event.source.name,
        'descriptionAr': event.reason ?? event.source.name,
        'at': FieldValue.serverTimestamp(),
      });

      final current = state.valueOrNull?.coinBalance ?? 0;
      state = AsyncData(state.valueOrNull?.copyWith(
            coinBalance: current + amount,
            latestEarnMessageAr: event.reason,
            recentTxs: [
              CoinTransaction(
                txId: DateTime.now().millisecondsSinceEpoch.toString(),
                studentId: uid,
                amount: amount,
                source: event.source,
                at: DateTime.now(),
                descriptionAr: event.reason,
              ),
              ...?state.valueOrNull?.recentTxs.take(19),
            ],
          ) ?? const SumouState());

      // Trigger haptics
      await BonyanHaptics.rewardPulse();

      // Check for badge unlocks after coin events
      await _evaluateBadgeProgress(uid, event.source);
    } catch (e) {
      _logger.e('❌ Coin award error: $e');
    }
  }

  // ── REDEEM IN STORE ───────────────────────────────────────────────────────
  Future<RedeemResult> redeemItem({
    required String itemId,
    required String studentId,
  }) async {
    final item = state.valueOrNull?.storeItems.firstWhere(
      (i) => i.itemId == itemId,
      orElse: () => const StoreItem(
        itemId: '', nameAr: '', descriptionAr: '',
        priceCoins: 999999, category: StoreCategory.cafeteria,
      ),
    );

    if (item == null || item.itemId.isEmpty) {
      return RedeemResult.failed(reasonAr: 'العنصر غير موجود');
    }

    final balance = state.valueOrNull?.coinBalance ?? 0;
    if (balance < item.priceCoins) {
      return RedeemResult.failed(
        reasonAr: 'رصيدك غير كافٍ. تحتاج ${item.priceCoins - balance} عملة إضافية',
      );
    }

    state = AsyncData(state.valueOrNull?.copyWith(isRedeeming: true) ?? const SumouState());

    try {
      // Call cafeteria API (mock)
      final apiResponse = await _cafeteriaApi.post('/redeem', data: {
        'studentId': studentId,
        'itemId': itemId,
        'coins': item.priceCoins,
      });

      final redemptionCode = apiResponse.data['code'] as String? ?? 'BNYN-${itemId.toUpperCase()}';

      // Deduct coins in Firestore
      await _firestore.collection('students').doc(studentId).update({
        'coinBalance': FieldValue.increment(-item.priceCoins),
      });

      final current = state.valueOrNull?.coinBalance ?? 0;
      state = AsyncData(state.valueOrNull?.copyWith(
            coinBalance: current - item.priceCoins,
            isRedeeming: false,
          ) ?? const SumouState());

      _logger.i('🛒 Redeemed ${item.nameAr} for ${item.priceCoins} coins');
      return RedeemResult.success(
        codeAr: redemptionCode,
        itemNameAr: item.nameAr,
      );
    } on DioException catch (e) {
      state = AsyncData(state.valueOrNull?.copyWith(isRedeeming: false) ?? const SumouState());
      _logger.e('❌ Cafeteria API error: ${e.message}');
      return RedeemResult.failed(reasonAr: 'فشل الاتصال بنظام المقصف. حاول لاحقًا');
    }
  }

  // ── BADGE DEGRADATION CHECK (called by background job daily) ─────────────
  Future<void> checkBadgeDegradation(String studentId) async {
    final badges = state.valueOrNull?.earnedBadges ?? [];
    final now = DateTime.now();

    final warned   = <BonyanBadge>[];
    final revoked  = <BonyanBadge>[];
    final stillOk  = <BonyanBadge>[];

    for (final badge in badges) {
      if (badge.lastActivityAt == null) {
        stillOk.add(badge);
        continue;
      }
      final daysSinceActivity = now.difference(badge.lastActivityAt!).inDays;

      if (daysSinceActivity >= badge.revokeAfterDays) {
        // Revoke badge
        revoked.add(badge.copyWith(isRevoked: true, isEarned: false));
        await _firestore
            .collection('students')
            .doc(studentId)
            .collection('badges')
            .doc(badge.badgeId)
            .update({'isRevoked': true, 'isEarned': false, 'revokedAt': FieldValue.serverTimestamp()});

        ref.read(bonyanEventBusProvider).fire(BadgeDegradedEvent(
          badgeId: badge.badgeId,
          badgeNameAr: badge.nameAr,
          missedDays: daysSinceActivity,
          isRevoked: true,
          timestamp: now,
          sourceUserId: studentId,
        ));

        _logger.w('⬇️ Badge REVOKED: ${badge.nameAr} after $daysSinceActivity days');
        await BonyanHaptics.errorPulse();
      } else if (daysSinceActivity >= badge.degradeAfterDays) {
        // Warn
        warned.add(badge.copyWith(isWarned: true));
        ref.read(bonyanEventBusProvider).fire(BadgeDegradedEvent(
          badgeId: badge.badgeId,
          badgeNameAr: badge.nameAr,
          missedDays: daysSinceActivity,
          isRevoked: false,
          timestamp: now,
          sourceUserId: studentId,
        ));
        _logger.i('⚠️ Badge WARNING: ${badge.nameAr}');
      } else {
        stillOk.add(badge);
      }
    }

    state = AsyncData(state.valueOrNull?.copyWith(
          earnedBadges: [...stillOk, ...warned],
          warnedBadges: warned,
        ) ?? const SumouState());
  }

  // ── PRIVATE: Wire Event Bus ───────────────────────────────────────────────
  void _wireBusReactions(String uid) {
    final bus = ref.read(bonyanEventBusProvider);

    // Auto-award coins when bus fires earn events
    _subscriptions.add(bus.on<BonyanCoinEarnedEvent>((e) {
      if (e.sourceUserId == uid || e.sourceUserId == null) {
        awardCoins(e);
      }
    }));

    // Badge earned event
    _subscriptions.add(bus.on<BadgeEarnedEvent>((e) {
      if (e.sourceUserId == uid) BonyanHaptics.achievementUnlocked();
    }));
  }

  // ── PRIVATE: Badge progress evaluation ───────────────────────────────────
  Future<void> _evaluateBadgeProgress(String uid, CoinSource source) async {
    // Map coin source to relevant badge categories
    final relevantCategory = switch (source) {
      CoinSource.prayerOnTime || CoinSource.azkarComplete => BadgeCategory.prayer,
      CoinSource.studyStreak || CoinSource.quizWin        => BadgeCategory.academic,
      CoinSource.earlyArrival                             => BadgeCategory.attendance,
      CoinSource.peerHelp                                 => BadgeCategory.social,
      _                                                   => null,
    };
    if (relevantCategory == null) return;

    // Fetch student's current streak for this category from Firestore
    final streakDoc = await _firestore
        .collection('students')
        .doc(uid)
        .collection('streaks')
        .doc(relevantCategory.name)
        .get();

    final currentStreak = streakDoc.data()?['count'] as int? ?? 0;

    // Check all badges in this category
    for (final badge in BadgeCatalogue.all.where((b) => b.category == relevantCategory)) {
      if (currentStreak >= badge.requiredStreak) {
        final alreadyEarned =
            state.valueOrNull?.earnedBadges.any((b) => b.badgeId == badge.badgeId) ?? false;
        if (!alreadyEarned) {
          await _grantBadge(uid, badge);
        }
      }
    }
  }

  Future<void> _grantBadge(String uid, BonyanBadge badge) async {
    _logger.i('🏅 Granting badge: ${badge.nameAr} to $uid');

    await _firestore
        .collection('students')
        .doc(uid)
        .collection('badges')
        .doc(badge.badgeId)
        .set({
      'badgeId': badge.badgeId,
      'isEarned': true,
      'isRevoked': false,
      'earnedAt': FieldValue.serverTimestamp(),
      'lastActivityAt': FieldValue.serverTimestamp(),
    });

    ref.read(bonyanEventBusProvider).fire(BadgeEarnedEvent(
      badgeId: badge.badgeId,
      badgeNameAr: badge.nameAr,
      iconPath: badge.iconPath,
      tier: badge.tier,
      timestamp: DateTime.now(),
      sourceUserId: uid,
    ));

    state = AsyncData(state.valueOrNull?.copyWith(
          earnedBadges: [
            ...?state.valueOrNull?.earnedBadges,
            badge.copyWith(isEarned: true, earnedAt: DateTime.now()),
          ],
        ) ?? const SumouState());
  }

  Future<int> _fetchBalance(String uid) async {
    final doc = await _firestore.collection('students').doc(uid).get();
    return doc.data()?['coinBalance'] as int? ?? 0;
  }

  Future<List<BonyanBadge>> _fetchBadges(String uid) async {
    final snap = await _firestore
        .collection('students')
        .doc(uid)
        .collection('badges')
        .where('isEarned', isEqualTo: true)
        .get();

    return snap.docs.map((doc) {
      final data = doc.data();
      final base = BadgeCatalogue.findById(doc.id);
      if (base == null) return null;
      return base.copyWith(
        isEarned: true,
        isRevoked: data['isRevoked'] as bool? ?? false,
        earnedAt: (data['earnedAt'] as Timestamp?)?.toDate(),
        lastActivityAt: (data['lastActivityAt'] as Timestamp?)?.toDate(),
      );
    }).whereType<BonyanBadge>().toList();
  }

  Future<List<StoreItem>> _fetchStoreItems() async {
    // In production: fetch from Firestore or cafeteria API
    return const [
      StoreItem(
        itemId: 'sandwich_meal',
        nameAr: 'وجبة سندويش + عصير',
        descriptionAr: 'استبدل عملاتك بوجبة من المقصف المدرسي',
        priceCoins: 150,
        category: StoreCategory.cafeteria,
        iconPath: 'assets/icons/store/sandwich.png',
      ),
      StoreItem(
        itemId: 'extra_break',
        nameAr: 'استراحة إضافية 15 دقيقة',
        descriptionAr: 'امتياز: استراحة إضافية بموافقة الإدارة',
        priceCoins: 300,
        category: StoreCategory.privilege,
      ),
      StoreItem(
        itemId: 'book_voucher',
        nameAr: 'قسيمة كتاب',
        descriptionAr: 'قسيمة لشراء كتاب من مكتبة المدرسة',
        priceCoins: 200,
        category: StoreCategory.digital,
      ),
      StoreItem(
        itemId: 'charity_meal',
        nameAr: 'تبرع بوجبة',
        descriptionAr: 'تبرّع بوجبة لطالب محتاج في مدرستك',
        priceCoins: 100,
        category: StoreCategory.charity,
      ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 5 — REDEEM RESULT
// ─────────────────────────────────────────────────────────────────────────────

class RedeemResult {
  final bool success;
  final String? codeAr;
  final String? itemNameAr;
  final String? reasonAr;

  const RedeemResult._({
    required this.success, this.codeAr, this.itemNameAr, this.reasonAr,
  });
  factory RedeemResult.success({required String codeAr, required String itemNameAr}) =>
      RedeemResult._(success: true, codeAr: codeAr, itemNameAr: itemNameAr);
  factory RedeemResult.failed({required String reasonAr}) =>
      RedeemResult._(success: false, reasonAr: reasonAr);
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 6 — PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final sumouProvider =
    AutoDisposeAsyncNotifierProvider<SumouNotifier, SumouState>(
  SumouNotifier.new,
);

final coinBalanceProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(sumouProvider).valueOrNull?.coinBalance ?? 0,
);

final earnedBadgesProvider = Provider.autoDispose<List<BonyanBadge>>(
  (ref) => ref.watch(sumouProvider).valueOrNull?.earnedBadges ?? [],
);

final warnedBadgesProvider = Provider.autoDispose<List<BonyanBadge>>(
  (ref) => ref.watch(sumouProvider).valueOrNull?.warnedBadges ?? [],
);

final storeItemsProvider =
    Provider.autoDispose.family<List<StoreItem>, StoreCategory?>((ref, category) {
  final items = ref.watch(sumouProvider).valueOrNull?.storeItems ?? [];
  if (category == null) return items;
  return items.where((i) => i.category == category).toList();
});

/// Live leaderboard stream — ordered by coinBalance desc
final leaderboardProvider =
    StreamProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, schoolId) {
    return FirebaseFirestore.instance
        .collection('students')
        .where('schoolId', isEqualTo: schoolId)
        .orderBy('coinBalance', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  },
);
