import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/utils/validators.dart';
import '../../shared/widgets/common.dart';
import 'map_utils.dart';
import 'osm_map.dart';

/// Full-screen picker. Returns the chosen [LatLng] via Navigator.pop, or null
/// if the person goes back without confirming.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initial});
  final LatLng? initial;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
  }

  void _confirm() {
    final p = _picked!;
    if (!Validators.inKerala(p.latitude, p.longitude)) {
      showMessage(context, 'That spot is outside Kerala. Pick a location inside Kerala.',
          error: true);
      return;
    }
    Navigator.of(context).pop(p);
  }

  @override
  Widget build(BuildContext context) {
    final p = _picked;
    return Scaffold(
      appBar: AppBar(title: const Text('Pick location')),
      body: Column(children: [
        Expanded(
          child: OsmMap(
            center: widget.initial ?? keralaCenter,
            zoom: widget.initial == null ? 8 : 15,
            onTap: (point) => setState(() => _picked = point),
            markers: [
              if (p != null)
                Marker(
                  point: p,
                  width: 40,
                  height: 40,
                  child: Icon(Icons.location_on,
                      size: 40, color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Text(p == null
                    ? 'Tap the map to drop a pin.'
                    : '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'),
              ),
              FilledButton(
                onPressed: p == null ? null : _confirm,
                child: const Text('Use this location'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
