import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/incident.dart';
import '../../core/utils/geo.dart';
import '../../services/intel/clustering.dart';
import '../../services/location_service.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../incidents/incident_detail_screen.dart';
import 'map_utils.dart';
import 'osm_map.dart';

enum MapMode { pins, clusters, heat }

enum _Filter { all, open, progress, resolved }

/// Map of the incidents the signed-in user is allowed to see (same provider as
/// the lists, so role and department limits apply automatically). Tap a pin to
/// see it in the card at the bottom. Pins / Groups / Heat live in the menu at
/// the top right; Heat is for staff.
class IncidentMapScreen extends ConsumerStatefulWidget {
  const IncidentMapScreen({super.key, this.initialMode = MapMode.pins, this.showTitle = true});
  final MapMode initialMode;
  final bool showTitle;
  @override
  ConsumerState<IncidentMapScreen> createState() => _IncidentMapScreenState();
}

class _IncidentMapScreenState extends ConsumerState<IncidentMapScreen> {
  late MapMode _mode = widget.initialMode;
  _Filter _filter = _Filter.all;
  LatLng? _me;
  LatLng? _focus;
  bool _flip = false;
  bool _locating = false;
  String? _selectedId;

  // Area search (staff): reports whose address contains the text, or that lie within
  // [_areaRadius] metres of the place found on OpenStreetMap.
  final _area = TextEditingController();
  String _areaText = '';
  LatLng? _areaPoint;
  String? _areaName;
  bool _searching = false;
  static const _areaRadius = 3000.0;

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  Future<void> _searchArea(String q) async {
    final text = q.trim();
    setState(() {
      _areaText = text.toLowerCase();
      _areaPoint = null;
      _areaName = null;
      _selectedId = null;
    });
    if (text.isEmpty) return;
    setState(() => _searching = true);
    final hit = await ref.read(geocodingProvider).search(text);
    if (!mounted) return;
    setState(() {
      _searching = false;
      if (hit != null) {
        _areaPoint = LatLng(hit.latitude, hit.longitude);
        _areaName = hit.name;
        _flip = !_flip;
        _focus = LatLng(hit.latitude, hit.longitude + (_flip ? 0.00001 : 0));
      }
    });
  }

  void _clearArea() {
    _area.clear();
    setState(() {
      _areaText = '';
      _areaPoint = null;
      _areaName = null;
    });
  }

  bool _inArea(Incident i) {
    if (_areaText.isEmpty) return true;
    if (i.locationText.toLowerCase().contains(_areaText)) return true;
    final p = _areaPoint;
    return p != null &&
        i.hasCoordinates &&
        distanceMeters(p.latitude, p.longitude, i.latitude!, i.longitude!) <= _areaRadius;
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      final p = await const LocationService().currentPosition();
      if (mounted) {
        setState(() {
          _me = p;
          // A tiny nudge each tap so the map re-centres even at the same spot.
          _flip = !_flip;
          _focus = LatLng(p.latitude, p.longitude + (_flip ? 0.00001 : 0));
        });
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  bool _matches(Incident i) {
    switch (_filter) {
      case _Filter.all:
        return i.status != IncidentStatus.rejected && i.status != IncidentStatus.withdrawn;
      case _Filter.open:
        return i.status == IncidentStatus.submitted ||
            i.status == IncidentStatus.underReview ||
            i.status == IncidentStatus.assigned;
      case _Filter.progress:
        return i.status == IncidentStatus.inProgress;
      case _Filter.resolved:
        return i.status == IncidentStatus.resolved || i.status == IncidentStatus.closed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(incidentsProvider);
    final user = ref.watch(sessionProvider)!;
    final scheme = Theme.of(context).colorScheme;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(incidentsProvider)),
      data: (all) {
        final shown = all
            .where((i) => _matches(i) && _inArea(i) && !(user.isStaff && i.isLinkedChild))
            .toList();
        final onMap = mappable(shown);
        final noCoords = shown.length - onMap.length;
        final mode = user.isStaff || _mode != MapMode.heat ? _mode : MapMode.pins;
        Incident? selected;
        for (final i in onMap) {
          if (i.id == _selectedId) selected = i;
        }

        void openDetail(Incident i) => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => IncidentDetailScreen(incidentId: i.id)));

        final clusters = const GeoClusterer().cluster(onMap);

        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(children: [
                    for (final f in _Filter.values)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _filter = f;
                            _selectedId = null;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _filter == f ? scheme.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              const {
                                _Filter.all: 'All',
                                _Filter.open: 'Open',
                                _Filter.progress: 'In Progress',
                                _Filter.resolved: 'Resolved',
                              }[f]!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: _filter == f ? scheme.onPrimary : scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
              PopupMenuButton<MapMode>(
                tooltip: 'Map view',
                icon: const Icon(Icons.tune),
                initialValue: mode,
                onSelected: (m) => setState(() => _mode = m),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: MapMode.pins, child: Text('Pins')),
                  const PopupMenuItem(value: MapMode.clusters, child: Text('Groups of nearby reports')),
                  if (user.isStaff) const PopupMenuItem(value: MapMode.heat, child: Text('Heat map (density)')),
                ],
              ),
            ]),
          ),
          if (user.isStaff)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _area,
                textInputAction: TextInputAction.search,
                onSubmitted: _searchArea,
                decoration: InputDecoration(
                  hintText: 'Search an area, e.g. Kowdiar or Edappally',
                  prefixIcon: const Icon(Icons.travel_explore),
                  isDense: true,
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : (_areaText.isEmpty
                          ? null
                          : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: _clearArea)),
                ),
              ),
            ),
          if (user.isStaff && _areaText.isNotEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _areaName != null
                      ? '${shown.length} report${shown.length == 1 ? '' : 's'} in or within 3 km of $_areaName'
                      : '${shown.length} report${shown.length == 1 ? '' : 's'} with "$_areaText" in the address '
                          '(place not found on the map, or offline)',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          if (mode == MapMode.heat)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Heat shows where reports are concentrated (higher priority counts more). '
                  'It is a density map of reports, not a forecast.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(children: [
                  Positioned.fill(
                    child: OsmMap(
                      center: _me ?? centerFor(onMap),
                      zoom: _me != null ? 14 : zoomFor(onMap),
                      userPoint: _me,
                      focus: _focus,
                      onLocate: _locate,
                      locating: _locating,
                      controlsBottom: selected != null ? 120 : 24,
                      onTap: (_) => setState(() => _selectedId = null),
                      layers: [
                        if (mode == MapMode.heat)
                          CircleLayer(circles: [
                            for (final h in GeoClusterer.heat(clusters))
                              CircleMarker(
                                point: LatLng(h.cluster.latitude, h.cluster.longitude),
                                radius: 180 + 220 * h.intensity,
                                useRadiusInMeter: true,
                                color: Color.lerp(Colors.amber, Colors.red, h.intensity)!
                                    .withValues(alpha: 0.18 + 0.32 * h.intensity),
                              ),
                          ]),
                      ],
                      markers: mode == MapMode.clusters
                          ? [
                              for (final c in clusters)
                                Marker(
                                  point: LatLng(c.latitude, c.longitude),
                                  width: 48,
                                  height: 48,
                                  child: GestureDetector(
                                    onTap: () => _clusterSheet(context, c, openDetail),
                                    child: CircleAvatar(
                                      backgroundColor: AppTheme.navy,
                                      child: Text('${c.count}',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                ),
                            ]
                          : mode == MapMode.heat
                              ? const []
                              : [
                                  for (final i in onMap)
                                    Marker(
                                      point: LatLng(i.latitude!, i.longitude!),
                                      width: 44,
                                      height: 44,
                                      alignment: Alignment.topCenter,
                                      child: GestureDetector(
                                        onTap: () => setState(() => _selectedId = i.id),
                                        child: Icon(
                                          Icons.location_on,
                                          size: i.id == _selectedId ? 48 : 40,
                                          color: AppTheme.priorityColor(i.priority.name),
                                          semanticLabel: '${i.category.label}, ${i.priority.label} priority',
                                        ),
                                      ),
                                    ),
                                ],
                    ),
                  ),
                  if (onMap.isEmpty)
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 12,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            shown.isEmpty
                                ? 'No reports to show here yet. Reports with a location appear as pins.'
                                : '${shown.length} report${shown.length == 1 ? '' : 's'}, none with a location.',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    )
                  else if (noCoords > 0)
                    Positioned(
                      left: 12,
                      top: 8,
                      child: Chip(
                        label: Text('$noCoords without a location not shown', style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  if (selected != null)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: _SelectedCard(incident: selected, onTap: () => openDetail(selected!)),
                    ),
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }

  void _clusterSheet(BuildContext context, Cluster c, void Function(Incident) open) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ListView(padding: const EdgeInsets.all(16), children: [
        Text('${c.count} report${c.count == 1 ? '' : 's'} within 250 m',
            style: Theme.of(ctx).textTheme.titleLarge),
        Text('Mostly ${c.dominantCategory.label}', style: Theme.of(ctx).textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final i in c.items)
          IncidentCard(
              incident: i,
              onTap: () {
                Navigator.pop(ctx);
                open(i);
              }),
      ]),
    );
  }
}

class _SelectedCard extends StatelessWidget {
  const _SelectedCard({required this.incident, required this.onTap});
  final Incident incident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = incident;
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (i.status) {
      IncidentStatus.inProgress => ('In progress', AppTheme.ember),
      IncidentStatus.resolved || IncidentStatus.closed => ('Resolved', const Color(0xFF2FB36B)),
      _ => ('Open', AppTheme.alert),
    };
    final photo = i.photoPath;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: photo != null && File(photo).existsSync()
                    ? Image.file(File(photo), fit: BoxFit.cover)
                    : Container(
                        color: scheme.primary.withValues(alpha: 0.15),
                        child: Icon(Icons.report_problem_outlined, color: scheme.primary)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.category.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(i.locationText,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 6),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                    child: Text(label,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  Text(timeAgo(i.createdAt), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}
