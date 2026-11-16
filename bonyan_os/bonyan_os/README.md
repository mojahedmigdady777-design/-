# بنيان OS — المنظومة التعليمية المتكاملة

> **المنظومة التعليمية الذكية** — Flutter · Firebase · Gemini AI · Riverpod

---

## 🗂️ هيكل المشروع الكامل

```
bonyan_os/
├── pubspec.yaml                          ← 50+ حزمة مُختارة
├── firestore.rules                       ← قواعد الأمان الكاملة
├── functions/
│   └── src/index.ts                     ← 7 Cloud Functions
└── lib/
    ├── main.dart                         ← نقطة الانطلاق + تهيئة EventBus
    ├── core/
    │   ├── network/event_bus.dart        ← المحور المركزي للأحداث (26 نوع حدث)
    │   └── theme/bonyan_theme.dart       ← نظام التصميم Namaa 2.0
    └── features/
        ├── auth/
        │   └── master_auth_provider.dart ← RBAC + Firebase Custom Claims
        ├── alarm/
        │   ├── logic/cascade_alarm_engine.dart ← محرك تنبيه الخلية
        │   └── alarm_screen.dart         ← شاشة تنبيه الفجر الكاملة
        ├── ai/
        │   └── mueen_ai_provider.dart    ← معين: تحليل + خطط إنقاذ + MCQ
        ├── attendance/
        │   └── smart_attendance_provider.dart ← QR + Geofence (100م)
        ├── gamification/
        │   └── sumou_provider.dart       ← عملة بنيان + شارات ديناميكية + متجر
        ├── prayer/
        │   └── prayer_heatmap_provider.dart ← خريطة حرارة 90 يومًا
        ├── admin/
        │   ├── admin_dashboard_provider.dart ← تحليلات + جدول حي
        │   └── admin_dashboard_screen.dart  ← واجهة المشرف
        ├── quiz/
        │   └── cell_quiz_screen.dart    ← مسابقة الخلية التنافسية
        └── home/
            ├── student_home_screen.dart  ← الشاشة الرئيسية
            └── widgets/
                ├── cell_status_widget.dart
                └── home_widgets.dart     ← Mueen card + Prayer ring + Stats
```

---

## ⚡ شبكة التفاعل بين الوحدات (EventBus)

```
صلاة في وقتها     → BonyanCoinEarnedEvent (+15 عملة)
أذكار مكتملة      → BonyanCoinEarnedEvent (+10 عملة)
تراجع الدرجات     → MueenMessageReadyEvent + RescuePlanGeneratedEvent
صلاة فائتة (×2)   → MueenMessageReadyEvent (رسالة دعم)
جلسة مذاكرة       → BonyanCoinEarnedEvent (متناسب مع الوقت)
فجر فائت في خلية  → VoipCallInitiatedEvent → Agora VOIP
محاضرة مسجلة      → LectureTranscribedEvent → Quiz + عملات
حضور مبكر         → BonyanCoinEarnedEvent (+20 عملة)
```

---

## 🔐 نموذج الأمان

| طبقة          | التقنية                               |
|---------------|---------------------------------------|
| المصادقة       | Firebase Auth + Custom Claims (JWT)   |
| رفع الصلاحيات  | Cloud Function + TOTP + Secret Manager |
| بيانات الطلاب  | AES-256 + Firestore Rules (least-privilege) |
| رمز Agora     | يُولَّد من الخادم فقط (Cloud Function)  |
| تدقيق الإدارة  | كل محاولة مُسجَّلة في `adminElevationAudit` |

---

## 🎮 اقتصاد عملة بنيان

| الفعل                    | العملات |
|--------------------------|---------|
| صلاة في وقتها            | +15     |
| أذكار مكتملة             | +10     |
| حضور مبكر (Geofence ✓)  | +20     |
| مذاكرة 15 دقيقة          | +2      |
| مذاكرة بمساعدة AI        | +4 (×2) |
| مساعدة زميل              | +15     |
| فوز في مسابقة الخلية     | حتى +50  |
| تسجيل محاضرة             | +25     |

---

## 🏅 الشارات الديناميكية

كل شارة لها عداد انتظام. عند التوقف:
- **بعد N يوم** → تحذير FCM
- **بعد M يوم** → سحب الشارة نهائيًا
- العودة للانتظام → يمكن اكتساب الشارة من جديد

---

## ☁️ Cloud Functions (7 وظائف)

1. `requestSuperAdminElevation` — رفع صلاحيات آمن (TOTP + Secret Manager)
2. `dailyBadgeDegradation` — فحص الشارات يوميًا 3 صباحًا
3. `generateAgoraToken` — رمز VOIP من الخادم فقط
4. `onCellAlarmEscalation` — إشعار FCM المتسلسل عند فوات الفجر
5. `onParentAlertTriggered` — إشعار ولي الأمر بعد 20 دقيقة
6. `onCoinBalanceChanged` — إعادة حساب درجة الخلية الجماعية
7. `aggregateDailyAttendance` — تجميع إحصائيات الحضور اليومية

---

## 🚀 خطوات التشغيل

```bash
# 1. تثبيت الحزم
flutter pub get

# 2. ضبط Firebase
flutterfire configure

# 3. تعريف المتغيرات البيئية (مطلوب للبناء)
flutter run \
  --dart-define=GEMINI_API_KEY=your_key \
  --dart-define=AGORA_APP_ID=your_agora_id \
  --dart-define=CAFETERIA_API_URL=https://your-api.sa

# 4. Cloud Functions
cd functions && npm install && npm run deploy

# 5. Firestore Rules
firebase deploy --only firestore:rules
```

---

## 📋 ما يحتاج استكمالاً

- [ ] شاشة تسجيل الدخول
- [ ] شاشة الملف الشخصي
- [ ] شاشة خطة الإنقاذ التفصيلية
- [ ] شاشة المتجر
- [ ] GoRouter مع حراسة المسارات
- [ ] اختبارات الوحدة (widget tests)
- [ ] Firebase Remote Config للإعدادات
- [ ] صفحة إعدادات الإشعارات

---

*بنيان OS — بُنيَ بـ Flutter · مدعوم بـ Firebase · مُحرَّك بـ Gemini AI*
*حفظ الله طلاب العلم وأعانهم على التفوق في دينهم ودنياهم* 🤲

---

## رفع المشروع على GitHub

```bash
git init
git add .
git commit -m "Bonyan OS - initial commit"
git branch -M main
git remote add origin https://github.com/USERNAME/bonyan-os.git
git push -u origin main
```

ثم في GitHub: Settings → Secrets and variables → Actions، وأضف:
`FIREBASE_OPTIONS_DART` و `GOOGLE_SERVICES_JSON` و `GEMINI_API_KEY` و `AGORA_APP_ID`.
بعدها من تبويب Actions شغّل **Build Bonyan APK** وحمّل الـ APK من Artifacts.
