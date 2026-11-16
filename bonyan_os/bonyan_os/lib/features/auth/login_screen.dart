// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/theme/bonyan_theme.dart';
import 'master_auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _formKey      = GlobalKey<FormState>();
  bool _obscure = true, _loading = false;
  late final AnimationController _bgCtrl;
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(vsync: this, duration: 6.seconds)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _emailCtrl.dispose(); _passCtrl.dispose(); _bgCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    FocusScope.of(context).unfocus();
    await ref.read(bonyanAuthProvider.notifier).signInWithEmailAndPassword(
      email: _emailCtrl.text.trim(), password: _passCtrl.text);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _biometric() async {
    final ok = await _localAuth.authenticate(
      localizedReason: 'استخدم بصمتك لتسجيل الدخول',
      options: const AuthenticationOptions(biometricOnly: true),
    );
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم التحقق بنجاح ✅', style: TextStyle(fontFamily: 'Cairo'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(bonyanAuthProvider, (_, next) {
      next.whenData((s) => s.maybeWhen(
        error: (msg, _) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
              backgroundColor: BonyanColors.error, behavior: SnackBarBehavior.floating)),
        orElse: () {}));
    });

    return Scaffold(
      backgroundColor: BonyanColors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        // Animated emerald glows
        AnimatedBuilder(animation: _bgCtrl, builder: (_, __) => Stack(children: [
          Positioned(top: -100 + _bgCtrl.value * 30, right: -80,
            child: Container(width: 320, height: 320,
              decoration: BoxDecoration(shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  BonyanColors.emerald500.withOpacity(0.14 + _bgCtrl.value * 0.06),
                  Colors.transparent])))),
          Positioned(bottom: -60 + _bgCtrl.value * 20, left: -60,
            child: Container(width: 200, height: 200,
              decoration: BoxDecoration(shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  BonyanColors.emerald700.withOpacity(0.10), Colors.transparent])))),
        ])),

        SafeArea(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(key: _formKey, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),

              // Logo
              Center(child: Column(children: [
                Container(width: 88, height: 88,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: BonyanGradients.emerald, boxShadow: BonyanShadow.emeraldGlow),
                  child: const Center(child: Text('🕌', style: TextStyle(fontSize: 42))))
                  .animate().scale(duration: 600.ms, curve: Curves.elasticOut),
                const SizedBox(height: 20),
                ShaderMask(
                  shaderCallback: (b) => BonyanGradients.emerald.createShader(b),
                  child: const Text('بنيان', style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 52, fontWeight: FontWeight.w900,
                    color: Colors.white, letterSpacing: -1)))
                  .animate().fadeIn(delay: 200.ms).slideY(begin: 0.3),
                const SizedBox(height: 6),
                const Text('المنظومة التعليمية المتكاملة', style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 14, color: BonyanColors.grey400))
                  .animate().fadeIn(delay: 350.ms),
              ])),

              const SizedBox(height: 52),

              // Email
              const Text('البريد الإلكتروني', style: TextStyle(
                fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600,
                color: BonyanColors.grey400)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontFamily: 'Cairo', color: BonyanColors.white),
                decoration: const InputDecoration(
                  hintText: 'student@school.sa',
                  prefixIcon: Icon(Icons.email_outlined, color: BonyanColors.grey400, size: 20)),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'أدخل بريدك الإلكتروني'
                    : (!v!.contains('@') ? 'بريد غير صالح' : null),
              ).animate().fadeIn(delay: 400.ms).slideX(begin: 0.1),

              const SizedBox(height: 18),

              // Password
              const Text('كلمة المرور', style: TextStyle(
                fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600,
                color: BonyanColors.grey400)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscure,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontFamily: 'Cairo', color: BonyanColors.white),
                decoration: InputDecoration(
                  hintText: '••••••••',
                  prefixIcon: const Icon(Icons.lock_outline, color: BonyanColors.grey400, size: 20),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: BonyanColors.grey400, size: 20))),
                validator: (v) => (v?.isEmpty ?? true) ? 'أدخل كلمة المرور'
                    : (v!.length < 6 ? 'كلمة المرور قصيرة جدًا' : null),
              ).animate().fadeIn(delay: 500.ms).slideX(begin: 0.1),

              const SizedBox(height: 32),

              // Sign in
              SizedBox(width: double.infinity, height: 56,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signIn,
                  child: _loading
                      ? const SizedBox(width: 24, height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('تسجيل الدخول', style: TextStyle(
                          fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.w700)),
                )).animate().fadeIn(delay: 600.ms),

              const SizedBox(height: 14),

              // Biometric
              SizedBox(width: double.infinity, height: 52,
                child: OutlinedButton.icon(
                  onPressed: _biometric,
                  icon: const Icon(Icons.fingerprint, color: BonyanColors.emerald500, size: 22),
                  label: const Text('الدخول بالبصمة', style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 15, color: BonyanColors.emerald500)),
                )).animate().fadeIn(delay: 700.ms),

              const SizedBox(height: 24),
              Center(child: TextButton(
                onPressed: () {},
                child: const Text('نسيت كلمة المرور؟', style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 13, color: BonyanColors.grey400)))),

              const SizedBox(height: 40),
              Center(child: Text('بنيان OS v1.0.0', style: TextStyle(
                fontFamily: 'Cairo', fontSize: 11, color: BonyanColors.surface500))),
              const SizedBox(height: 20),
            ],
          )),
        )),
      ]),
    );
  }
}
