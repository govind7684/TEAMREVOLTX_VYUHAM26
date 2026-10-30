import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart' show Marker;
import 'package:latlong2/latlong.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/service_place.dart';
import '../../services/location_service.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../map/osm_map.dart';
import 'manage_services_screen.dart';

/// Search a city or town and see the services around it: hospitals, police,
/// workshops, tyre / puncture shops and more. Places added by staff are shown
/// first and marked; the rest come from OpenStreetMap (may be incomplete).
class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key});
  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  final _query = TextEditingController();
  ServiceKind? _kind;
  List<ServicePlace>? _places;
  LatLng? _center;
  String? _where;
  String? _note;
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load(LatLng center, String label, String city) async {
    setState(() {
      _busy = true;
      _note = null;
    });
    final staff = await ref.read(servicePlacesRepositoryProvider).inCity(city);
    var osm = <ServicePlace>[];
    String? note;
    try {
      osm = await ref.read(osmPlacesProvider).around(center.latitude, center.longitude);
    } catch (e) {
      note = '${friendlyError(e)} Showing places added by staff only.';
    }
    final merged = [...staff, ...osm];
    if (!mounted) return;
    setState(() {
      _places = merged;
      _center = center;
      _where = label;
      _note = note;
      _busy = false;
    });
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < 3) {
      showMessage(context, 'Type a city or town in Kerala.', error: true);
      return;
    }
    setState(() => _busy = true);
    final hit = await ref.read(geocodingProvider).search(q);
    if (!mounted) return;
    if (hit == null) {
      setState(() => _busy = false);
      showMessage(context, 'Could not find "$q" in Kerala. Check the spelling and your internet.',
          error: true);
      return;
    }
    await _load(LatLng(hit.latitude, hit.longitude), hit.name, q);
  }

  Future<void> _near() async {
    setState(() => _busy = true);
    try {
      final p = await const LocationService().currentPosition();
      final address = await ref.read(geocodingProvider).reverse(p.latitude, p.longitude);
      await _load(p, address ?? 'Your location', address?.split(',').last.trim() ?? '');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider)!;
    ref.watch(refreshTickProvider);
    final scheme = Theme.of(context).colorScheme;
    final shown = (_places ?? const <ServicePlace>[])
        .where((p) => _kind == null || p.kind == _kind)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('City services'), actions: [
        if (user.canManageServices)
          IconButton(
            tooltip: 'Manage services',
            icon: const Icon(Icons.edit_location_alt_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ManageServicesScreen())),
          ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: 'City or town',
            hintText: 'for example Thiruvananthapuram',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
                tooltip: 'Use my location', icon: const Icon(Icons.my_location), onPressed: _busy ? null : _near),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy ? null : _search, child: const Text('Find services')),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                  label: const Text('All'), selected: _kind == null, onSelected: (_) => setState(() => _kind = null)),
            ),
            for (final k in ServiceKind.values.where((k) => k != ServiceKind.other))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  avatar: Icon(k.icon, size: 16),
                  label: Text(k.label),
                  selected: _kind == k,
                  onSelected: (s) => setState(() => _kind = s ? k : null),
                ),
              ),
          ]),
        ),
        if (_places == null) ...[
          const SizedBox(height: 24),
          const EmptyState(
              icon: Icons.travel_explore,
              message: 'Search a city or town to see hospitals, police, workshops, '
                  'puncture shops and more nearby.'),
        ] else ...[
          const SizedBox(height: 8),
          Text('Around $_where', style: Theme.of(context).textTheme.titleMedium),
          if (_note != null) Text(_note!, style: TextStyle(color: scheme.error, fontSize: 12)),
          const SizedBox(height: 8),
          if (_center != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 240,
                child: OsmMap(
                  center: _center!,
                  zoom: 13.5,
                  markers: [
                    for (final p in shown.where((p) => p.latitude != null && p.longitude != null))
                      Marker(
                        point: LatLng(p.latitude!, p.longitude!),
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () => _details(p),
                          child: Icon(p.kind.icon,
                              size: 28, color: p.staff ? AppTheme.accentDeep : scheme.primary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
              'Teal icons were added by city staff. Other places come from OpenStreetMap, which is '
              'made by volunteers and may be missing some places. Call before you travel.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            const EmptyState(icon: Icons.search_off, message: 'No places found for this filter.')
          else
            for (final p in shown) _PlaceCard(place: p, onTap: () => _details(p)),
        ],
      ]),
    );
  }

  void _details(ServicePlace p) => showModalBottomSheet<void>(
        context: context,
        builder: (_) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: Theme.of(context).textTheme.titleLarge),
            Text('${p.kind.label} · ${p.staff ? 'Added by city staff' : 'OpenStreetMap'}'),
            const SizedBox(height: 8),
            if (p.address != null) Text(p.address!),
            if (p.hours != null) Text('Hours: ${p.hours}'),
            if (p.phone != null)
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: p.phone!));
                  showMessage(context, 'Phone number copied.');
                },
                icon: const Icon(Icons.copy, size: 16),
                label: Text(p.phone!),
              )
            else
              const Text('No phone number listed.'),
          ]),
        ),
      );
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.onTap});
  final ServicePlace place;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = place;
    final d = p.distanceMeters;
    return Card(
      child: ListTile(
        leading: Icon(p.kind.icon, color: p.staff ? AppTheme.accentDeep : null),
        title: Text(p.name),
        subtitle: Text([
          p.kind.label,
          if (d != null) d < 1000 ? '${d.round()} m' : '${(d / 1000).toStringAsFixed(1)} km',
          if (p.phone != null) p.phone!,
        ].join(' · ')),
        trailing: p.staff ? const Icon(Icons.verified_outlined, size: 20) : null,
        onTap: onTap,
      ),
    );
  }
}
