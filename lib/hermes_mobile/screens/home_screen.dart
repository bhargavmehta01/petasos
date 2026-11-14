import 'package:flutter/material.dart';

import '../cards/card_widgets.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../data/panels.dart';
import '../features/wave1_proactive/w1_shell.dart'; // wave1
import '../features/wave4_novel/ui/w4_home.dart'; // --- wave4 ---
import '../features/wave4_novel/w4_controller.dart'; // --- wave4 ---
import '../theme/hermes_mobile_theme.dart';
import '../widgets/common.dart';
import 'settings_screen.dart';
import 'shell.dart' show showChatActions;

/// Home: what needs you, what is running, glanceable panels, recent chats.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenChat,
    required this.onNewChat,
  });
  final void Function(HermesMobileChat) onOpenChat;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final state = HermesMobileScope.of(context);
    final c = context.hermesMobile;
    final approvals = state.pendingApprovals.entries.toList();
    final running = state.runningNow;
    final recent = state.chats.take(5).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          state.refreshChats(),
          state.refreshPanels(),
          state.wave4.refreshAll(), // --- wave4 ---
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Wave1HomeBriefCard(onOpenChat: onOpenChat), // wave1
          if (approvals.isNotEmpty) ...[
            const SectionHeader('Needs you'),
            for (final e in approvals)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: HermesMobileCardFrame(
                  onTap: () => onOpenChat(
                    HermesMobileChat(id: e.key, title: state.titleFor(e.key)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined, color: c.warning),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.titleFor(e.key),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              e.value.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Review',
                        style: TextStyle(
                          color: c.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (running.isNotEmpty) ...[
            const SectionHeader('Running now'),
            HermesMobileCardFrame(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final chat in running)
                    ListTile(
                      dense: true,
                      leading: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.accent,
                        ),
                      ),
                      title: Text(
                        chat.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        state.controllerById(chat.id)?.liveRun?.currentLine ??
                            'Working',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => onOpenChat(chat),
                    ),
                ],
              ),
            ),
          ],
          // --- wave4 ---
          Wave4HomeSection(onOpenChat: onOpenChat, urgentOnly: true),
          // --- /wave4 ---
          SectionHeader(
            'Panels',
            trailing: state.panels?.sourceLabel == null
                ? null
                : Text(
                    state.panels!.sourceLabel!,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
          ),
          PanelsGrid(
            result: state.panels,
            loading: state.panelsLoading,
            onSetup: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PanelsSettingsScreen()),
            ),
          ),
          // --- wave4 ---
          Wave4HomeSection(onOpenChat: onOpenChat),
          // --- /wave4 ---
          SectionHeader(
            'Recent chats',
            trailing: TextButton.icon(
              onPressed: onNewChat,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New'),
            ),
          ),
          if (state.chatsLoading && recent.isEmpty)
            const SkeletonCard(height: 160)
          else if (recent.isEmpty)
            HermesMobileCardFrame(
              child: Text(
                state.chatsError == null
                    ? 'No chats yet. Start one and it will show up here.'
                    : 'Could not reach Hermes: ${state.chatsError}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            HermesMobileCardFrame(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final chat in recent)
                    ChatTile(
                      chat: chat,
                      running: state.runningChats.contains(chat.id) ||
                          chat.isActive,
                      needsYou: state.pendingApprovals.containsKey(chat.id),
                      onTap: () => onOpenChat(chat),
                      onLongPress: () => showChatActions(context, chat),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Two-column panel grid: stat/progress take half width, the rest full.
class PanelsGrid extends StatelessWidget {
  const PanelsGrid({
    super.key,
    required this.result,
    required this.loading,
    required this.onSetup,
  });
  final PanelsResult? result;
  final bool loading;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null || (loading && r.panels.isEmpty)) {
      return const Row(
        children: [
          Expanded(child: SkeletonCard(height: 110)),
          SizedBox(width: 10),
          Expanded(child: SkeletonCard(height: 110)),
        ],
      );
    }
    if (!r.configured) {
      return HermesMobileCardFrame(
        title: 'Show your Hermes panels here',
        icon: Icons.dashboard_customize_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Agents and cron jobs publish small status cards as JSON in '
              '\$HERMES_HOME/panels/. The phone reads them over HTTP: turn on '
              'the Hermes dashboard source (needs the home-dashboard plugin) '
              'or set a URL that returns the panel list.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onSetup, child: const Text('Set up panels')),
          ],
        ),
      );
    }
    if (r.panels.isEmpty) {
      return HermesMobileCardFrame(
        child: Row(
          children: [
            Expanded(
              child: Text(
                r.error == null
                    ? 'No panels published yet.'
                    : 'Could not load panels: ${r.error}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            TextButton(onPressed: onSetup, child: const Text('Settings')),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final half = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final p in r.panels)
              SizedBox(
                width: p.kind == PanelKind.stat || p.kind == PanelKind.progress
                    ? half
                    : constraints.maxWidth,
                child: PanelCard(panel: p),
              ),
          ],
        );
      },
    );
  }
}

class PanelCard extends StatelessWidget {
  const PanelCard({super.key, required this.panel});
  final HermesMobilePanel panel;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final p = panel;
    final stale = p.isStale(DateTime.now());
    final t = Theme.of(context).textTheme;
    Widget body;
    switch (p.kind) {
      case PanelKind.stat:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: p.value ?? '—',
                    style: t.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (p.unit != null)
                    TextSpan(
                      text: ' ${p.unit}',
                      style: t.bodySmall,
                    ),
                ],
              ),
            ),
            if (p.trend != null)
              Text(
                p.trend!,
                style: t.bodySmall?.copyWith(
                  color: p.trend!.startsWith('-')
                      ? c.danger
                      : p.trend!.startsWith('+')
                      ? c.success
                      : c.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        );
      case PanelKind.progress:
        final v = p.progress ?? 0;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${(v * 100).round()}%',
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: c.surfaceMuted,
                color: v >= 1 ? c.success : c.accent,
              ),
            ),
          ],
        );
      case PanelKind.list:
        body = Column(
          children: [
            for (final it in p.items.take(6))
              InkWell(
                onTap: it.url == null ? null : () => openExternal(context, it.url!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          it.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium,
                        ),
                      ),
                      if (it.value != null)
                        Text(
                          it.value!,
                          style: t.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      case PanelKind.table:
        body = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 30,
            dataRowMinHeight: 30,
            dataRowMaxHeight: 36,
            horizontalMargin: 0,
            columnSpacing: 20,
            dividerThickness: 0.5,
            headingTextStyle: t.labelMedium?.copyWith(color: c.textSecondary),
            columns: [for (final col in p.columns) DataColumn(label: Text(col))],
            rows: [
              for (final row in p.rows.take(6))
                DataRow(
                  cells: [
                    for (var i = 0; i < p.columns.length; i++)
                      DataCell(Text(i < row.length ? row[i] : '')),
                  ],
                ),
            ],
          ),
        );
      case PanelKind.text:
        body = Text(
          p.text ?? '',
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: t.bodyMedium,
        );
    }

    return Opacity(
      opacity: stale ? 0.6 : 1,
      child: HermesMobileCardFrame(
        onTap: p.url == null ? null : () => openExternal(context, p.url!),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelLarge?.copyWith(
                      color: c.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (p.url != null)
                  Icon(Icons.north_east_rounded, size: 13, color: c.textTertiary),
              ],
            ),
            if (p.subtitle != null && p.kind != PanelKind.stat)
              Text(
                p.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall,
              ),
            const SizedBox(height: 8),
            body,
            const SizedBox(height: 8),
            Text(
              [
                if (stale) 'stale',
                if (p.updatedAt != null) relativeTime(p.updatedAt),
                ?p.profile,
                ?p.source,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.labelSmall?.copyWith(color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
