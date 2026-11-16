// lib/features/ai/mueen_ai_provider.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║         بنيان OS — مُعين: قلب الذكاء الاصطناعي             ║
// ║  Predictive Analytics · Rescue Plans · OCR · Arabic MCQ     ║
// ╚══════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:logger/logger.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/network/event_bus.dart';
import '../auth/master_auth_provider.dart';

part 'mueen_ai_provider.freezed.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class RescuePlan with _$RescuePlan {
  const factory RescuePlan({
    required String planId,
    required String subjectId,
    required String subjectNameAr,
    required String studentId,
    required List<RescueTopic> topics,
    required int dailyMinutes,
    required int estimatedDays,
    required DateTime createdAt,
    @Default(false) bool teacherNotified,
    String? motivationalMessageAr,
  }) = _RescuePlan;
}

@freezed
class RescueTopic with _$RescueTopic {
  const factory RescueTopic({
    required String topicId,
    required String titleAr,
    required String descriptionAr,
    required TopicPriority priority,
    required int estimatedMinutes,
    @Default([]) List<String> resourceUrls,
    @Default(false) bool isCompleted,
  }) = _RescueTopic;
}

enum TopicPriority { critical, high, medium, low }

@freezed
class McqQuestion with _$McqQuestion {
  const factory McqQuestion({
    required String questionId,
    required String questionAr,
    required List<String> optionsAr,    // Always 4 options
    required int correctIndex,
    required String explanationAr,
    required QuestionDifficulty difficulty,
    String? imageUrl,
  }) = _McqQuestion;
}

enum QuestionDifficulty { easy, medium, hard }

@freezed
class LectureTranscript with _$LectureTranscript {
  const factory LectureTranscript({
    required String transcriptId,
    required String subjectId,
    required String rawText,
    required String summaryAr,
    required List<String> keyPointsAr,
    required List<McqQuestion> quiz,
    required DateTime createdAt,
    @Default(0) int durationSeconds,
  }) = _LectureTranscript;
}

@freezed
class GradePrediction with _$GradePrediction {
  const factory GradePrediction({
    required String studentId,
    required String subjectId,
    required double currentGrade,
    required double predictedGrade,
    required double riskScore,         // 0.0 (safe) – 1.0 (critical)
    required List<String> riskFactorsAr,
    required List<String> recommendationsAr,
    required DateTime analyzedAt,
  }) = _GradePrediction;

  const GradePrediction._();

  bool get isAtRisk => riskScore > 0.4;
  bool get isCritical => riskScore > 0.7;

  String get riskLabelAr {
    if (isCritical) return '🔴 حرج';
    if (isAtRisk)   return '🟡 متابعة';
    return '🟢 مستقر';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — MUEEN AI STATE
// ─────────────────────────────────────────────────────────────────────────────

@freezed
class MueenState with _$MueenState {
  const factory MueenState({
    @Default([]) List<GradePrediction> predictions,
    @Default([]) List<RescuePlan> rescuePlans,
    @Default([]) List<LectureTranscript> transcripts,
    @Default([]) List<McqQuestion> pendingQuiz,
    @Default(false) bool isAnalyzing,
    @Default(false) bool isTranscribing,
    @Default(false) bool isGeneratingQuiz,
    String? activeMessage,
    String? errorAr,
  }) = _MueenState;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — MUEEN AI NOTIFIER
// ─────────────────────────────────────────────────────────────────────────────

class MueenAiNotifier extends AutoDisposeAsyncNotifier<MueenState> {
  final _logger = Logger();
  final _stt = SpeechToText();

  // Gemini model — key injected via --dart-define, never hardcoded
  GenerativeModel get _model => GenerativeModel(
        model: 'gemini-1.5-pro',
        apiKey: const String.fromEnvironment('GEMINI_API_KEY', defaultValue: ''),
        generationConfig: GenerationConfig(
          temperature: 0.3,      // Lower temp for educational accuracy
          maxOutputTokens: 4096,
          responseMimeType: 'application/json',
        ),
        systemInstruction: Content.text(_systemPromptAr),
      );

  static const _systemPromptAr = '''
أنت "مُعين" — مساعد تعليمي ذكي ضمن منصة بنيان التعليمية.
مهمتك: مساعدة الطلاب على التفوق الأكاديمي والروحي.

قواعدك الثابتة:
- تجيب دائمًا باللغة العربية الفصحى المبسطة.
- تكون داعمًا وإيجابيًا، لا تُحبط الطالب أبدًا.
- تربط دائمًا بين النجاح الأكاديمي والثبات الروحي.
- مخرجاتك دائمًا JSON صحيح قابل للتحليل البرمجي.
- لا تختلق معلومات — إذا لم تكن متأكدًا قل "لا أعلم".
''';

  @override
  Future<MueenState> build() async {
    // Subscribe to event bus — react to grade drops automatically
    final bus = ref.watch(bonyanEventBusProvider);
    final sub = bus.on<GradeDropDetectedEvent>(_onGradeDropDetected);
    ref.onDispose(sub.cancel);
    return const MueenState();
  }

  // ── PREDICTIVE GRADE ANALYSIS ─────────────────────────────────────────────
  Future<List<GradePrediction>> analyzeStudentGrades({
    required String studentId,
    required List<Map<String, dynamic>> gradeHistory, // [{subject, grades[], attendance, azkarRate}]
  }) async {
    state = AsyncData(state.valueOrNull?.copyWith(isAnalyzing: true) ?? const MueenState(isAnalyzing: true));
    _logger.i('🧠 Mueen: analyzing grades for $studentId');

    try {
      final prompt = '''
حلل بيانات الطالب التالية وتنبأ بأدائه المستقبلي.

بيانات الطالب:
${jsonEncode(gradeHistory)}

أعطني تحليلًا لكل مادة بصيغة JSON التالية:
{
  "predictions": [
    {
      "subjectId": "string",
      "subjectNameAr": "string",
      "currentGrade": 0.0,
      "predictedGrade": 0.0,
      "riskScore": 0.0,
      "riskFactorsAr": ["string"],
      "recommendationsAr": ["string"]
    }
  ]
}

riskScore: 0.0 = آمن تمامًا، 1.0 = خطر شديد.
ضع في اعتبارك: انتظام الصلاة وإتمام الأذكار يرتبطان إيجابيًا بالأداء الأكاديمي.
''';

      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '{}';
      final data = jsonDecode(_cleanJson(text)) as Map<String, dynamic>;
      final rawList = data['predictions'] as List<dynamic>? ?? [];

      final predictions = rawList.map((p) {
        final m = p as Map<String, dynamic>;
        return GradePrediction(
          studentId: studentId,
          subjectId: m['subjectId'] as String,
          subjectNameAr: m['subjectNameAr'] as String,
          currentGrade: (m['currentGrade'] as num).toDouble(),
          predictedGrade: (m['predictedGrade'] as num).toDouble(),
          riskScore: (m['riskScore'] as num).toDouble(),
          riskFactorsAr: List<String>.from(m['riskFactorsAr'] as List),
          recommendationsAr: List<String>.from(m['recommendationsAr'] as List),
          analyzedAt: DateTime.now(),
        );
      }).toList();

      // Auto-trigger rescue plan for critical subjects
      for (final pred in predictions) {
        if (pred.isCritical) {
          final dropPct = ((pred.currentGrade - pred.predictedGrade) / pred.currentGrade * 100)
              .abs();
          ref.read(bonyanEventBusProvider).fire(GradeDropDetectedEvent(
            subjectId: pred.subjectId,
            subjectName: pred.subjectNameAr,
            previousGrade: pred.currentGrade,
            currentGrade: pred.predictedGrade,
            dropPercentage: dropPct,
            timestamp: DateTime.now(),
            sourceUserId: studentId,
          ));
        }
      }

      state = AsyncData(state.valueOrNull?.copyWith(
            predictions: predictions,
            isAnalyzing: false,
          ) ?? const MueenState());

      return predictions;
    } catch (e) {
      _logger.e('❌ Mueen analysis error: $e');
      state = AsyncData(state.valueOrNull?.copyWith(
            isAnalyzing: false,
            errorAr: 'حدث خطأ أثناء التحليل. يُرجى المحاولة مجددًا',
          ) ?? const MueenState());
      return [];
    }
  }

  // ── RESCUE PLAN GENERATION ────────────────────────────────────────────────
  Future<RescuePlan?> generateRescuePlan({
    required String studentId,
    required String subjectId,
    required String subjectNameAr,
    required double currentGrade,
    required double targetGrade,
    required List<String> weakTopicsAr,
    required int availableDailyMinutes,
  }) async {
    _logger.i('📚 Mueen: generating rescue plan for $subjectNameAr');

    try {
      final prompt = '''
أنشئ خطة إنقاذ أكاديمية مفصّلة للطالب.

المادة: $subjectNameAr
الدرجة الحالية: $currentGrade%
الدرجة المستهدفة: $targetGrade%
المواضيع الضعيفة: ${weakTopicsAr.join('، ')}
الوقت المتاح يوميًا: $availableDailyMinutes دقيقة

أعطني خطة بصيغة JSON:
{
  "topics": [
    {
      "topicId": "t1",
      "titleAr": "string",
      "descriptionAr": "string",
      "priority": "critical|high|medium|low",
      "estimatedMinutes": 0
    }
  ],
  "dailyMinutes": 0,
  "estimatedDays": 0,
  "motivationalMessageAr": "string"
}

رتّب المواضيع حسب الأولوية. الرسالة التحفيزية تربط بين الجد في الطلب وقول النبي ﷺ في فضل العلم.
''';

      final response = await _model.generateContent([Content.text(prompt)]);
      final data = jsonDecode(_cleanJson(response.text ?? '{}')) as Map<String, dynamic>;

      final plan = RescuePlan(
        planId: 'plan_${subjectId}_${DateTime.now().millisecondsSinceEpoch}',
        subjectId: subjectId,
        subjectNameAr: subjectNameAr,
        studentId: studentId,
        topics: (data['topics'] as List<dynamic>).map((t) {
          final tm = t as Map<String, dynamic>;
          return RescueTopic(
            topicId: tm['topicId'] as String,
            titleAr: tm['titleAr'] as String,
            descriptionAr: tm['descriptionAr'] as String,
            priority: TopicPriority.values.firstWhere(
              (p) => p.name == tm['priority'],
              orElse: () => TopicPriority.medium,
            ),
            estimatedMinutes: (tm['estimatedMinutes'] as num).toInt(),
          );
        }).toList(),
        dailyMinutes: (data['dailyMinutes'] as num).toInt(),
        estimatedDays: (data['estimatedDays'] as num).toInt(),
        createdAt: DateTime.now(),
        motivationalMessageAr: data['motivationalMessageAr'] as String?,
      );

      state = AsyncData(state.valueOrNull?.copyWith(
            rescuePlans: [...?state.valueOrNull?.rescuePlans, plan],
          ) ?? const MueenState());

      // Fire event for notifications and coins
      ref.read(bonyanEventBusProvider).fire(RescuePlanGeneratedEvent(
        planId: plan.planId,
        subjectId: plan.subjectId,
        recommendedDailyMinutes: plan.dailyMinutes,
        topicIds: plan.topics.map((t) => t.topicId).toList(),
        timestamp: DateTime.now(),
        sourceUserId: studentId,
      ));

      return plan;
    } catch (e) {
      _logger.e('❌ Rescue plan error: $e');
      return null;
    }
  }

  // ── LECTURE TRANSCRIPTION + SUMMARY + MCQ ─────────────────────────────────
  Future<LectureTranscript?> transcribeAndAnalyzeLecture({
    required File audioFile,
    required String subjectId,
    required String subjectNameAr,
    required String studentId,
  }) async {
    state = AsyncData(state.valueOrNull?.copyWith(isTranscribing: true) ?? const MueenState(isTranscribing: true));
    _logger.i('🎙️ Mueen: transcribing lecture for $subjectNameAr');

    try {
      // Step 1: Convert audio to base64 for Gemini
      final audioBytes = await audioFile.readAsBytes();
      final base64Audio = base64Encode(audioBytes);

      // Step 2: Transcribe + summarize in one call
      final transcribePrompt = '''
هذا تسجيل صوتي لمحاضرة في مادة "$subjectNameAr".
قم بما يلي وأعطني النتيجة بصيغة JSON:
{
  "rawText": "النص الكامل للمحاضرة",
  "summaryAr": "ملخص المحاضرة في 3-5 جمل",
  "keyPointsAr": ["نقطة 1", "نقطة 2", "نقطة 3"]
}
''';

      final transcribeResponse = await _model.generateContent([
        Content.multi([
          DataPart('audio/mp4', audioBytes),
          TextPart(transcribePrompt),
        ]),
      ]);

      final transcribeData =
          jsonDecode(_cleanJson(transcribeResponse.text ?? '{}')) as Map<String, dynamic>;

      // Step 3: Generate MCQ quiz from transcript
      state = AsyncData(state.valueOrNull?.copyWith(isGeneratingQuiz: true) ?? const MueenState());

      final quiz = await _generateMcqFromText(
        text: transcribeData['rawText'] as String? ?? '',
        subjectNameAr: subjectNameAr,
        count: 10,
      );

      final transcriptId = 'tr_${DateTime.now().millisecondsSinceEpoch}';
      final transcript = LectureTranscript(
        transcriptId: transcriptId,
        subjectId: subjectId,
        rawText: transcribeData['rawText'] as String? ?? '',
        summaryAr: transcribeData['summaryAr'] as String? ?? '',
        keyPointsAr: List<String>.from(transcribeData['keyPointsAr'] as List? ?? []),
        quiz: quiz,
        createdAt: DateTime.now(),
      );

      state = AsyncData(state.valueOrNull?.copyWith(
            transcripts: [...?state.valueOrNull?.transcripts, transcript],
            isTranscribing: false,
            isGeneratingQuiz: false,
          ) ?? const MueenState());

      // Fire event → cell members get notified
      ref.read(bonyanEventBusProvider).fire(LectureTranscribedEvent(
        transcriptId: transcriptId,
        subjectId: subjectId,
        summaryAr: transcript.summaryAr,
        quizQuestionIds: quiz.map((q) => q.questionId).toList(),
        timestamp: DateTime.now(),
        sourceUserId: studentId,
      ));

      return transcript;
    } catch (e) {
      _logger.e('❌ Transcription error: $e');
      state = AsyncData(state.valueOrNull?.copyWith(
            isTranscribing: false,
            isGeneratingQuiz: false,
            errorAr: 'فشل تحليل التسجيل. تحقق من جودة الصوت',
          ) ?? const MueenState());
      return null;
    }
  }

  // ── MCQ GENERATION ────────────────────────────────────────────────────────
  Future<List<McqQuestion>> _generateMcqFromText({
    required String text,
    required String subjectNameAr,
    required int count,
  }) async {
    final prompt = '''
من النص التالي لمحاضرة في "$subjectNameAr"، أنشئ $count سؤالًا من اختيار متعدد.

النص:
$text

أعطني النتيجة بصيغة JSON:
{
  "questions": [
    {
      "questionId": "q1",
      "questionAr": "نص السؤال",
      "optionsAr": ["أ", "ب", "ج", "د"],
      "correctIndex": 0,
      "explanationAr": "شرح الإجابة الصحيحة",
      "difficulty": "easy|medium|hard"
    }
  ]
}

تنويع الصعوبة: 30% سهل، 50% متوسط، 20% صعب.
الأسئلة تقيس الفهم لا الحفظ.
''';

    final response = await _model.generateContent([Content.text(prompt)]);
    final data = jsonDecode(_cleanJson(response.text ?? '{}')) as Map<String, dynamic>;
    final rawQ = data['questions'] as List<dynamic>? ?? [];

    return rawQ.map((q) {
      final qm = q as Map<String, dynamic>;
      return McqQuestion(
        questionId: qm['questionId'] as String,
        questionAr: qm['questionAr'] as String,
        optionsAr: List<String>.from(qm['optionsAr'] as List),
        correctIndex: (qm['correctIndex'] as num).toInt(),
        explanationAr: qm['explanationAr'] as String,
        difficulty: QuestionDifficulty.values.firstWhere(
          (d) => d.name == qm['difficulty'],
          orElse: () => QuestionDifficulty.medium,
        ),
      );
    }).toList();
  }

  // ── LIVE VOICE STUDY ASSISTANT ────────────────────────────────────────────
  Future<String> askMueenVoice(String questionAr) async {
    _logger.i('🎤 Mueen: voice question received');
    try {
      final prompt = '''
سؤال الطالب: "$questionAr"

أجب بشكل مختصر ومفيد (3-5 جمل) ثم اختم بنصيحة تحفيزية قصيرة.
أعطني الإجابة كنص عادي (ليس JSON).
''';
      final chat = _model.startChat();
      final response = await chat.sendMessage(Content.text(prompt));
      return response.text ?? 'عذرًا، لم أستطع فهم السؤال. حاول مجددًا.';
    } catch (e) {
      return 'حدث خطأ في الاتصال. تحقق من الإنترنت.';
    }
  }

  // ── SPIRITUAL-ACADEMIC CORRELATION REPORT ─────────────────────────────────
  Future<String> generateCorrelationInsightAr({
    required double prayerConsistency,  // 0.0–1.0
    required double azkarConsistency,   // 0.0–1.0
    required double averageGrade,       // 0–100
    required double attendanceRate,     // 0.0–1.0
  }) async {
    final prompt = '''
لدينا بيانات الطالب التالية:
- انتظام الصلاة: ${(prayerConsistency * 100).round()}%
- إتمام الأذكار: ${(azkarConsistency * 100).round()}%
- المعدل الدراسي: ${averageGrade.round()}%
- نسبة الحضور: ${(attendanceRate * 100).round()}%

اكتب تحليلًا موجزًا (4 جمل) يربط بين الثبات الروحي والأداء الأكاديمي.
اجعله داعمًا، واستشهد بحكمة أو حديث إن أمكن.
أعطني النص مباشرة (ليس JSON).
''';
    final response = await _model.generateContent([Content.text(prompt)]);
    return response.text ?? '';
  }

  // ── PRIVATE: EVENT BUS LISTENER ───────────────────────────────────────────
  Future<void> _onGradeDropDetected(GradeDropDetectedEvent event) async {
    if (event.dropPercentage < 15) return; // Only significant drops
    _logger.w('🚨 Mueen auto-triggered by grade drop in ${event.subjectName}');

    // Auto-generate rescue plan with defaults
    await generateRescuePlan(
      studentId: event.sourceUserId ?? '',
      subjectId: event.subjectId,
      subjectNameAr: event.subjectName,
      currentGrade: event.currentGrade,
      targetGrade: event.previousGrade, // Restore to previous level
      weakTopicsAr: const ['يُحدَّد من تحليل الواجبات'],
      availableDailyMinutes: 45,
    );
  }

  // ── PRIVATE: Clean JSON response from model ───────────────────────────────
  String _cleanJson(String raw) {
    return raw
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final mueenAiProvider =
    AutoDisposeAsyncNotifierProvider<MueenAiNotifier, MueenState>(
  MueenAiNotifier.new,
);

final gradePredictionsProvider = Provider.autoDispose<List<GradePrediction>>(
  (ref) => ref.watch(mueenAiProvider).valueOrNull?.predictions ?? [],
);

final atRiskSubjectsProvider = Provider.autoDispose<List<GradePrediction>>(
  (ref) => ref.watch(gradePredictionsProvider).where((p) => p.isAtRisk).toList(),
);

final activeRescuePlansProvider = Provider.autoDispose<List<RescuePlan>>(
  (ref) => ref.watch(mueenAiProvider).valueOrNull?.rescuePlans ?? [],
);
