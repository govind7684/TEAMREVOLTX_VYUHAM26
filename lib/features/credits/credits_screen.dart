import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/credits.dart';
import '../../shared/widgets/common.dart';
import '../../state/providers.dart';
import '../incidents/incident_detail_screen.dart';

/// A citizen's civic credit points: level, how they were earned, and the rules.
class CreditsScreen extends ConsumerWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Civic credit points')),
      body: ref.watch(creditsProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(creditsProvider)),
            data: (c) => ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c.total} points', style: Theme.of(context).textTheme.headlineMedium),
                    Text(c.level, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800)),
                    if (c.toNext != null) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                          value: () {
                            final cur = Credits.levelFor(c.total).$2;
                            final nxt = c.total + c.toNext!;
                            return (c.total - cur) / (nxt - cur);
                          }()),
                      const SizedBox(height: 4),
                      Text('${c.toNext} more for ${c.nextLevel}', style: const TextStyle(fontSize: 12)),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Text('How you earn points', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const _Rule('Report a problem', '+${Credits.perReport}', 'up to ${Credits.dailyCap} reports a day'),
              const _Rule('Take the photo live with the camera', '+${Credits.liveBonus}', 'not for flagged photos'),
              const _Rule('The city takes it up', '+${Credits.acceptedBonus}', 'when staff assign or start work'),
              const _Rule('The problem is resolved', '+${Credits.resolvedBonus}', ''),
              const _Rule('Your report matches someone else’s and staff confirm it', '+${Credits.confirmedSame}', ''),
              const _Rule('Say whether the fix worked', '+${Credits.feedbackBonus}', 'in the report’s feedback'),
              const SizedBox(height: 4),
              Text(
                  'Rejected or withdrawn reports earn nothing. Points are counted from your own reports, '
                  'cannot be edited, and are recognition only: they have no cash value.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Text('History', style: Theme.of(context).textTheme.titleMedium),
              if (c.events.isEmpty)
                const EmptyState(
                    icon: Icons.emoji_events_outlined,
                    message: 'No points yet. Report a problem and they will appear here.')
              else
                for (final e in c.events)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text(e.title),
                    subtitle: Text('${e.incidentId ?? ''} · ${formatDate(e.at)}'),
                    trailing: Text('+${e.points}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    onTap: e.incidentId == null
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => IncidentDetailScreen(incidentId: e.incidentId!))),
                  ),
            ]),
          ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule(this.what, this.pts, this.note);
  final String what, pts, note;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 38, child: Text(pts, style: const TextStyle(fontWeight: FontWeight.w800))),
          Expanded(child: Text(note.isEmpty ? what : '$what ($note)')),
        ]),
      );
}
