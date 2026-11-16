#!/usr/bin/env bash
# =============================================================================
#  بنيان OS — سكريبت البناء الكامل
#  build_apk.sh
#
#  الاستخدام:
#    chmod +x build_apk.sh
#    ./build_apk.sh
#
#  المتطلبات:
#    - Flutter SDK 3.22+ (stable channel)
#    - Android SDK (API 34) + Build Tools 34.0.0
#    - Java 17+
#    - firebase-tools (npm install -g firebase-tools)
# =============================================================================
set -e  # Stop on any error

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

step() { echo -e "\n${CYAN}${BOLD}▶ $1${RESET}"; }
ok()   { echo -e "${GREEN}✓ $1${RESET}"; }
warn() { echo -e "${YELLOW}⚠ $1${RESET}"; }
err()  { echo -e "${RED}✗ $1${RESET}"; exit 1; }

echo -e "${BOLD}"
cat << 'EOF'
 ╔══════════════════════════════════════╗
 ║     بنيان OS — Build Pipeline       ║
 ╚══════════════════════════════════════╝
EOF
echo -e "${RESET}"

# ── Step 0: Check prerequisites ──────────────────────────────────────────────
step "التحقق من البيئة"

command -v flutter >/dev/null 2>&1 || err "Flutter غير مثبت. ثبّته من https://flutter.dev"
command -v java    >/dev/null 2>&1 || err "Java غير مثبت. نسخة 17+ مطلوبة"

FLUTTER_VER=$(flutter --version 2>&1 | head -1)
JAVA_VER=$(java -version 2>&1 | head -1)
ok "Flutter: $FLUTTER_VER"
ok "Java: $JAVA_VER"

# ── Step 1: Firebase setup (one-time) ────────────────────────────────────────
step "إعداد Firebase"
if [ ! -f "lib/firebase_options.dart" ]; then
  warn "lib/firebase_options.dart غير موجود"
  echo "  نفّذ: flutterfire configure"
  echo "  ثم أعد تشغيل هذا السكريبت"
  exit 1
fi
ok "Firebase مُهيأ"

# ── Step 2: Check API keys ────────────────────────────────────────────────────
step "التحقق من مفاتيح API"
if [ -z "$GEMINI_API_KEY" ]; then
  warn "GEMINI_API_KEY غير معرّف. ميزات Mueen AI لن تعمل"
  echo "  export GEMINI_API_KEY=your_key_here"
fi
if [ -z "$AGORA_APP_ID" ]; then
  warn "AGORA_APP_ID غير معرّف. مكالمات VOIP لن تعمل"
fi

# ── Step 3: Install dependencies ─────────────────────────────────────────────
step "تثبيت حزم Flutter"
flutter pub get
ok "تم تثبيت الحزم"

# ── Step 4: Code generation (freezed, riverpod, etc.) ────────────────────────
step "توليد الكود (build_runner)"
dart run build_runner build --delete-conflicting-outputs
ok "تم توليد الكود"

# ── Step 5: Run tests ─────────────────────────────────────────────────────────
step "تشغيل الاختبارات"
if [ -d "test" ] && [ "$(ls -A test)" ]; then
  flutter test --coverage || warn "بعض الاختبارات فشلت — راجعها قبل النشر"
  ok "الاختبارات اكتملت"
else
  warn "لا توجد اختبارات بعد"
fi

# ── Step 6: Analyze ───────────────────────────────────────────────────────────
step "تحليل الكود"
flutter analyze --no-fatal-infos || warn "يوجد تحذيرات في الكود"
ok "التحليل اكتمل"

# ── Step 7: Build APK variants ───────────────────────────────────────────────
step "بناء APK"

# Debug APK (للتطوير والاختبار — بدون حاجة لـ keystore)
echo "  Building debug APK..."
flutter build apk \
  --debug \
  --dart-define=GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
  --dart-define=AGORA_APP_ID="${AGORA_APP_ID:-}" \
  --dart-define=CAFETERIA_API_URL="${CAFETERIA_API_URL:-https://api.bonyan-school.sa/cafeteria/v1}"

DEBUG_APK="build/app/outputs/flutter-apk/app-debug.apk"
if [ -f "$DEBUG_APK" ]; then
  SIZE=$(du -h "$DEBUG_APK" | cut -f1)
  ok "Debug APK جاهز: $DEBUG_APK ($SIZE)"
else
  err "فشل بناء Debug APK"
fi

# Release APK (للنشر — يحتاج keystore)
if [ -n "$KEYSTORE_PATH" ] && [ -f "$KEYSTORE_PATH" ]; then
  echo "  Building release APK (split by ABI)..."
  flutter build apk \
    --release \
    --split-per-abi \
    --dart-define=GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
    --dart-define=AGORA_APP_ID="${AGORA_APP_ID:-}" \
    --dart-define=CAFETERIA_API_URL="${CAFETERIA_API_URL:-}"

  echo ""
  echo -e "${GREEN}${BOLD}APK ملفات Release:${RESET}"
  for apk in build/app/outputs/flutter-apk/app-*-release.apk; do
    [ -f "$apk" ] && echo "  📦 $apk ($(du -h "$apk" | cut -f1))"
  done

  # Also build App Bundle for Play Store
  echo ""
  echo "  Building App Bundle (AAB) for Play Store..."
  flutter build appbundle \
    --release \
    --dart-define=GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
    --dart-define=AGORA_APP_ID="${AGORA_APP_ID:-}"

  AAB="build/app/outputs/bundle/release/app-release.aab"
  [ -f "$AAB" ] && ok "App Bundle: $AAB ($(du -h "$AAB" | cut -f1))"
else
  warn "KEYSTORE_PATH غير معرّف — تم بناء Debug فقط"
  echo "  لبناء Release APK:"
  echo "    export KEYSTORE_PATH=/path/to/bonyan.jks"
  echo "    export KEYSTORE_PASSWORD=your_password"
  echo "    export KEY_ALIAS=bonyan"
  echo "    export KEY_PASSWORD=your_key_password"
  echo "    ./build_apk.sh"
fi

# ── Step 8: Deploy Cloud Functions (optional) ────────────────────────────────
step "نشر Cloud Functions (اختياري)"
if command -v firebase >/dev/null 2>&1 && [ -d "functions" ]; then
  read -p "  هل تريد نشر Cloud Functions الآن؟ [y/N] " deploy_fn
  if [ "$deploy_fn" = "y" ] || [ "$deploy_fn" = "Y" ]; then
    cd functions && npm install && cd ..
    firebase deploy --only functions
    ok "Cloud Functions نُشرت بنجاح"
  fi
else
  warn "firebase-tools غير مثبت أو مجلد functions غير موجود"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}"
cat << 'EOF'
 ╔══════════════════════════════════════╗
 ║     ✅ البناء اكتمل بنجاح          ║
 ╚══════════════════════════════════════╝
EOF
echo -e "${RESET}"
echo "  📱 Debug APK:  build/app/outputs/flutter-apk/app-debug.apk"
echo "  📲 تثبيت فوري: flutter install"
echo ""
echo "  بنيان OS — حفظ الله طلاب العلم 🤲"
