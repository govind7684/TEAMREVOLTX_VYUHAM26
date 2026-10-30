# Photo analysis (YOLO) - how to plug a real model in

**Today: no image model ships with this app.** `UnavailableImageAnalyzer`
reports that honestly, and a person says what the photo shows ("Pothole",
"Garbage", ...). Staff can confirm or correct it. Nothing labels a photo as
"AI detected" unless a model really ran.

## Adding YOLO on device (free)

1. Train or download a YOLO model whose licence you may use, for example a
   YOLOv8n pothole/garbage/waterlogging detector, and export it to TFLite:
   `yolo export model=best.pt format=tflite`.
   Check the licence of the model and of the Ultralytics tooling (AGPL-3.0 for
   Ultralytics code; this matters if you distribute the app).
2. Put the file at `assets/models/detector.tflite` with a `labels.txt`, and
   register the assets in `pubspec.yaml`.
3. Add `tflite_flutter` to `pubspec.yaml` and implement `ImageAnalyzer`
   (see `lib/services/ai/image_analyzer.dart`): load the model once, resize the
   photo to the model's input size, run it, map the best detection's label to
   an `IncidentCategory`, and return `ImageFinding(source: 'yolo-tflite', ...)`.
4. Override `imageAnalyzerProvider` with the new class.

The report form and incident screen already show the model's confidence and ask
a person to confirm; findings from a model are stored as "not yet verified"
until staff confirm them.

## Accuracy

A detector trained on a small or foreign dataset can be badly wrong on Kerala
roads. Measure it on your own photos before showing percentages to anyone.
