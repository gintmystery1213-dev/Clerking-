import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Vector embedding matcher for clinical intents.
///
/// Offline path: **LSA** (TF–IDF → Truncated SVD) — classic dense vector
/// space model, same projection for queries and intents.
///
/// Online path: optional **neural** vectors (all-MiniLM-L6-v2, 384-d)
/// when a query embedding is supplied (e.g. from Worker).
class EmbeddingIndex {
  EmbeddingIndex._();
  static final EmbeddingIndex instance = EmbeddingIndex._();

  bool loaded = false;
  int lsaDim = 0;
  List<String> vocabulary = [];
  List<double> idf = [];
  List<List<double>> components = []; // (lsaDim, vocabSize)
  final Map<String, List<double>> intentLsa = {};
  final Map<String, List<double>> intentNeural = {};
  final Map<String, String> intentText = {};

  Future<void> load() async {
    if (loaded) return;
    final raw = await rootBundle.loadString(
      'assets/knowledge/intent_embeddings.json',
    );
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final lsa = data['lsa'] as Map<String, dynamic>;
    vocabulary = (lsa['vocabulary'] as List).cast<String>();
    idf = (lsa['idf'] as List).map((e) => (e as num).toDouble()).toList();
    components = (lsa['components'] as List)
        .map((row) => (row as List).map((e) => (e as num).toDouble()).toList())
        .toList();
    lsaDim = components.length;

    for (final item in (data['intents'] as List)) {
      final m = Map<String, dynamic>.from(item as Map);
      final id = m['id'] as String;
      intentText[id] = m['text'] as String? ?? '';
      intentLsa[id] =
          (m['lsa'] as List).map((e) => (e as num).toDouble()).toList();
      intentNeural[id] =
          (m['neural'] as List).map((e) => (e as num).toDouble()).toList();
    }
    loaded = true;
  }

  /// Project normalised query text into LSA space (unit vector).
  List<double> embedLsa(String normText) {
    if (!loaded || vocabulary.isEmpty) return List.filled(lsaDim, 0);

    final tokens = _tokenize(normText);
    if (tokens.isEmpty) return List.filled(lsaDim, 0);

    // TF
    final tf = <int, double>{};
    for (final t in tokens) {
      final i = _vocabIndex[t];
      if (i == null) continue;
      tf[i] = (tf[i] ?? 0) + 1;
    }
    if (tf.isEmpty) {
      // try unigrams from bigram vocab via contains
      for (final t in tokens) {
        for (var i = 0; i < vocabulary.length; i++) {
          if (vocabulary[i] == t) {
            tf[i] = (tf[i] ?? 0) + 1;
          }
        }
      }
    }

    final n = tokens.length.toDouble();
    final vec = List<double>.filled(vocabulary.length, 0);
    tf.forEach((i, c) {
      vec[i] = (c / n) * idf[i];
    });

    // Project: y = components * vec
    final out = List<double>.filled(lsaDim, 0);
    for (var k = 0; k < lsaDim; k++) {
      var s = 0.0;
      final row = components[k];
      tf.forEach((i, _) {
        s += row[i] * vec[i];
      });
      out[k] = s;
    }
    return _normalize(out);
  }

  Map<String, int>? _vocabIndexCache;
  Map<String, int> get _vocabIndex {
    if (_vocabIndexCache != null) return _vocabIndexCache!;
    final m = <String, int>{};
    for (var i = 0; i < vocabulary.length; i++) {
      m[vocabulary[i]] = i;
    }
    _vocabIndexCache = m;
    return m;
  }

  List<String> _tokenize(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s]"), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final out = <String>[...words];
    for (var i = 0; i < words.length - 1; i++) {
      out.add('${words[i]} ${words[i + 1]}');
    }
    return out;
  }

  List<double> _normalize(List<double> v) {
    var n = 0.0;
    for (final x in v) {
      n += x * x;
    }
    n = math.sqrt(n);
    if (n < 1e-9) return v;
    return [for (final x in v) x / n];
  }

  static double cosine(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  /// Rank intents by LSA cosine similarity to [normText].
  List<({String id, double score})> rankLsa(String normText, {int topK = 8}) {
    final q = embedLsa(normText);
    final scored = <({String id, double score})>[];
    intentLsa.forEach((id, vec) {
      scored.add((id: id, score: cosine(q, vec)));
    });
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).toList();
  }

  /// Rank using a provided neural query vector (from Worker / MiniLM).
  List<({String id, double score})> rankNeural(List<double> queryVec,
      {int topK = 8}) {
    final q = _normalize(List<double>.from(queryVec));
    final scored = <({String id, double score})>[];
    intentNeural.forEach((id, vec) {
      scored.add((id: id, score: cosine(q, vec)));
    });
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).toList();
  }
}
