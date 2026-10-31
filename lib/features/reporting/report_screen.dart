import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/utils/validators.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai/image_analyzer.dart';
import '../../services/assist_service.dart';
import '../../services/location_service.dart';
import '../../services/photo_check.dart';
import '../../shared/brand/brand_widgets.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../incidents/incident_detail_screen.dart';
import '../map/location_picker_screen.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});
  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final _desc = TextEditingController();
  final _loc = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _people = TextEditingController(text: '1');
  IncidentCategory? _category;
  bool _safety = false;
  String? _photoPath;
  IncidentCategory? _photoShows;
  ImageFinding? _finding;
  AiSuggestion? _suggestion;
  AssistSuggestion? _claude;
  bool _claudeBusy = false;
  AssistSuggestion? _photoClaude;
  bool _photoBusy = false;
  String? _photoOrigin; // 'camera' or 'gallery'
  DateTime? _capturedAt;
  bool _gpsAtCapture = false;
  bool _descFromPhoto = false;
  bool _busy = false;

  // Wizard: 0 = issue, 1 = location, 2 = review.
  int _step = 0;
  LatLng? _point;
  bool _locating = false;
  bool _autoTried = false;
  bool _addressAuto = false; // the address text came from the lookup, not typing
  String? _locNote;

  @override
  void dispose() {
    for (final c in [_desc, _loc, _lat, _lng, _people, _otherKind]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _askClaude() async {
    final text = _desc.text.trim();
    if (text.length < 5) {
      showMessage(context, 'Describe the problem first (a few words at least).', error: true);
      return;
    }
    setState(() => _claudeBusy = true);
    try {
      final r = await ref.read(assistServiceProvider).suggest(text);
      if (mounted) setState(() => _claude = r);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _claudeBusy = false);
    }
  }

  bool _photoShowsByAi = false;
  final _otherKind = TextEditingController();

  Future<void> _askClaudeAboutPhoto() async {
    final path = _photoPath;
    if (path == null) return;
    setState(() => _photoBusy = true);
    try {
      final r = await ref
          .read(assistServiceProvider)
          .analyzePhoto(path, description: _desc.text.trim());
      if (mounted) {
        setState(() {
          _photoClaude = r;
          // Fill in what the person has not chosen yet; they can change it.
          if (r.visible && _category == null) _category = r.category;
          // The photo type is chosen from what the AI saw; the person can still change it.
          if (r.visible) {
            _photoShows = r.category;
            _photoShowsByAi = true;
          }
          if (r.visible && _desc.text.trim().isEmpty && r.summary.isNotEmpty) {
            _desc.text = r.summary;
            _descFromPhoto = true;
          }
        });
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  /// Takes a photo with the phone camera (the default, so the picture is live)
  /// or, as a second choice, picks one from the gallery. Right after the photo
  /// the app finds the location and, if the assistant is set up, has Claude look
  /// at the photo and suggest the problem and department.
  Future<void> _addPhoto({required bool camera}) async {
    try {
      final picked = await ImagePicker().pickImage(
          source: camera ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1280,
          imageQuality: 80);
      if (picked == null) return;
      final capturedAt = DateTime.now();
      final size = await File(picked.path).length();
      final problem = Validators.photoFile(picked.path, size);
      if (problem != null) {
        if (mounted) showMessage(context, problem, error: true);
        return;
      }
      // Copy into app-private storage under a random name.
      final dir = await getApplicationDocumentsDirectory();
      final photos = Directory(p.join(dir.path, 'incident_photos'));
      await photos.create(recursive: true);
      final dest = p.join(photos.path, '${const Uuid().v4()}${p.extension(picked.path).toLowerCase()}');
      await File(picked.path).copy(dest);
      // Runs a real image model only if one is installed; otherwise null.
      final finding = await ref.read(imageAnalyzerProvider).analyze(dest);
      if (!mounted) return;
      setState(() {
        _photoPath = dest;
        _photoOrigin = camera ? 'camera' : 'gallery';
        _capturedAt = capturedAt;
        _gpsAtCapture = false;
        _photoClaude = null;
        _photoShowsByAi = false;
        _finding = finding;
        _photoShows = finding?.category;
      });
      // Automatic steps: location first (needs no internet), then the AI look.
      if (_point == null) {
        await _useGps();
        if (mounted) setState(() => _gpsAtCapture = _point != null);
      } else {
        setState(() => _gpsAtCapture = true);
      }
      if (mounted && ref.read(assistServiceProvider).isConfigured) {
        await _askClaudeAboutPhoto();
      }
    } catch (_) {
      if (mounted) {
        showMessage(context, 'Could not use that photo. You can submit without one.', error: true);
      }
    }
  }

  /// Records the chosen point, shows its coordinates, and looks up a readable
  /// address (internet needed; the person can always type or correct it).
  Future<void> _setPoint(LatLng p, {String? source}) async {
    setState(() {
      _point = p;
      _lat.text = p.latitude.toStringAsFixed(6);
      _lng.text = p.longitude.toStringAsFixed(6);
      _suggestion = null;
      _locNote = source;
    });
    final address = await ref.read(geocodingProvider).reverse(p.latitude, p.longitude);
    if (!mounted || _point != p) return;
    setState(() {
      if (address != null) {
        // Never overwrite something the person typed themselves.
        if (_loc.text.trim().isEmpty || _addressAuto) {
          _loc.text = address;
          _addressAuto = true;
        }
        _locNote = '${source ?? 'Location set'}. Address found on OpenStreetMap; check it and correct if needed.';
      } else {
        _locNote = '${source ?? 'Location set'}. Could not look up the address (no internet or no result). Type it below.';
      }
    });
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.of(context)
        .push<LatLng>(MaterialPageRoute(builder: (_) => LocationPickerScreen(initial: _point)));
    if (result != null) await _setPoint(result, source: 'Picked on the map');
  }

  Future<void> _useGps() async {
    setState(() => _locating = true);
    try {
      final pos = await const LocationService().currentPosition();
      await _setPoint(pos, source: 'Detected from your phone\'s GPS');
    } catch (e) {
      if (mounted) {
        setState(() => _locNote = friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _goTo(int step) {
    setState(() => _step = step);
    // Detect once, the first time the location step opens.
    if (step == 1 && !_autoTried && _point == null) {
      _autoTried = true;
      _useGps();
    }
  }

  bool _validateIssue() {
    final d = _desc.text.trim();
    if (d.length < 10) {
      showMessage(context, 'Describe the problem in at least 10 characters.', error: true);
      return false;
    }
    final n = int.tryParse(_people.text.trim()) ?? 0;
    if (n < 1) {
      showMessage(context, 'People affected must be at least 1.', error: true);
      return false;
    }
    return true;
  }

  Future<void> _toReview() async {
    final ok = await _preview();
    if (ok) _goTo(2);
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim());

  Future<bool> _preview() async {
    final lat = _lat.text.trim().isEmpty ? null : _num(_lat);
    final lng = _lng.text.trim().isEmpty ? null : _num(_lng);
    if ((_lat.text.trim().isNotEmpty && lat == null) ||
        (_lng.text.trim().isNotEmpty && lng == null)) {
      showMessage(context, 'Latitude and longitude must be numbers.', error: true);
      return false;
    }
    final people = int.tryParse(_people.text.trim()) ?? 0;
    final errors = Validators.report(
      description: _desc.text,
      locationText: _loc.text,
      latitude: lat,
      longitude: lng,
      peopleAffected: people,
    );
    if (errors.isNotEmpty) {
      showMessage(context, errors.join('\n'), error: true);
      return false;
    }
    final s = await ref.read(incidentRepositoryProvider).suggest(AiInput(
          description: _desc.text,
          userCategory: _category,
          latitude: lat,
          longitude: lng,
          peopleAffected: people,
          safetyRiskFlag: _safety,
          hasPhoto: _photoPath != null,
        ));
    if (!mounted) return false;
    setState(() => _suggestion = s);
    return true;
  }

  Future<void> _submit() async {
    final user = ref.read(sessionProvider)!;
    setState(() => _busy = true);
    try {
      final result = await ref.read(incidentRepositoryProvider).submit(
            reporter: user,
            description: _desc.text,
            locationText: _loc.text,
            category: _category,
            latitude: _lat.text.trim().isEmpty ? null : _num(_lat),
            longitude: _lng.text.trim().isEmpty ? null : _num(_lng),
            photoPath: _photoPath,
            peopleAffected: int.tryParse(_people.text.trim()) ?? 0,
            safetyRisk: _safety,
            photoShows: _finding == null ? _photoShows : null,
            photoFinding: _finding != null && _photoShows == _finding!.category ? _finding : null,
            photoCheck: _photoPath == null ? null : _currentCheck(),
            aiDepartmentId: _photoClaude?.departmentId ?? _claude?.departmentId,
          );
      ref.read(refreshTickProvider.notifier).state++;
      if (!mounted) return;
      final dupNote = result.linkedTo != null
          ? ' It matches an existing report, so ${result.reporterCount} citizens are now counted together.'
          : result.duplicates.isEmpty
              ? ''
              : ' Similar open reports were found nearby; staff will review.';
      showMessage(context, 'Report ${result.incident.id} submitted.$dupNote');
      _desc.clear();
      _loc.clear();
      _lat.clear();
      _lng.clear();
      setState(() {
        _suggestion = null;
        _photoPath = null;
        _photoOrigin = null;
        _capturedAt = null;
        _gpsAtCapture = false;
        _photoClaude = null;
        _descFromPhoto = false;
        _photoShows = null;
        _finding = null;
        _category = null;
        _safety = false;
        _step = 0;
        _point = null;
        _autoTried = false;
        _addressAuto = false;
        _locNote = null;
        _people.text = '1';
      });
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => IncidentDetailScreen(incidentId: result.incident.id)));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  static const _groups = [
    _Group('Road & Transportation', 'Potholes, traffic, accessibility', Icons.directions_car_filled,
        Color(0xFFE5333D), [IncidentCategory.roadDamage, IncidentCategory.traffic, IncidentCategory.accessibility]),
    _Group('Water & Drainage', 'Leaks, flooding, drainage', Icons.water_drop,
        Color(0xFF3B82F6), [IncidentCategory.flooding, IncidentCategory.blockedDrain, IncidentCategory.waterLeak]),
    _Group('Electricity & Lighting', 'Street lights, power, electrical', Icons.bolt,
        Color(0xFFEAB308), [IncidentCategory.streetlight]),
    _Group('Public Facilities', 'Waste, parks, environment', Icons.chair_alt,
        Color(0xFF3B82F6), [IncidentCategory.waste, IncidentCategory.environment]),
    _Group('Other', 'General issues', Icons.more_horiz,
        Color(0xFF64748B), [IncidentCategory.other]),
  ];
  int? _openGroup;

  Widget _groupRow(BuildContext context, int g) {
    final grp = _groups[g];
    final scheme = Theme.of(context).colorScheme;
    final selected = _category != null && grp.cats.contains(_category);
    final open = _openGroup == g && grp.cats.length > 1;
    return Column(children: [
      Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: grp.color.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(12)),
            child: Icon(grp.icon, color: grp.color),
          ),
          title: Text(grp.title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(selected && grp.cats.length > 1 ? _category!.label : grp.subtitle),
          trailing: Icon(selected ? Icons.check_circle : (open ? Icons.expand_less : Icons.chevron_right),
              color: selected ? scheme.primary : null),
          onTap: () => setState(() {
            _suggestion = null;
            if (grp.cats.length == 1) {
              _category = _category == grp.cats.first ? null : grp.cats.first;
              _openGroup = null;
            } else {
              _openGroup = open ? null : g;
            }
          }),
        ),
      ),
      if (open)
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              for (final c in grp.cats)
                ChoiceChip(
                  label: Text(c.label),
                  selected: _category == c,
                  onSelected: (_) => setState(() {
                    _category = _category == c ? null : c;
                    _suggestion = null;
                  }),
                ),
            ]),
          ),
        ),
    ]);
  }

  Widget _stepper(BuildContext context) {
    const labels = ['Issue Details', 'Location', 'Review'];
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0)
          Expanded(child: Divider(color: i <= _step ? scheme.primary : scheme.outlineVariant, thickness: 2)),
        Column(children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: i <= _step ? scheme.primary : scheme.surfaceContainerHigh,
            foregroundColor: i <= _step ? scheme.onPrimary : scheme.onSurfaceVariant,
            child: i < _step
                ? const Icon(Icons.check, size: 16)
                : Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Text(labels[i],
              style: TextStyle(fontSize: 12, fontWeight: i == _step ? FontWeight.w800 : FontWeight.w500)),
        ]),
      ],
    ]);
  }

  Widget _stepIssue(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text("What's the issue?", style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 2),
      Text('Select a category for your report.',
          style: TextStyle(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 10),
      for (var g = 0; g < _groups.length; g++) _groupRow(context, g),
      const SizedBox(height: 16),
      TextField(
        controller: _desc,
        maxLines: 4,
        maxLength: 1000,
        decoration: const InputDecoration(labelText: 'What is the problem?'),
        onChanged: (_) => setState(() {
          _suggestion = null;
          _claude = null;
        }),
      ),
      if (ref.watch(assistServiceProvider).isConfigured) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _claudeBusy ? null : _askClaude,
            icon: _claudeBusy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('Suggest with Claude'),
          ),
        ),
        if (_claude != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Claude suggests: ${_claude!.category.label} · ${_claude!.priority.label} priority',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (_claude!.summary.isNotEmpty) Text(_claude!.summary),
                if (_claude!.reason.isNotEmpty)
                  Text(_claude!.reason, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                const Text('A suggestion from an AI model; you and staff decide.',
                    style: TextStyle(fontSize: 11)),
                TextButton(
                  onPressed: () => setState(() => _category = _claude!.category),
                  child: const Text('Use this category'),
                ),
              ]),
            ),
          ),
      ],
      const SizedBox(height: 4),
      TextField(
        controller: _people,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Approximate people affected'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Immediate safety risk'),
        subtitle: const Text('For example exposed wires, open manhole, deep water.'),
        value: _safety,
        onChanged: (v) => setState(() {
          _safety = v;
          _suggestion = null;
        }),
      ),
      FilledButton.icon(
        onPressed: () => _addPhoto(camera: true),
        icon: const Icon(Icons.photo_camera_outlined),
        label: Text(_photoPath == null ? 'Take a photo of the problem' : 'Retake photo'),
      ),
      Row(children: [
        Flexible(
          child: TextButton(
            onPressed: () => _addPhoto(camera: false),
            child: const Text('Use a gallery photo instead (not verified as live)',
                textAlign: TextAlign.start),
          ),
        ),
        if (_photoPath != null)
          IconButton(
            tooltip: 'Remove photo',
            onPressed: () => setState(() {
              _photoPath = null;
              _photoOrigin = null;
              _capturedAt = null;
              _gpsAtCapture = false;
              _photoShows = null;
              _photoShowsByAi = false;
              _finding = null;
              _photoClaude = null;
            }),
            icon: const Icon(Icons.close),
          ),
      ]),
      if (_photoPath == null)
        const Text(
            'A live photo lets the app find the location and suggest the problem and department for you.',
            style: TextStyle(fontSize: 12)),
      if (_photoPath != null) ...[
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(File(_photoPath!), height: 140, fit: BoxFit.cover),
        ),
        const SizedBox(height: 8),
        _photoStatus(context),
        if (_descFromPhoto)
          const Text('The description was filled in from the photo. Edit it if it is not right.',
              style: TextStyle(fontSize: 12)),
        if (ref.watch(assistServiceProvider).isConfigured) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _photoBusy ? null : _askClaudeAboutPhoto,
              icon: _photoBusy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('Analyse photo again'),
            ),
          ),
          if (_photoClaude != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (!_photoClaude!.visible)
                    const Text('No clear civic fault is visible in this photo.',
                        style: TextStyle(fontWeight: FontWeight.w700))
                  else
                    Text(
                        'Photo looks like: ${_photoClaude!.category.label} · '
                        '${_photoClaude!.priority.label} priority',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (_photoClaude!.visible)
                    Text('Would go to: ${Departments.nameOf(_photoClaude!.departmentId ?? _photoClaude!.category.departmentId)}'
                        '${_photoClaude!.departmentId == null ? '' : ' (AI choice)'}'),
                  if (_photoClaude!.summary.isNotEmpty) Text(_photoClaude!.summary),
                  if (_photoClaude!.landmarks.isNotEmpty)
                    Text('Readable in photo: ${_photoClaude!.landmarks}',
                        style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  const Text(
                      'From an AI model. The place of the report comes from your GPS or the map, '
                      'not from the photo. You and staff confirm.',
                      style: TextStyle(fontSize: 11)),
                  if (_photoClaude!.visible)
                    TextButton(
                      onPressed: () => setState(() => _category = _photoClaude!.category),
                      child: const Text('Use this category'),
                    ),
                ]),
              ),
            ),
        ],
        if (_finding != null)
          Text('Photo model (${_finding!.source}) suggests '
              '${_finding!.category.label} at ${(_finding!.confidence * 100).round()}%. '
              'Please confirm or correct it below.',
              style: const TextStyle(fontSize: 12)),
        DropdownButtonFormField<IncidentCategory?>(
          key: ValueKey('photo-shows-${_photoShows?.name}-$_photoShowsByAi'),
          initialValue: _photoShows,
          decoration: InputDecoration(
              labelText: 'What does the photo show?',
              helperText: _photoShowsByAi
                  ? 'Chosen by the AI from your photo. Change it if it is wrong.'
                  : (_photoBusy ? 'The AI is looking at the photo...' : 'Pick one, or use General / other.')),
          items: [
            const DropdownMenuItem(value: null, child: Text('Not chosen yet')),
            for (final e in supportedPhotoFaults.entries)
              DropdownMenuItem(
                  value: e.value,
                  child: Text(e.value == IncidentCategory.other ? 'General / other (type it below)' : e.key)),
          ],
          onChanged: (v) => setState(() {
            _photoShows = v;
            _photoShowsByAi = false;
          }),
        ),
        if (_photoShows == IncidentCategory.other) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _otherKind,
            maxLength: 60,
            decoration: const InputDecoration(
                labelText: 'Name the problem (optional)',
                hintText: 'For example: fallen tree, stray animals, broken bench'),
          ),
        ],
      ],
      const SizedBox(height: 4),
      Text(
          ref.watch(imageAnalyzerProvider).isModel
              ? 'Photos stay on this device. A model suggests what they show; you and staff confirm.'
              : 'Photos stay on this device${ref.watch(assistServiceProvider).isConfigured ? ' unless you tap Analyse photo with Claude, which sends that photo to the AI service' : ''}. ${ref.watch(imageAnalyzerProvider).statusText}',
          style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 16),
      GradientButton(
          onPressed: () {
            final kind = _otherKind.text.trim();
            if (_photoShows == IncidentCategory.other &&
                kind.isNotEmpty &&
                !_desc.text.toLowerCase().contains(kind.toLowerCase())) {
              _desc.text = _desc.text.trim().isEmpty ? kind : '$kind. ${_desc.text.trim()}';
            }
            if (_validateIssue()) _goTo(1);
          },
          label: 'Next'),
    ]);
  }

  PhotoCheck _currentCheck() => PhotoCheck(
        origin: _photoOrigin ?? 'gallery',
        capturedAt: _capturedAt ?? DateTime.now(),
        gpsAtCapture: _gpsAtCapture,
        ai: _photoClaude?.authenticity,
        aiReason: _photoClaude?.authenticityReason,
      );

  /// What the app did automatically after the photo, in plain words.
  Widget _photoStatus(BuildContext context) {
    final c = _currentCheck();
    final scheme = Theme.of(context).colorScheme;
    Widget row(IconData icon, String text, {bool warn = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: warn ? scheme.error : scheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          row(c.live ? Icons.check_circle_outline : Icons.info_outline,
              c.live ? 'Taken live with the camera' : 'From the gallery: not verified as live',
              warn: !c.live),
          row(_locating ? Icons.hourglass_empty : (_point != null ? Icons.check_circle_outline : Icons.info_outline),
              _locating
                  ? 'Finding your location…'
                  : (_point != null ? 'Location found automatically' : 'Location not found yet: set it in the next step')),
          row(_photoBusy ? Icons.hourglass_empty : Icons.auto_awesome_outlined,
              _photoBusy
                  ? 'AI is looking at the photo…'
                  : (_photoClaude == null ? 'No AI look yet (assistant not set up or offline)' : c.aiLabel),
              warn: c.verdict == PhotoVerdict.suspicious),
        ]),
      ),
    );
  }

  Widget _stepLocation(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.my_location, color: scheme.primary),
              const SizedBox(width: 8),
              Text('GPS position', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (_locating) const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 8),
            if (_point != null)
              Text('Latitude ${_point!.latitude.toStringAsFixed(6)}\nLongitude ${_point!.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], height: 1.5))
            else
              Text(_locating ? 'Finding your location…' : 'No position yet.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            if (_locNote != null) ...[
              const SizedBox(height: 6),
              Text(_locNote!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _locating ? null : _useGps,
                icon: const Icon(Icons.gps_fixed),
                label: Text(_point == null ? 'Detect my location' : 'Detect again'),
              ),
              OutlinedButton.icon(
                onPressed: _pickOnMap,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Pick on map'),
              ),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _loc,
        maxLines: 2,
        decoration: const InputDecoration(
            labelText: 'Address or landmark', helperText: 'Correct it if the lookup is wrong.'),
        onChanged: (_) => _addressAuto = false,
      ),
      const SizedBox(height: 6),
      const Text('Your position is read only when you open this step or tap a button, and is saved only in this report.',
          style: TextStyle(fontSize: 12)),
      const SizedBox(height: 16),
      Row(children: [
        OutlinedButton(onPressed: () => _goTo(0), child: const Text('Back')),
        const SizedBox(width: 12),
        Expanded(child: GradientButton(onPressed: _toReview, label: 'Next')),
      ]),
    ]);
  }

  Widget _stepReview(BuildContext context) {
    final s = _suggestion;
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your report', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_desc.text.trim()),
            const Divider(height: 20),
            Row(children: [
              const Icon(Icons.place_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(_loc.text.trim())),
            ]),
            if (_point != null)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 2),
                child: Text('${_point!.latitude.toStringAsFixed(5)}, ${_point!.longitude.toStringAsFixed(5)}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 6),
            Text('${_people.text.trim()} people affected${_safety ? ' · safety risk flagged' : ''}'
                '${_photoPath != null ? ' · photo attached' : ''}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            if (_photoPath != null) ...[
              const Divider(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(File(_photoPath!), height: 110, fit: BoxFit.cover),
              ),
              const SizedBox(height: 6),
              Text('Photo check', style: Theme.of(context).textTheme.titleSmall),
              for (final line in _currentCheck().lines)
                Text('• $line', style: const TextStyle(fontSize: 12)),
              const Text(
                  'The AI opinion is a hint, not proof. Staff look at every report and can ask for a new photo.',
                  style: TextStyle(fontSize: 11)),
            ],
          ]),
        ),
      ),
      if (s != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Suggested routing', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Category: ${s.category.label}'
                  '${s.confidence == null ? '' : ' (${(s.confidence! * 100).round()}% model estimate)'}'),
              if (s.alternatives.isNotEmpty)
                Text('Also possible: ${s.alternativesText}', style: const TextStyle(fontSize: 12)),
              Text('Will be sent to: ${Departments.nameOf(_photoClaude?.departmentId ?? _claude?.departmentId ?? s.category.departmentId)}'
                  '${(_photoClaude?.departmentId ?? _claude?.departmentId) == null ? '' : ' (AI choice; staff can reassign)'}'),
              const SizedBox(height: 4),
              Text(s.explanation, style: const TextStyle(fontSize: 12)),
              Text(
                  s.confidence == null
                      ? 'Suggestion source: ${s.providerId} (keyword rules, not a trained model; no probability).'
                      : 'Suggestion source: ${s.providerId} (small text model trained on this device; '
                          'the percentage is its own estimate, not a measured accuracy).',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              const Text('This is an AI suggestion. Staff review every report and can change it.',
                  style: TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      const SizedBox(height: 12),
      Row(children: [
        OutlinedButton(onPressed: _busy ? null : () => _goTo(1), child: const Text('Back')),
        const SizedBox(width: 12),
        Expanded(
          child: GradientButton(onPressed: _submit, busy: _busy, label: 'Submit report'),
        ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Report Issue', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      _stepper(context),
      const SizedBox(height: 16),
      switch (_step) {
        0 => _stepIssue(context),
        1 => _stepLocation(context),
        _ => _stepReview(context),
      },
    ]);
  }
}

class _Group {
  const _Group(this.title, this.subtitle, this.icon, this.color, this.cats);
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final List<IncidentCategory> cats;
}
