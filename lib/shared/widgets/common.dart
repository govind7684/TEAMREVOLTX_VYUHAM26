import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/incident.dart';

final _dateFmt = DateFormat('d MMM y, h:mm a');
String formatDate(DateTime d) => _dateFmt.format(d);

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
}

class PriorityChip extends StatelessWidget {
  const PriorityChip(this.priority, {super.key});
  final Priority priority;
  @override
  Widget build(BuildContext context) {
    final c = AppTheme.priorityColor(priority.name);
    return Chip(
      label: Text(priority.label, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
      side: BorderSide(color: c),
      backgroundColor: c.withValues(alpha: 0.08),
      visualDensity: VisualDensity.compact,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.error_outline,
        message: friendlyError(error),
        action: FilledButton(onPressed: onRetry, child: const Text('Retry')),
      );
}

class IncidentCard extends StatelessWidget {
  const IncidentCard({super.key, required this.incident, required this.onTap});
  final Incident incident;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: onTap,
          title: Text(incident.category.label),
          subtitle: Text(
            '${incident.id} · ${incident.status.label}\n${incident.locationText}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PriorityChip(incident.priority),
            ],
          ),
        ),
      );
}

/// "just now", "5 min ago", "2 h ago", "3 d ago", then a date.
String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return DateFormat('d MMM').format(t);
}

/// Disposes text controllers after a dialog has finished closing. Disposing them
/// the moment showDialog returns can happen while the dialog is still animating
/// away, which crashes with "'_dependents.isEmpty' is not true".
void disposeLater(Iterable<ChangeNotifier> items) {
  final list = items.toList();
  Future<void>.delayed(const Duration(milliseconds: 600), () {
    for (final i in list) {
      i.dispose();
    }
  });
}
