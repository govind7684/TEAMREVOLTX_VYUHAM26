import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/workflow.dart';
import '../../services/location_service.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../map/map_utils.dart';
import '../map/osm_map.dart';

/// Citizens see open problems near them in a limited form (no descriptions,
/// no names, no photos) and can add their voice with "I see this too".
class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});
  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  LatLng? _here;
  List<PublicIncident>? _list;
  String? _error;
  bool _busy = false;

  bool _cityWide = false;

  /// Everything open in the city. Needs no GPS.
  Future<void> _loadCity() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final list = await ref.read(workflowRepositoryProvider).openCityWide(ref.read(sessionProvider)!);
      if (mounted) {
        setState(() {
          _cityWide = true;
          _here = null;
          _list = list;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // Show something straight away; "Use my location" narrows it down.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCity());
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await const LocationService().currentPosition();
      final list = await ref.read(workflowRepositoryProvider).nearby(ref.read(sessionProvider)!,
          latitude: p.latitude, longitude: p.longitude);
      if (mounted) {
        setState(() {
          _cityWide = false;
          _here = p;
          _list = list;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _support(PublicIncident p) async {
    try {
      final n = await ref.read(workflowRepositoryProvider).support(ref.read(sessionProvider)!, p.id);
      ref.read(refreshTickProvider.notifier).state++;
      if (mounted) showMessage(context, 'Thanks. $n citizens now report this problem.');
      await (_cityWide ? _loadCity() : _load());
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: const Text('Problems around you')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
            _cityWide
                ? 'Open problems across the city. You only see the kind of problem, the area '
                    'and how many people reported it. Reporter names, descriptions and photos stay private.'
                : 'Open problems within 1.5 km of you. You only see the kind of problem, the area '
                    'and how many people reported it. Reporter names, descriptions and photos stay private.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.my_location),
            label: Text(_cityWide ? 'Near me' : 'Refresh'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _loadCity,
            icon: const Icon(Icons.public),
            label: const Text('Whole city'),
          ),
        ]),
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (list != null && !_busy) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: OsmMap(
                center: _here ?? keralaCenter,
                zoom: _here == null ? 7 : 15,
                markers: [
                  if (_here != null)
                    Marker(point: _here!, width: 24, height: 24,
                        child: const Icon(Icons.circle, color: Colors.blue, size: 18)),
                  for (final p in list)
                    if (p.latitude != null && p.longitude != null)
                      Marker(
                        point: LatLng(p.latitude!, p.longitude!),
                        width: 32,
                        height: 32,
                        child: const Icon(Icons.location_on, color: AppTheme.accent, size: 32),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (list.isEmpty)
            const EmptyState(icon: Icons.check_circle_outline, message: 'No open reports to show.'),
          for (final p in list)
            Card(
              child: ListTile(
                title: Text('${p.category.label} · ${p.areaText}'),
                subtitle: Text('${p.status.label} · '
                    '${p.distanceMeters == null ? '' : '${p.distanceMeters!.round()} m away · '}'
                    '${p.citizens} ${p.citizens == 1 ? 'citizen' : 'citizens'}'),
                trailing: p.supportedByMe
                    ? const Tooltip(message: 'You already reported or supported this',
                        child: Icon(Icons.check_circle, color: AppTheme.accent))
                    : OutlinedButton(onPressed: () => _support(p), child: const Text('I see this too')),
              ),
            ),
          const Text('Locations are rounded to about 100 m for privacy.', style: TextStyle(fontSize: 12)),
        ],
      ]),
    );
  }
}
