import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/models/service_place.dart';
import '../../services/location_service.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../map/location_picker_screen.dart';

final _managedProvider = FutureProvider.autoDispose<List<ServicePlace>>((ref) {
  ref.watch(refreshTickProvider);
  return ref.watch(servicePlacesRepositoryProvider).all();
});

/// For administrators and officers an administrator has allotted: add, correct
/// and remove the places citizens see in City services. Nothing is pre-filled.
class ManageServicesScreen extends ConsumerWidget {
  const ManageServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(sessionProvider)!;
    if (!me.canManageServices) {
      return Scaffold(
          appBar: AppBar(title: const Text('Manage services')),
          body: const EmptyState(
              icon: Icons.lock_outline,
              message: 'An administrator must allot you services access first.'));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Manage services')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add place'),
      ),
      body: ref.watch(_managedProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(_managedProvider)),
            data: (list) => list.isEmpty
                ? const EmptyState(
                    icon: Icons.add_business_outlined,
                    message: 'No places added yet. Add hospitals, police stations, workshops and '
                        'others that OpenStreetMap is missing or has wrong.')
                : ListView(padding: const EdgeInsets.only(bottom: 90), children: [
                    for (final p in list)
                      ListTile(
                        leading: Icon(p.kind.icon),
                        title: Text(p.name),
                        subtitle: Text('${p.kind.label} · ${p.city}${p.phone == null ? '' : ' · ${p.phone}'}'),
                        onTap: () => _edit(context, ref, p),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _remove(context, ref, p),
                        ),
                      ),
                  ]),
          ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, ServicePlace p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${p.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(servicePlacesRepositoryProvider).delete(actor: ref.read(sessionProvider)!, id: p.id);
      ref.read(refreshTickProvider.notifier).state++;
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, ServicePlace? existing) async {
    final name = TextEditingController(text: existing?.name);
    final city = TextEditingController(text: existing?.city);
    final phone = TextEditingController(text: existing?.phone);
    final address = TextEditingController(text: existing?.address);
    final hours = TextEditingController(text: existing?.hours);
    var kind = existing?.kind ?? ServiceKind.hospital;
    LatLng? point = existing?.latitude == null ? null : LatLng(existing!.latitude!, existing.longitude!);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(existing == null ? 'Add place' : 'Edit place'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              DropdownButtonFormField<ServiceKind>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [for (final k in ServiceKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
                onChanged: (v) => set(() => kind = v ?? kind),
              ),
              const SizedBox(height: 8),
              TextField(controller: city, decoration: const InputDecoration(labelText: 'City or town')),
              const SizedBox(height: 8),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone (optional)')),
              const SizedBox(height: 8),
              TextField(controller: address, decoration: const InputDecoration(labelText: 'Address (optional)')),
              const SizedBox(height: 8),
              TextField(
                  controller: hours,
                  decoration: const InputDecoration(labelText: 'Opening hours (optional)', hintText: '24 hours')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: Text(point == null
                        ? 'No map position yet'
                        : '${point!.latitude.toStringAsFixed(5)}, ${point!.longitude.toStringAsFixed(5)}')),
                IconButton(
                  tooltip: 'Use my GPS',
                  icon: const Icon(Icons.my_location),
                  onPressed: () async {
                    try {
                      final p = await const LocationService().currentPosition();
                      set(() => point = p);
                    } catch (e) {
                      if (c.mounted) showMessage(c, friendlyError(e), error: true);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Pick on map',
                  icon: const Icon(Icons.map_outlined),
                  onPressed: () async {
                    final r = await Navigator.of(c).push<LatLng>(MaterialPageRoute(
                        builder: (_) => LocationPickerScreen(initial: point)));
                    if (r != null) set(() => point = r);
                  },
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final values = (name.text, city.text, phone.text, address.text, hours.text);
    for (final t in [name, city, phone, address, hours]) {
      t.dispose();
    }
    if (ok != true) return;
    try {
      await ref.read(servicePlacesRepositoryProvider).save(
            actor: ref.read(sessionProvider)!,
            id: existing?.id,
            name: values.$1,
            kind: kind,
            city: values.$2,
            phone: values.$3,
            address: values.$4,
            hours: values.$5,
            latitude: point?.latitude,
            longitude: point?.longitude,
          );
      ref.read(refreshTickProvider.notifier).state++;
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }
}
