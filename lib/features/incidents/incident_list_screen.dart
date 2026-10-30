import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import 'incident_detail_screen.dart';

class IncidentListScreen extends ConsumerStatefulWidget {
  const IncidentListScreen(
      {super.key, required this.title, this.initialQuery = '', this.standalone = false});
  final String title;
  final String initialQuery;

  /// True when pushed as its own page (adds an app bar); false inside the shell.
  final bool standalone;
  @override
  ConsumerState<IncidentListScreen> createState() => _State();
}

class _State extends ConsumerState<IncidentListScreen> {
  late String _query = widget.initialQuery.trim().toLowerCase();
  late final _search = TextEditingController(text: widget.initialQuery);
  IncidentStatus? _status;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(incidentsProvider);
    final body = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(children: [
          if (!widget.standalone) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.title, style: Theme.of(context).textTheme.headlineSmall),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _search,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search), labelText: 'Search ID, area or text'),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                    label: const Text('All'),
                    selected: _status == null,
                    onSelected: (_) => setState(() => _status = null)),
              ),
              for (final s in IncidentStatus.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: Text(s.label),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s)),
                ),
            ]),
          ),
        ]),
      ),
      Expanded(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(incidentsProvider)),
          data: (all) {
            final list = all.where((i) {
              if (_status != null && i.status != _status) return false;
              if (_query.isEmpty) return true;
              return '${i.id} ${i.locationText} ${i.description} ${i.category.label}'
                  .toLowerCase()
                  .contains(_query);
            }).toList();
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.search_off,
                message: all.isEmpty
                    ? 'Nothing here yet.'
                    : 'No reports match your search or filter.',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(incidentsProvider),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: list.length,
                itemBuilder: (_, n) => IncidentCard(
                  incident: list[n],
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => IncidentDetailScreen(incidentId: list[n].id))),
                ),
              ),
            );
          },
        ),
      ),
    ]);
    if (!widget.standalone) return body;
    return Scaffold(appBar: AppBar(title: Text(widget.title)), body: body);
  }
}
