import 'package:flutter/material.dart';

import '../../core/constants/brand.dart';
import '../../shared/brand/brand_widgets.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _steps = [
    ('Report', 'Citizens describe the problem, add a photo and drop a pin on the map.'),
    ('Triage', 'Keyword rules suggest a category, department and an explainable priority score. '
        'They are rules, not a trained model, and every suggestion can be overridden.'),
    ('Respond', 'Officers assign, update and resolve reports. Every status change and override is logged.'),
    ('Learn', 'Analytics, FloodGuard and RoadVision turn the same reports into workload, risk and repair priorities.'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        HeroBox(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const BrandMark(size: 56),
            const SizedBox(height: 16),
            Text(Brand.appName,
                style: t.headlineMedium?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            const Text(Brand.tagline, style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            const EventBadge(onDark: true),
            const SizedBox(height: 8),
            const Text(Brand.eventLine, style: TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 20),
        Text('What it does', style: t.titleLarge),
        const SizedBox(height: 4),
        const Text(
          'One platform for civic issues in Kerala: citizens report, officers respond, '
          'and everyone sees the same shared record instead of separate apps.',
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_steps[i].$1, style: t.titleSmall),
                  Text(_steps[i].$2),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        Text('Built to run at zero cost', style: t.titleLarge),
        const SizedBox(height: 4),
        const Text(
          'Open-source Flutter app with a local SQLite database, OpenStreetMap maps and no paid '
          'APIs or subscriptions. Data stays on the device.',
        ),
        if (Brand.teamName.isNotEmpty || Brand.teamMembers.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(Brand.teamName.isEmpty ? 'Team' : Brand.teamName, style: t.titleLarge),
          const SizedBox(height: 4),
          for (final m in Brand.teamMembers) Text(m),
        ],
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'CIVINEX AI is a hackathon project. It is not an emergency dispatch system and '
              'is not an official product of the event or its host.',
              style: t.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text('Version ${Brand.version}', style: t.bodySmall)),
      ]),
    );
  }
}
