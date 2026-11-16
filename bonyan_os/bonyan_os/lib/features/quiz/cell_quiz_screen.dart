// lib/features/quiz/cell_quiz_screen.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║      بنيان OS — مسابقة الخلية التنافسية                    ║
// ║  Realtime MCQ · Firebase sync · Leaderboard                 ║
// ╚══════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/bonyan_theme.dart';
import '../ai/mueen_ai_provider.dart';
import '../auth/master_auth_provider.dart';
import '../gamification/sumou_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// QUIZ STATE (Realtime DB per session)
// ─────────────────────────────────────────────────────────────────────────────

class CellQuizScreen extends ConsumerStatefulWidget {
  final String quizSessionId;
  final String subjectNameAr;
  final List<McqQuestion> questions;

  const CellQuizScreen({
    super.key,
    required this.quizSessionId,
    required this.subjectNameAr,
    required this.questions,
  });

  @override
  ConsumerState<CellQuizScreen> createState() => _CellQuizScreenState();
}

class _CellQuizScreenState extends ConsumerState<CellQuizScreen>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  int _score = 0;
  int? _selectedOption;
  bool _answered = false;
  bool _finished = false;
  int _timeLeft = 30; // seconds per question
  Timer? _questionTimer;

  late final AnimationController _progressController;
  late final DatabaseReference _sessionRef;
  Map<String, int> _memberScores = {}; // uid → score (live from RT DB)
  StreamSubscription<DatabaseEvent>? _scoresSub;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );

    _sessionRef = FirebaseDatabase.instance
        .ref('quizSessions/${widget.quizSessionId}');

    _listenToScores();
    _startQuestionTimer();
  }

  void _listenToScores() {
    _scoresSub = _sessionRef.child('scores').onValue.listen((event) {
      if (!event.snapshot.exists || !mounted) return;
      final raw = Map<String, dynamic>.from(
        event.snapshot.value as Map<Object?, Object?>);
      setState(() {
        _memberScores = raw.map((k, v) => MapEntry(k, (v as num).toInt()));
      });
    });
  }

  void _startQuestionTimer() {
    _timeLeft = 30;
    _progressController.forward(from: 0);
    _questionTimer?.cancel();
    _questionTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _timeLeft--);
      if (_timeLeft <= 0) {
        t.cancel();
        if (!_answered) _onOptionSelected(-1); // time out = wrong
      }
    });
  }

  Future<void> _onOptionSelected(int optionIndex) async {
    if (_answered) return;
    setState(() {
      _selectedOption = optionIndex;
      _answered = true;
    });
    _questionTimer?.cancel();
    _progressController.stop();

    final q = widget.questions[_currentIndex];
    final isCorrect = optionIndex == q.correctIndex;
    final points = isCorrect ? (_timeLeft * 2) : 0; // faster = more points

    if (isCorrect) {
      _score += points;
      await BonyanHaptics.rewardPulse();

      // Push score to Realtime DB (all members see it live)
      final uid = ref.read(currentProfileProvider)?.uid ?? 'anon';
      await _sessionRef.child('scores/$uid').set(_score);
    } else {
      await BonyanHaptics.errorPulse();
    }

    // Auto-advance after 1.8s
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    if (_currentIndex < widget.questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOption = null;
        _answered = false;
      });
      _startQuestionTimer();
    } else {
      setState(() => _finished = true);
      _questionTimer?.cancel();
      await _finalizeQuiz();
    }
  }

  Future<void> _finalizeQuiz() async {
    final uid = ref.read(currentProfileProvider)?.uid ?? '';
    // Mark quiz done in Firestore
    await FirebaseFirestore.instance
        .collection('quizSessions')
        .doc(widget.quizSessionId)
        .collection('results')
        .doc(uid)
        .set({
      'score': _score,
      'totalQuestions': widget.questions.length,
      'finishedAt': FieldValue.serverTimestamp(),
    });

    // Award coins for quiz participation
    ref.read(bonyanEventBusProvider).fire(BonyanCoinEarnedEvent(
      amount: (_score / 10).round().clamp(5, 50),
      source: CoinSource.quizWin,
      reason: 'شاركت في مسابقة ${widget.subjectNameAr} 🏆',
      timestamp: DateTime.now(),
      sourceUserId: uid,
    ));
  }

  @override
  void dispose() {
    _progressController.dispose();
    _questionTimer?.cancel();
    _scoresSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _buildFinishedScreen();

    final q = widget.questions[_currentIndex];

    return Scaffold(
      backgroundColor: BonyanColors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            _QuizHeader(
              subjectNameAr: widget.subjectNameAr,
              current: _currentIndex + 1,
              total: widget.questions.length,
              score: _score,
              progressController: _progressController,
              timeLeft: _timeLeft,
            ),

            // ── Live member scores ──────────────────────────────────────────
            if (_memberScores.isNotEmpty)
              _LiveScoreRow(scores: _memberScores),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const SizedBox(height: 16),

                    // Difficulty chip
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _DifficultyChip(difficulty: q.difficulty),
                    ),
                    const SizedBox(height: 16),

                    // Question text
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: BonyanColors.surface800,
                        borderRadius: BorderRadius.circular(BonyanRadius.lg),
                        border: Border.all(color: BonyanColors.surface500),
                      ),
                      child: Text(
                        q.questionAr,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: BonyanColors.white,
                          height: 1.7,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ).animate(key: ValueKey(_currentIndex))
                     .fadeIn(duration: 300.ms)
                     .slideY(begin: 0.1),

                    const SizedBox(height: 20),

                    // Options
                    ...q.optionsAr.asMap().entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _OptionButton(
                          key: ValueKey('${_currentIndex}_${e.key}'),
                          index: e.key,
                          text: e.value,
                          selected: _selectedOption == e.key,
                          isCorrect: e.key == q.correctIndex,
                          answered: _answered,
                          onTap: () => _onOptionSelected(e.key),
                        ).animate(delay: Duration(milliseconds: 80 * e.key))
                         .fadeIn().slideX(begin: 0.1),
                      );
                    }),

                    // Explanation (shown after answering)
                    if (_answered) ...[
                      const SizedBox(height: 16),
                      _ExplanationCard(explanation: q.explanationAr),
                    ],

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinishedScreen() {
    // Sort scores to find winner
    final sorted = _memberScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final uid = ref.read(currentProfileProvider)?.uid ?? '';
    final myRank = sorted.indexWhere((e) => e.key == uid) + 1;

    return Scaffold(
      backgroundColor: BonyanColors.black,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Trophy
              Text(
                myRank == 1 ? '🏆' : myRank == 2 ? '🥈' : '🥉',
                style: const TextStyle(fontSize: 80),
              ).animate().scale(delay: 200.ms),

              const SizedBox(height: 20),

              Text(
                'انتهت المسابقة!',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: BonyanColors.white,
                ),
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 8),

              Text(
                'ترتيبك: $myRank من ${_memberScores.length}',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  color: BonyanColors.grey400,
                ),
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 8),

              Text(
                'نقاطك: $_score',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: BonyanColors.emerald500,
                ),
              ).animate().fadeIn(delay: 600.ms),

              const SizedBox(height: 40),

              // Leaderboard
              if (sorted.isNotEmpty)
                ..._buildLeaderboard(sorted, uid),

              const SizedBox(height: 40),

              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('العودة',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 16)),
              ).animate().fadeIn(delay: 800.ms),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLeaderboard(
      List<MapEntry<String, int>> sorted, String myUid) {
    return [
      const Text(
        'ترتيب الخلية',
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: BonyanColors.white,
        ),
      ),
      const SizedBox(height: 12),
      ...sorted.asMap().entries.map((e) {
        final rank = e.key + 1;
        final isMe = e.value.key == myUid;
        final medals = ['🥇', '🥈', '🥉'];
        return Animate(
          delay: Duration(milliseconds: 700 + rank * 100),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isMe
                  ? BonyanColors.emerald900
                  : BonyanColors.surface800,
              borderRadius: BorderRadius.circular(BonyanRadius.md),
              border: Border.all(
                color: isMe
                    ? BonyanColors.emerald500
                    : BonyanColors.surface500,
              ),
            ),
            child: Row(
              children: [
                Text(
                  rank <= 3 ? medals[rank - 1] : '$rank',
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isMe ? 'أنت' : e.value.key.substring(0, 6),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: isMe ? FontWeight.w700 : FontWeight.w400,
                      color: isMe ? BonyanColors.emerald400 : BonyanColors.white,
                    ),
                  ),
                ),
                Text(
                  '${e.value.value} نقطة',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: BonyanColors.goldAccent,
                  ),
                ),
              ],
            ),
          ).fadeIn().slideX(),
        );
      }),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _QuizHeader extends StatelessWidget {
  final String subjectNameAr;
  final int current, total, score, timeLeft;
  final AnimationController progressController;

  const _QuizHeader({
    required this.subjectNameAr,
    required this.current,
    required this.total,
    required this.score,
    required this.progressController,
    required this.timeLeft,
  });

  @override
  Widget build(BuildContext context) {
    final urgentColor = timeLeft <= 10 ? BonyanColors.error : BonyanColors.emerald500;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: BonyanColors.grey400),
              ),
              Expanded(
                child: Text(
                  subjectNameAr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: BonyanColors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: BonyanColors.emerald900,
                  borderRadius: BorderRadius.circular(BonyanRadius.full),
                ),
                child: Text(
                  '$score نقطة',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: BonyanColors.emerald400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$current / $total',
                style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 12, color: BonyanColors.grey400),
              ),
              const Spacer(),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: urgentColor,
                ),
                child: Text('$timeLeft ثانية'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedBuilder(
            animation: progressController,
            builder: (_, __) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: current / total,
                backgroundColor: BonyanColors.surface600,
                valueColor: AlwaysStoppedAnimation(urgentColor),
                minHeight: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveScoreRow extends StatelessWidget {
  final Map<String, int> scores;
  const _LiveScoreRow({required this.scores});

  @override
  Widget build(BuildContext context) {
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      margin: const EdgeInsets.only(top: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        children: sorted.map((e) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Chip(
            label: Text(
              '${e.key.substring(0, 4)} · ${e.value}',
              style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 11, color: BonyanColors.white),
            ),
            backgroundColor: BonyanColors.surface700,
            side: const BorderSide(color: BonyanColors.surface500),
            padding: EdgeInsets.zero,
          ),
        )).toList(),
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  final QuestionDifficulty difficulty;
  const _DifficultyChip({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (difficulty) {
      QuestionDifficulty.easy   => ('سهل', BonyanColors.emerald500),
      QuestionDifficulty.medium => ('متوسط', BonyanColors.warning),
      QuestionDifficulty.hard   => ('صعب', BonyanColors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(BonyanRadius.full),
        border: Border.all(color: color),
      ),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final int index;
  final String text;
  final bool selected, isCorrect, answered;
  final VoidCallback onTap;

  const _OptionButton({
    super.key,
    required this.index,
    required this.text,
    required this.selected,
    required this.isCorrect,
    required this.answered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = BonyanColors.surface800;
    Color border = BonyanColors.surface500;
    Color textColor = BonyanColors.white;
    String? trailingIcon;

    if (answered) {
      if (isCorrect) {
        bg = BonyanColors.emerald900;
        border = BonyanColors.emerald500;
        textColor = BonyanColors.emerald400;
        trailingIcon = '✓';
      } else if (selected && !isCorrect) {
        bg = const Color(0xFF1A0000);
        border = BonyanColors.error;
        textColor = BonyanColors.error;
        trailingIcon = '✗';
      }
    } else if (selected) {
      bg = BonyanColors.surface700;
      border = BonyanColors.emerald500;
    }

    final letters = ['أ', 'ب', 'ج', 'د'];

    return GestureDetector(
      onTap: answered ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(BonyanRadius.md),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: border.withOpacity(0.2),
                border: Border.all(color: border),
              ),
              child: Center(
                child: Text(
                  letters[index],
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  color: textColor,
                  height: 1.5,
                ),
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 8),
              Text(trailingIcon!, style: TextStyle(fontSize: 18, color: textColor)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  final String explanation;
  const _ExplanationCard({required this.explanation});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BonyanColors.surface700,
        borderRadius: BorderRadius.circular(BonyanRadius.md),
        border: Border.all(color: BonyanColors.surface500),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              explanation,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: BonyanColors.grey200,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }
}
