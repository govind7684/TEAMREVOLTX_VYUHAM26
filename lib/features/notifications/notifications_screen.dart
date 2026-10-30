import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/common.dart';
import '../../state/providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          ErrorState(error: e, onRetry: () => ref.invalidate(notificationsProvider)),
      data: (list) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
                child: Text('Notifications',
                    style: Theme.of(context).textTheme.headlineSmall)),
            TextButton(
              onPressed: list.any((n) => !n.isRead)
                  ? () async {
                      await ref
                          .read(incidentRepositoryProvider)
                          .markAllRead(ref.read(sessionProvider)!);
                      ref.read(refreshTickProvider.notifier).state++;
                    }
                  : null,
              child: const Text('Mark all read'),
            ),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none,
                  message: 'No notifications yet. In-app only; no push service is used.')
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, n) => ListTile(
                    leading: Icon(list[n].isRead
                        ? Icons.notifications_none
                        : Icons.notifications_active),
                    title: Text(list[n].title),
                    subtitle: Text('${list[n].body}\n${formatDate(list[n].createdAt)}'),
                    isThreeLine: true,
                  ),
                ),
        ),
      ]),
    );
  }
}
