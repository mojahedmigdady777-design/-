// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/admin_dashboard_screen.dart';
import '../../features/ai/mueen_ai_provider.dart';
import '../../features/ai/rescue_plan_screen.dart';
import '../../features/alarm/alarm_screen.dart';
import '../../features/alarm/logic/cascade_alarm_engine.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/master_auth_provider.dart';
import '../../features/gamification/store_screen.dart';
import '../../features/home/student_home_screen.dart';
import '../../features/quiz/cell_quiz_screen.dart';

class Routes {
  static const login          = '/login';
  static const home           = '/';
  static const alarm          = '/alarm';
  static const quiz           = '/cell-quiz/:sessionId';
  static const rescuePlan     = '/rescue-plan/:planId';
  static const store          = '/store';
  static const adminDashboard = '/admin';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.login,
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final authState = ref.read(bonyanAuthProvider).valueOrNull;
      final isLoggedIn = authState?.maybeWhen(
            authenticated: (_, __) => true, orElse: () => false) ?? false;
      final onLogin = state.matchedLocation == Routes.login;

      if (!isLoggedIn && !onLogin) return Routes.login;
      if (isLoggedIn && onLogin) {
        final role = ref.read(currentRoleProvider);
        return role.canAccessAdminDashboard ? Routes.adminDashboard : Routes.home;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.login,
          pageBuilder: (_, s) => _fade(const LoginScreen(), s)),
      GoRoute(path: Routes.home,
          pageBuilder: (_, s) => _fade(const StudentHomeScreen(), s)),
      GoRoute(path: Routes.alarm, pageBuilder: (ctx, s) {
        final ex = s.extra as Map<String, dynamic>? ?? {};
        return _fade(AlarmScreen(
          cellId:    ex['cellId']    as String? ?? '',
          alarmId:   ex['alarmId']   as String? ?? '',
          labelAr:   ex['labelAr']   as String? ?? 'تنبيه',
          alarmType: ex['alarmType'] as AlarmType? ?? AlarmType.fajr,
        ), s);
      }),
      GoRoute(path: Routes.quiz, pageBuilder: (ctx, s) {
        final ex = s.extra as Map<String, dynamic>? ?? {};
        return _slide(CellQuizScreen(
          quizSessionId: s.pathParameters['sessionId'] ?? '',
          subjectNameAr: ex['subjectNameAr'] as String? ?? 'اختبار',
          questions: (ex['questions'] as List?)?.cast<McqQuestion>() ?? [],
        ), s);
      }),
      GoRoute(path: Routes.rescuePlan,
          pageBuilder: (ctx, s) => _slide(
              RescuePlanScreen(planId: s.pathParameters['planId'] ?? ''), s)),
      GoRoute(path: Routes.store,
          pageBuilder: (_, s) => _slide(const StoreScreen(), s)),
      GoRoute(
        path: Routes.adminDashboard,
        redirect: (ctx, s) => ref.read(currentRoleProvider).canAccessAdminDashboard
            ? null : Routes.home,
        pageBuilder: (_, s) => _fade(const AdminDashboardScreen(), s)),
    ],
    errorBuilder: (_, s) => Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: Text('404 — ${s.error}',
          style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)))),
  );
});

CustomTransitionPage<void> _fade(Widget child, GoRouterState s) =>
    CustomTransitionPage(key: s.pageKey, child: child,
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c));

CustomTransitionPage<void> _slide(Widget child, GoRouterState s) =>
    CustomTransitionPage(key: s.pageKey, child: child,
        transitionsBuilder: (_, a, __, c) => SlideTransition(
            position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeOutCubic)).animate(a),
            child: c));

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(bonyanAuthProvider, (_, __) => notifyListeners());
  }
}
