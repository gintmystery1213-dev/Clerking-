import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Compact on-device encoder distilled from **paraphrase-MiniLM-L3-v2**.
///
/// Assets (~300KB total):
/// - `minilm_static_96.vocab` — token list
/// - `minilm_static_96.vec.zlib` — int8 matrix + scales
/// - `intent_static_96.json` — intent vectors in the same space
///
/// Runtime: tokenize → lookup → mean pool → L2 normalize → cosine rank.
/// Pure Dart · no ONNX/TFLite · sub-ms on phones.
class OnDeviceEncoder {
  OnDeviceEncoder._();
  static final OnDeviceEncoder instance = OnDeviceEncoder._();

  bool loaded = false;
  int dim = 96;
  final Map<String, Float32List> _vectors = {};
  final Map<String, List<double>> intentVectors = {};

  Future<void> load() async {
    if (loaded) return;

    final vocabStr = await rootBundle.loadString(
      'assets/knowledge/models/minilm_static_96.vocab',
    );
    final words = vocabStr
        .split('\n')
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList();

    final compressed = await rootBundle.load(
      'assets/knowledge/models/minilm_static_96.vec.zlib',
    );
    final zbytes = compressed.buffer.asUint8List(
      compressed.offsetInBytes,
      compressed.lengthInBytes,
    );
    final raw = Uint8List.fromList(zlib.decode(zbytes));

    var o = 0;
    dim = _u32(raw, o);
    o += 4;
    final nVocab = _u32(raw, o);
    o += 4;
    if (nVocab != words.length) {
      throw StateError('Vocab size mismatch: file=$nVocab text=${words.length}');
    }

    final qBytes = nVocab * dim;
    final q = raw.sublist(o, o + qBytes);
    o += qBytes;
    final bd = ByteData.sublistView(raw, o, o + nVocab * 4);

    for (var i = 0; i < nVocab; i++) {
      final scale = bd.getFloat32(i * 4, Endian.little) / 127.0;
      final v = Float32List(dim);
      final base = i * dim;
      for (var d = 0; d < dim; d++) {
        final qi = q[base + d];
        final signed = qi > 127 ? qi - 256 : qi;
        v[d] = signed * scale;
      }
      _vectors[words[i]] = v;
    }

    final intentRaw = await rootBundle.loadString(
      'assets/knowledge/models/intent_static_96.json',
    );
    final intentJson = jsonDecode(intentRaw) as Map<String, dynamic>;
    final intents = intentJson['intents'] as Map<String, dynamic>;
    intents.forEach((id, vec) {
      intentVectors[id] =
          (vec as List).map((e) => (e as num).toDouble()).toList();
    });

    loaded = true;
  }

  List<double> embed(String text) {
    if (!loaded) return List.filled(dim, 0);
    final toks = text
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s']"), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final acc = Float32List(dim);
    var count = 0;
    for (final t in toks) {
      var v = _vectors[t];
      if (v == null && t.endsWith('s') && t.length > 3) {
        v = _vectors[t.substring(0, t.length - 1)];
      }
      if (v == null && t.endsWith('ing') && t.length > 5) {
        v = _vectors[t.substring(0, t.length - 3)];
      }
      if (v == null) continue;
      for (var d = 0; d < dim; d++) {
        acc[d] += v[d];
      }
      count++;
    }
    if (count == 0) return List.filled(dim, 0);
    var norm = 0.0;
    for (var d = 0; d < dim; d++) {
      acc[d] /= count;
      norm += acc[d] * acc[d];
    }
    norm = math.sqrt(norm);
    if (norm < 1e-9) return List.filled(dim, 0);
    return [for (var d = 0; d < dim; d++) acc[d] / norm];
  }

  List<({String id, double score})> rankIntents(String text, {int topK = 10}) {
    final q = embed(text);
    final scored = <({String id, double score})>[];
    intentVectors.forEach((id, vec) {
      scored.add((id: id, score: _cosine(q, vec)));
    });
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).toList();
  }

  static double _cosine(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
}
