import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants/enums.dart';
import '../core/errors/app_exceptions.dart';
import 'prefs.dart';

/// What Claude suggested for a report description.
class AssistSuggestion {
  const AssistSuggestion({
    required this.category,
    required this.priority,
    required this.summary,
    required this.reason,
    this.departmentId,
    this.visible = true,
    this.landmarks = '',
    this.authenticity,
    this.authenticityReason,
  });
  final IncidentCategory category;
  final Priority priority;
  final String summary, reason;

  /// Department the model picked from the list the app sent; null if none.
  final String? departmentId;

  /// False when the photo shows no clear civic fault.
  final bool visible;

  /// Text Claude could actually read in the photo (a sign), never a guess.
  final String landmarks;

  /// Model opinion: real_photo, screen_photo, illustration_or_ai or unclear. Not proof.
  final String? authenticity;
  final String? authenticityReason;
}

/// Talks to the small assistant server in `server/` (which holds the Claude
/// key). The phone never sees the key. Sends only the report description text,
/// or aggregate counts for the briefing.
class AssistService {
  AssistService(this._prefs, {http.Client? client}) : _http = client ?? http.Client();
  final Prefs _prefs;
  final http.Client _http;

  static const urlKey = 'assist_url';
  static const tokenKey = 'assist_token';

  String? get baseUrl {
    final v = _prefs.get(urlKey)?.trim();
    if (v == null || v.isEmpty) return null;
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  bool get isConfigured => baseUrl != null;

  Future<void> configure(String? url, String? token) async {
    final u = url?.trim();
    await _prefs.set(urlKey, (u == null || u.isEmpty) ? null : u);
    final t = token?.trim();
    await _prefs.set(tokenKey, (t == null || t.isEmpty) ? null : t);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_prefs.get(tokenKey) != null) 'X-Assist-Token': _prefs.get(tokenKey)!,
      };

  Future<Map<String, dynamic>> _call(String method, String path, [Object? body]) async {
    final base = baseUrl;
    if (base == null) {
      throw const ValidationException(['The AI assistant is not set up. See More > Settings.']);
    }
    try {
      final uri = Uri.parse('$base$path');
      final res = method == 'GET'
          ? await _http.get(uri, headers: _headers).timeout(const Duration(seconds: 8))
          : await _http
              .post(uri, headers: _headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 30));
      final decoded = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
      final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      if (res.statusCode != 200) {
        throw ValidationException([(map['error'] as String?) ?? 'Assistant error (${res.statusCode}).']);
      }
      return map;
    } on TimeoutException {
      throw const ValidationException(['The assistant did not answer. Is the laptop server running?']);
    } on FormatException {
      throw const ValidationException(['The assistant sent an unreadable answer.']);
    } on AppException {
      rethrow;
    } catch (_) {
      throw const ValidationException(
          ['Cannot reach the assistant. Phone and laptop must be on the same Wi-Fi, with the server running.']);
    }
  }

  /// Returns the server's model name when it is reachable and configured.
  static String? _dept(Object? v) => v is String && Departments.names.containsKey(v) ? v : null;

  Future<String> test() async {
    final r = await _call('GET', '/health');
    if (r['configured'] != true) {
      throw const ValidationException(['Server is running but has no API key or model set.']);
    }
    return '${r['model']}';
  }

  Future<AssistSuggestion> suggest(String description) async {
    final r = await _call('POST', '/suggest', {
      'description': description,
      'departments': Departments.names,
    });
    final category = IncidentCategory.values.where((c) => c.name == r['category']).firstOrNull;
    final priority = Priority.values.where((p) => p.name == r['priority']).firstOrNull;
    if (category == null || priority == null) {
      throw const ValidationException(['The assistant gave an answer the app cannot use.']);
    }
    return AssistSuggestion(
      category: category,
      priority: priority,
      departmentId: _dept(r['department']),
      summary: '${r['summary'] ?? ''}',
      reason: '${r['reason'] ?? ''}',
    );
  }

  /// Sends the (already shrunk) report photo to the assistant server for a
  /// category and priority suggestion. The photo's place is NOT guessed; the
  /// location comes from the phone's GPS or the map.
  Future<AssistSuggestion> analyzePhoto(String path, {String description = ''}) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    if (bytes.length > 3 * 1024 * 1024) {
      throw const ValidationException(['That photo is too large to analyse. Choose a smaller one.']);
    }
    final lower = path.toLowerCase();
    final media = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    final r = await _call('POST', '/photo',
        {
          'image': base64Encode(bytes),
          'mediaType': media,
          'description': description,
          'departments': Departments.names,
        });
    final category = IncidentCategory.values.where((c) => c.name == r['category']).firstOrNull;
    final priority = Priority.values.where((p) => p.name == r['priority']).firstOrNull;
    if (category == null || priority == null) {
      throw const ValidationException(['The assistant gave an answer the app cannot use.']);
    }
    return AssistSuggestion(
      category: category,
      priority: priority,
      departmentId: _dept(r['department']),
      summary: '${r['summary'] ?? ''}',
      reason: '${r['reason'] ?? ''}',
      visible: r['visible'] == true,
      landmarks: '${r['landmarks'] ?? ''}',
      authenticity: r['authenticity'] as String?,
      authenticityReason: r['authenticityReason'] as String?,
    );
  }

  Future<String> briefing(Map<String, Object?> stats) async {
    final r = await _call('POST', '/briefing', stats);
    return '${r['text'] ?? ''}'.trim();
  }
}
