import 'dart:math' as math;

import '../../core/constants/enums.dart';
import 'ai_provider.dart';
import 'rule_based_provider.dart';
import 'training_corpus.dart';

/// Multinomial Naive Bayes text classifier trained on-device from a small
/// built-in sample ([trainingCorpus]). This is a real statistical model: the
/// percentage it reports is its estimated probability, and it is NOT a measured
/// accuracy. It has no pretrained language knowledge, only the words it saw.
///
/// When the text contains no known words, or the model is unsure, the provider
/// falls back to the keyword rules and says so (no probability is shown then).
class NaiveBayesProvider implements AiProvider {
  NaiveBayesProvider({
    Map<IncidentCategory, List<String>>? corpus,
    this.minConfidence = 0.45,
    AiProvider? fallback,
  }) : _fallback = fallback ?? RuleBasedProvider() {
    _train(corpus ?? trainingCorpus);
  }

  final double minConfidence;
  final AiProvider _fallback;

  static const modelId = 'naive-bayes-local';

  @override
  String get id => modelId;

  @override
  String get description =>
      'Naive Bayes text model trained on this device from a small built-in '
      'sample of example complaints. Probabilities are model estimates, not '
      'measured accuracy.';

  final _wordCounts = <IncidentCategory, Map<String, int>>{};
  final _totalWords = <IncidentCategory, int>{};
  final _docCounts = <IncidentCategory, int>{};
  final _vocab = <String>{};
  var _docs = 0;

  int get vocabularySize => _vocab.length;
  int get trainingExamples => _docs;

  static const _stop = {
    'the', 'and', 'for', 'are', 'was', 'has', 'have', 'with', 'this', 'that',
    'near', 'from', 'not', 'but', 'all', 'our', 'its', 'any', 'out', 'since',
    'been', 'there', 'their', 'very', 'also', 'into', 'than', 'then', 'over',
    'please', 'need', 'needs', 'again', 'every', 'many', 'some', 'only',
  };

  static List<String> tokenize(String text) {
    final out = <String>[];
    for (final raw in text.toLowerCase().split(RegExp(r'[^a-z]+'))) {
      if (raw.length < 3 || _stop.contains(raw)) continue;
      out.add(_stem(raw));
    }
    return out;
  }

  static String _stem(String w) {
    if (w.length > 5 && w.endsWith('ing')) return w.substring(0, w.length - 3);
    if (w.length > 4 && w.endsWith('ed')) return w.substring(0, w.length - 2);
    if (w.length > 4 && w.endsWith('es')) return w.substring(0, w.length - 2);
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) {
      return w.substring(0, w.length - 1);
    }
    return w;
  }

  void _train(Map<IncidentCategory, List<String>> corpus) {
    corpus.forEach((cat, examples) {
      final counts = _wordCounts.putIfAbsent(cat, () => {});
      for (final ex in examples) {
        _docs++;
        _docCounts[cat] = (_docCounts[cat] ?? 0) + 1;
        for (final t in tokenize(ex)) {
          counts[t] = (counts[t] ?? 0) + 1;
          _totalWords[cat] = (_totalWords[cat] ?? 0) + 1;
          _vocab.add(t);
        }
      }
    });
  }

  double _logLik(IncidentCategory c, String token) {
    final n = _wordCounts[c]?[token] ?? 0;
    return math.log((n + 1) / ((_totalWords[c] ?? 0) + _vocab.length));
  }

  /// Posterior probabilities for every category, highest first, plus how many
  /// words of the text the model knew.
  ({List<(IncidentCategory, double)> ranked, int known, int total}) predict(String text) {
    final tokens = tokenize(text);
    final known = tokens.where(_vocab.contains).toList();
    final logs = <IncidentCategory, double>{};
    for (final c in _docCounts.keys) {
      var s = math.log(_docCounts[c]! / _docs);
      for (final t in known) {
        s += _logLik(c, t);
      }
      logs[c] = s;
    }
    final maxLog = logs.values.reduce(math.max);
    final exps = logs.map((k, v) => MapEntry(k, math.exp(v - maxLog)));
    final sum = exps.values.fold<double>(0, (a, b) => a + b);
    final ranked = exps.entries.map((e) => (e.key, e.value / sum)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return (ranked: ranked, known: known.length, total: tokens.length);
  }

  /// Words that pushed the decision towards [cat] most, for the explanation.
  List<String> topEvidence(String text, IncidentCategory cat) {
    final tokens = tokenize(text).where(_vocab.contains).toSet();
    final scored = <(String, double)>[];
    for (final t in tokens) {
      var others = 0.0;
      var n = 0;
      for (final c in _docCounts.keys) {
        if (c == cat) continue;
        others += _logLik(c, t);
        n++;
      }
      scored.add((t, _logLik(cat, t) - others / n));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.where((e) => e.$2 > 0).take(4).map((e) => e.$1).toList();
  }

  @override
  Future<AiSuggestion> analyze(AiInput input) async {
    final text = input.description;
    final p = predict(text);
    final rules = await _fallback.analyze(input);

    if (p.known == 0) {
      return AiSuggestion(
        category: rules.category,
        categoryReasons: [
          'The text model did not recognise any words in this description, '
              'so the keyword rules were used instead (no probability available).',
          ...rules.categoryReasons,
        ],
        providerId: _fallback.id,
        matchedKeywords: rules.matchedKeywords,
        needsHumanReview: true,
        reviewReasons: [...rules.reviewReasons, 'text model had no known words'],
        safetyRisk: rules.safetyRisk,
      );
    }

    var cat = p.ranked.first.$1;
    var conf = p.ranked.first.$2;
    final reasons = <String>[];
    final review = <String>[];

    final chosen = input.userCategory;
    if (chosen != null) {
      final chosenProb = p.ranked.firstWhere((e) => e.$1 == chosen).$2;
      if (chosenProb >= 0.15) {
        cat = chosen;
        conf = chosenProb;
        reasons.add('Kept your chosen category; the text model rates it at '
            '${(chosenProb * 100).round()}%.');
      } else {
        review.add('chosen category (${chosen.label}) differs from the text '
            '(model prefers ${p.ranked.first.$1.label})');
      }
    }

    final evidence = topEvidence(text, cat);
    reasons.insert(
        0,
        'Text model: ${cat.label} with ${(conf * 100).round()}% estimated probability'
        '${evidence.isEmpty ? '' : ' (key words: ${evidence.join(', ')})'}.');

    if (conf < minConfidence) review.add('low model confidence (${(conf * 100).round()}%)');
    if (p.known < 3) review.add('only ${p.known} recognised word(s)');
    if (p.ranked.length > 1 && p.ranked[1].$2 > 0.3 && cat == p.ranked.first.$1) {
      review.add('close to ${p.ranked[1].$1.label} (${(p.ranked[1].$2 * 100).round()}%)');
    }

    final lower = text.toLowerCase();
    final safety = input.safetyRiskFlag || RuleBasedProvider.safetyWords.any(lower.contains);
    if (safety) {
      reasons.add(input.safetyRiskFlag
          ? 'Reporter flagged an immediate safety risk.'
          : 'Text mentions possible safety words (keyword rule).');
      review.add('possible safety risk');
    }
    if (text.trim().length < 25) review.add('very short description');
    if (input.hasPhoto) {
      reasons.add('A photo is attached; see the photo finding for what it shows.');
    }

    return AiSuggestion(
      category: cat,
      categoryReasons: reasons,
      providerId: id,
      matchedKeywords: evidence,
      needsHumanReview: review.isNotEmpty,
      reviewReasons: review,
      safetyRisk: safety,
      confidence: conf,
      alternatives: p.ranked.where((e) => e.$1 != cat).take(2).toList(),
    );
  }
}
