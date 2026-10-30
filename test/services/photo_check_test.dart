import 'package:civinex_ai/services/photo_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = DateTime(2026, 10, 1);

  test('live camera photo with a normal AI opinion is "live"', () {
    final c = PhotoCheck(origin: 'camera', capturedAt: t, gpsAtCapture: true, ai: 'real_photo');
    expect(c.verdict, PhotoVerdict.live);
  });

  test('gallery photo is unverified, not rejected', () {
    expect(PhotoCheck(origin: 'gallery', capturedAt: t).verdict, PhotoVerdict.unverified);
  });

  test('screen photo or generated image is suspicious even if taken live', () {
    expect(PhotoCheck(origin: 'camera', capturedAt: t, ai: 'screen_photo').verdict,
        PhotoVerdict.suspicious);
    expect(PhotoCheck(origin: 'camera', capturedAt: t, ai: 'illustration_or_ai').verdict,
        PhotoVerdict.suspicious);
  });

  test('json round trip keeps the fields and bad input gives null', () {
    final c = PhotoCheck(origin: 'camera', capturedAt: t, gpsAtCapture: true, ai: 'unclear', aiReason: 'blurry');
    final back = PhotoCheck.parse(c.toJson())!;
    expect(back.origin, 'camera');
    expect(back.gpsAtCapture, isTrue);
    expect(back.ai, 'unclear');
    expect(back.aiReason, 'blurry');
    expect(PhotoCheck.parse('not json'), isNull);
    expect(PhotoCheck.parse(null), isNull);
  });

  test('without an AI opinion the label says so', () {
    expect(PhotoCheck(origin: 'camera', capturedAt: t).aiLabel, contains('No AI opinion'));
  });
}
