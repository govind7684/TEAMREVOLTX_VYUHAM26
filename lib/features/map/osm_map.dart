import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Shared OpenStreetMap view. Used by the incident map and the location picker.
///
/// Tile policy: the public OSM tile server (tile.openstreetmap.org) is for light
/// use with a valid User-Agent and visible attribution. It is fine for a demo.
/// For real traffic, self-host tiles or use a provider whose terms allow it.
class OsmMap extends StatefulWidget {
  const OsmMap({
    super.key,
    required this.center,
    required this.zoom,
    this.markers = const [],
    this.layers = const [],
    this.onTap,
    this.userPoint,
    this.focus,
    this.onLocate,
    this.locating = false,
    this.controlsBottom = 16,
  });

  final LatLng center;
  final double zoom;
  final List<Marker> markers;

  /// Extra flutter_map layers drawn under the markers (for example heat circles).
  final List<Widget> layers;
  final void Function(LatLng point)? onTap;

  /// The person's own position, drawn as a blue dot.
  final LatLng? userPoint;

  /// When this changes to a new value the map flies there (for example after
  /// "my location" is tapped).
  final LatLng? focus;

  /// Shows a "my location" button above the zoom buttons when set.
  final VoidCallback? onLocate;
  final bool locating;

  /// Distance of the control buttons from the bottom edge.
  final double controlsBottom;

  @override
  State<OsmMap> createState() => _OsmMapState();
}

class _OsmMapState extends State<OsmMap> {
  bool _tilesFailed = false;
  final _controller = MapController();

  @override
  void didUpdateWidget(OsmMap old) {
    super.didUpdateWidget(old);
    if (widget.focus != null && widget.focus != old.focus) {
      try {
        _controller.move(widget.focus!, 15);
      } catch (_) {}
    } else if (old.center != widget.center || old.zoom != widget.zoom) {
      // Controller is only ready after the first build.
      try {
        _controller.move(widget.center, widget.zoom);
      } catch (_) {}
    }
  }

  void _zoom(double delta) {
    try {
      final cam = _controller.camera;
      _controller.move(cam.center, (cam.zoom + delta).clamp(5.0, 18.0));
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      FlutterMap(
        mapController: _controller,
        options: MapOptions(
          initialCenter: widget.center,
          initialZoom: widget.zoom,
          minZoom: 5,
          maxZoom: 18,
          onTap: widget.onTap == null ? null : (_, p) => widget.onTap!(p),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.civinex_ai',
            errorTileCallback: (tile, error, stack) {
              if (!_tilesFailed && mounted) {
                // Defer: this can fire while the framework is building.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _tilesFailed = true);
                });
              }
            },
          ),
          ...widget.layers,
          MarkerLayer(markers: widget.markers),
          if (widget.userPoint != null)
            MarkerLayer(markers: [
              Marker(
                point: widget.userPoint!,
                width: 26,
                height: 26,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2F80ED),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
                  ),
                ),
              ),
            ]),
          const RichAttributionWidget(
            attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
          ),
        ],
      ),
      Positioned(
        right: 12,
        bottom: widget.controlsBottom,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.onLocate != null) ...[
            _MapButton(
              tooltip: 'My location',
              onPressed: widget.locating ? null : widget.onLocate,
              child: widget.locating
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
            const SizedBox(height: 8),
          ],
          _MapButton(tooltip: 'Zoom in', onPressed: () => _zoom(1), child: const Icon(Icons.add)),
          const SizedBox(height: 2),
          _MapButton(tooltip: 'Zoom out', onPressed: () => _zoom(-1), child: const Icon(Icons.remove)),
        ]),
      ),
      if (_tilesFailed)
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Map tiles could not load (offline?). Markers may float on a blank '
                'background. The list below still works.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.child, required this.onPressed, required this.tooltip});
  final Widget child;
  final VoidCallback? onPressed;
  final String tooltip;
  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        elevation: 2,
        child: IconButton(tooltip: tooltip, onPressed: onPressed, icon: child),
      );
}
