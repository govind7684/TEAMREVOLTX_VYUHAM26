import '../../core/constants/enums.dart';

/// One finding about a photo.
class ImageFinding {
  const ImageFinding({
    required this.category,
    required this.confidence,
    required this.source,
    this.label,
  });
  final IncidentCategory category;

  /// Model confidence 0..1. For human-tagged findings this is null in the
  /// database; here it is 1.0 only to mean "a person decided".
  final double confidence;

  /// 'human' or a model id such as 'yolo-tflite'. Never a model name unless
  /// that model really ran.
  final String source;
  final String? label;
  bool get isHuman => source == ImageAnalyzer.humanSource;
}

/// Contract for photo analysis. A YOLO (TFLite) detector can implement this
/// when a model file is bundled; see docs/IMAGE_MODEL.md. Until then the app
/// uses [UnavailableImageAnalyzer], which honestly reports that no model ran,
/// and findings come from a person choosing what the photo shows.
abstract class ImageAnalyzer {
  static const humanSource = 'human';
  String get id;
  bool get isModel;
  String get statusText;
  Future<ImageFinding?> analyze(String imagePath);
}

class UnavailableImageAnalyzer implements ImageAnalyzer {
  const UnavailableImageAnalyzer();
  @override
  String get id => 'none';
  @override
  bool get isModel => false;
  @override
  String get statusText =>
      'No image model is installed in this build, so photos are not analysed '
      'automatically. Please say what the photo shows; a person confirms it.';
  @override
  Future<ImageFinding?> analyze(String imagePath) async => null;
}

/// What a YOLO-style detector could be asked to find, mapped to categories.
const supportedPhotoFaults = <String, IncidentCategory>{
  'Pothole / damaged road': IncidentCategory.roadDamage,
  'Garbage accumulation': IncidentCategory.waste,
  'Waterlogging / flooding': IncidentCategory.flooding,
  'Blocked or open drain': IncidentCategory.blockedDrain,
  'Water leakage': IncidentCategory.waterLeak,
  'Broken streetlight': IncidentCategory.streetlight,
  'Accessibility barrier': IncidentCategory.accessibility,
  'Other / not sure': IncidentCategory.other,
};
