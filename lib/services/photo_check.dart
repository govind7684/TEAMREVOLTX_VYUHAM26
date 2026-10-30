import 'dart:convert';

/// What we can honestly say about where a report photo came from.
///
/// This is NOT a detector of AI-generated pictures; no app can promise that.
/// What it does:
///  * records whether the photo was taken live with the phone's camera inside
///    the app (the strongest signal we have: a picture from the gallery or
///    downloaded from the internet cannot be sent as "live"),
///  * records when it was taken and whether the phone had a GPS fix then,
///  * adds an AI model's opinion on whether it looks like a real photograph,
///    a photo of a screen, or an illustration / generated image.
/// A weak result never rejects a report; it asks staff to look more carefully.
enum PhotoVerdict {
  /// Taken live in the app and nothing looks wrong.
  live('Taken live with the camera'),

  /// From the gallery, or no live-capture evidence. Not necessarily wrong.
  unverified('Not verified as live'),

  /// The AI opinion says it may be a screen photo or generated image.
  suspicious('Looks questionable: staff should check');

  const PhotoVerdict(this.label);
  final String label;
}

class PhotoCheck {
  const PhotoCheck({
    required this.origin,
    required this.capturedAt,
    this.gpsAtCapture = false,
    this.ai,
    this.aiReason,
  });

  /// 'camera' or 'gallery'.
  final String origin;
  final DateTime capturedAt;
  final bool gpsAtCapture;

  /// real_photo | screen_photo | illustration_or_ai | unclear, or null when no AI
  /// opinion was available.
  final String? ai;
  final String? aiReason;

  bool get live => origin == 'camera';

  PhotoVerdict get verdict {
    if (ai == 'screen_photo' || ai == 'illustration_or_ai') return PhotoVerdict.suspicious;
    return live ? PhotoVerdict.live : PhotoVerdict.unverified;
  }

  String get aiLabel => switch (ai) {
        'real_photo' => 'AI opinion: looks like a real photograph',
        'screen_photo' => 'AI opinion: may be a photo of a screen',
        'illustration_or_ai' => 'AI opinion: may be an illustration or generated image',
        'unclear' => 'AI opinion: unclear',
        _ => 'No AI opinion (assistant not used)',
      };

  /// Plain lines for the review screen and the staff view.
  List<String> get lines => [
        live ? 'Taken live with the phone camera in this app' : 'Chosen from the gallery (not verified as live)',
        if (gpsAtCapture) 'Phone location was found when the photo was taken',
        aiLabel,
        if (aiReason != null && aiReason!.isNotEmpty) aiReason!,
      ];

  String toJson() => jsonEncode({
        'origin': origin,
        'at': capturedAt.millisecondsSinceEpoch,
        'gps': gpsAtCapture,
        if (ai != null) 'ai': ai,
        if (aiReason != null) 'reason': aiReason,
      });

  static PhotoCheck? parse(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final m = jsonDecode(json);
      if (m is! Map) return null;
      return PhotoCheck(
        origin: m['origin'] == 'camera' ? 'camera' : 'gallery',
        capturedAt: DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? 0),
        gpsAtCapture: m['gps'] == true,
        ai: m['ai'] as String?,
        aiReason: m['reason'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
