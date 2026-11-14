import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/services/background_work_prefs.dart';
import '../../core/services/connection_manager.dart';
import '../../core/widgets/mobile_push_settings.dart';

import '../cards/card_widgets.dart';
import '../data/app_state.dart';
import '../data/live_backend.dart';
import '../data/models.dart';
import '../hermes_mobile_app.dart';
import '../theme/hermes_mobile_theme.dart';
import '../widgets/common.dart';
import '../features/wave4_novel/ui/w4_settings.dart'; // --- wave4 ---
import 'connect_screen.dart';
import 'hermes_mobile_accounts_screen.dart';
import 'skill_memory_detail.dart';
import '../features/wave3_control/memory_manager_screen.dart';
import '../features/wave2_parity/w2_settings_screen.dart'; // --- wave2 ---
// --- wave3 ---
import '../features/wave3_control/wave3_settings_section.dart';
import '../features/wave2_parity/w2_settings.dart';
// --- end wave3 ---

/// Profile and settings.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = HermesMobileScope.of(context);
    final conn = state.backend.connection;
    void push(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          HermesMobileCardFrame(
            child: Row(
              children: [
                ProfileAvatar(label: conn.label, demo: state.backend.isDemo),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conn.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        conn.endpoint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _HealthDot(future: state.backend.checkHealth()),
              ],
            ),
          ),
          const SectionHeader('Hermes'),
          _Group(
            children: [
              _Row(
                icon: Icons.dns_outlined,
                title: 'Connection',
                onTap: () => push(const ConnectionSettingsScreen()),
              ),
              _Row(
                icon: Icons.manage_accounts_outlined,
                title: 'Accounts & connectors',
                onTap: () => push(const HermesMobileAccountsScreen()),
              ),
              _Row(
                icon: Icons.schedule_rounded,
                title: 'Scheduled tasks',
                onTap: () => push(const CronListScreen()),
              ),
              _Row(
                icon: Icons.extension_outlined,
                title: 'Skills',
                onTap: () => push(const SkillsScreen()),
              ),
              _Row(
                icon: Icons.psychology_outlined,
                title: 'Memory',
                onTap: () => push(const MemoryScreen()),
              ),
              _Row(
                icon: Icons.insights_outlined,
                title: 'Usage',
                onTap: () => push(const UsageScreen()),
              ),
              _Row(
                icon: Icons.dashboard_customize_outlined,
                title: 'Home panels',
                onTap: () => push(const PanelsSettingsScreen()),
              ),
            ],
          ),
          // --- wave3 ---
          const Wave3SettingsSection(),
          // --- end wave3 ---
          // --- wave4 ---
          const Wave4SettingsGroup(),
          // --- /wave4 ---
          const SectionHeader('App'),
          _Group(
            children: [
              _Row(
                icon: Icons.palette_outlined,
                title: 'Appearance',
                onTap: () => push(const AppearanceScreen()),
              ),
              // --- wave2 ---
              _Row(
                icon: Icons.tune_rounded,
                title: 'Colors, text, voice and haptics',
                onTap: () => push(const W2AppearanceScreen()),
              ),
              // --- end wave2 ---
              _Row(
                icon: Icons.info_outline_rounded,
                title: 'About and licenses',
                onTap: () => push(const AboutScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthDot extends StatelessWidget {
  const _HealthDot({required this.future});
  final Future<bool> future;
  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return FutureBuilder<bool>(
      future: future,
      builder: (context, snap) {
        final ok = snap.data;
        final color = ok == null
            ? c.textTertiary
            : ok
            ? c.success
            : c.danger;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              ok == null
                  ? 'Checking'
                  : ok
                  ? 'Online'
                  : 'Offline',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        );
      },
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return HermesMobileCardFrame(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 52, color: c.hairline),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, size: 22),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

// ── Connection ──────────────────────────────────────────────────────────

class ConnectionSettingsScreen extends StatelessWidget {
  const ConnectionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final root = HermesMobileRoot.of(context);
    final state = HermesMobileScope.of(context);
    final conn = state.backend.connection;
    final saved = root.savedConnections;
    final active = root.activeConnection;
    final manager = root.connections;
    final activeId = active?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Connection')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          HermesMobileCardFrame(
            title: state.backend.isDemo ? 'Demo mode' : conn.label,
            icon: state.backend.isDemo
                ? Icons.science_outlined
                : Icons.dns_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv(context, 'API server', conn.endpoint),
                if (conn.dashboard != null)
                  _kv(context, 'Dashboard', conn.dashboard!),
              ],
            ),
          ),
          const SectionHeader('Saved connections'),
          _Group(
            children: [
              for (final s in saved)
                ListTile(
                  leading: Icon(
                    !state.backend.isDemo && s.id == active?.id
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: !state.backend.isDemo && s.id == active?.id
                        ? context.hermesMobile.accent
                        : null,
                  ),
                  title: Text(s.label),
                  subtitle: Text('${s.host}:${s.port}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final full =
                          (await root.connections!.loadConnectionsWithSecrets())
                              .firstWhere((c) => c.id == s.id);
                      if (!context.mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ConnectScreen(existing: full),
                        ),
                      );
                    },
                  ),
                  onTap: () async {
                    await root.useConnection(s.id);
                    if (context.mounted) {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: const Text('Add connection'),
                onTap: root.connections == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Add connection')),
                            body: const ConnectScreen(),
                          ),
                        ),
                      ),
              ),
            ],
          ),
          const SectionHeader('Background'),
          if (!state.backend.isDemo && manager != null && activeId != null)
            FutureBuilder<List<SavedConnection>>(
              future: manager.loadConnectionsWithSecrets(),
              builder: (context, snapshot) {
                final paired = snapshot.data
                    ?.where((c) => c.id == activeId)
                    .firstOrNull;
                if (paired == null) {
                  return const SizedBox.shrink();
                }
                return MobilePushSettings(
                  connection: paired,
                  connectionManager: manager,
                );
              },
            ),
          _Group(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: BackgroundWorkPrefsStore.confirmedChanges,
                builder: (context, _, _) => SwitchListTile(
                  secondary: const Icon(Icons.bolt_outlined),
                  title: const Text('Keep runs going in the background'),
                  subtitle: const Text(
                    'Shows a quiet notification while Hermes works so Android '
                    'does not cut the connection.',
                  ),
                  value: BackgroundWorkPrefsStore.confirmedEnabled,
                  onChanged: (v) => BackgroundWorkPrefsStore.setEnabled(v),
                ),
              ),
            ],
          ),
          const SectionHeader('Demo'),
          _Group(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.science_outlined),
                title: const Text('Demo mode'),
                subtitle: const Text(
                  'Sample chats, cards and panels. No server.',
                ),
                value: state.backend.isDemo,
                onChanged: kHermesMobileDemo
                    ? null
                    : (v) async {
                        if (v) {
                          await root.enterDemo();
                        } else {
                          await root.leaveDemo();
                        }
                        if (context.mounted) {
                          Navigator.of(context).popUntil((r) => r.isFirst);
                        }
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(k, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: SelectableText(v)),
      ],
    ),
  );
}

// ── Panels source ───────────────────────────────────────────────────────

class PanelsSettingsScreen extends StatefulWidget {
  const PanelsSettingsScreen({super.key});
  @override
  State<PanelsSettingsScreen> createState() => _PanelsSettingsScreenState();
}

class _PanelsSettingsScreenState extends State<PanelsSettingsScreen> {
  late final _url = TextEditingController(
    text: HermesMobileRoot.of(context).prefs.getString(LiveBackend.panelsUrlKey) ?? '',
  );
  late final _token = TextEditingController(
    text:
        HermesMobileRoot.of(context).prefs.getString(LiveBackend.panelsTokenKey) ?? '',
  );
  late bool _dashboard =
      HermesMobileRoot.of(context).prefs.getBool(LiveBackend.panelsUseDashboardKey) ??
      false;

  Future<void> _save() async {
    final prefs = HermesMobileRoot.of(context).prefs;
    await prefs.setString(LiveBackend.panelsUrlKey, _url.text.trim());
    await prefs.setString(LiveBackend.panelsTokenKey, _token.text.trim());
    await prefs.setBool(LiveBackend.panelsUseDashboardKey, _dashboard);
    if (!mounted) return;
    await HermesMobileScope.read(context).refreshPanels();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final demo = HermesMobileScope.of(context).backend.isDemo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home panels'),
        actions: [
          TextButton(onPressed: demo ? null : _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Agents publish panels as JSON files in \$HERMES_HOME/panels/<id>.json. '
            'The phone cannot read the host\'s files, so pick an HTTP source. '
            'A custom URL wins over the dashboard.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (demo)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Demo mode shows sample panels.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          HermesMobileCardFrame(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('Hermes dashboard'),
              subtitle: const Text(
                'GET /api/plugins/home-dashboard/panels (home-dashboard plugin 1.6+)',
              ),
              value: _dashboard,
              onChanged: (v) => setState(() => _dashboard = v),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Custom panels URL (optional)',
              hintText: 'https://host.tailnet.ts.net/panels.json',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Bearer token (optional)',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'The URL must return {"panels":[…]} or a JSON list of panels. '
            'Format: docs/hermes-mobile-panels.md in the app repository.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ── Scheduled tasks ─────────────────────────────────────────────────────

class CronListScreen extends StatefulWidget {
  const CronListScreen({super.key});
  @override
  State<CronListScreen> createState() => _CronListScreenState();
}

class _CronListScreenState extends State<CronListScreen> {
  Future<List<HermesMobileCronJob>>? _jobs;

  void _reload() =>
      setState(() => _jobs = HermesMobileScope.read(context).backend.listCron());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _jobs ??= HermesMobileScope.read(context).backend.listCron();
  }

  Future<void> _act(Future<void> Function() f, String done) async {
    try {
      await f();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final b = HermesMobileScope.of(context).backend;
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled tasks')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await showCronEditor(context);
          if (ok == true) _reload();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New task'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _reload();
          await _jobs;
        },
        child: FutureBuilder<List<HermesMobileCronJob>>(
          future: _jobs,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonList(count: 4);
            }
            if (snap.hasError) {
              return ListView(
                children: [
                  EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not load scheduled tasks',
                    body:
                        'Scheduled tasks come from the Hermes dashboard. Check '
                        'its URL under Connection.\n${snap.error}',
                    action: TextButton(
                      onPressed: _reload,
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              );
            }
            final jobs = snap.data ?? const [];
            if (jobs.isEmpty) {
              return ListView(
                children: const [
                  EmptyState(
                    icon: Icons.schedule_rounded,
                    title: 'No scheduled tasks',
                    body: 'Create one, or ask Hermes to schedule something.',
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: jobs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final j = jobs[i];
                final c = context.hermesMobile;
                return HermesMobileCardFrame(
                  onTap: () async {
                    final ok = await showCronEditor(context, job: j);
                    if (ok == true) _reload();
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              j.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Switch(
                            value: !j.paused,
                            onChanged: (on) => _act(() {
                              W2Haptics.selection();
                              return b.setCronPaused(j.id, !on);
                            }, on ? 'Resumed' : 'Paused'),
                          ),
                        ],
                      ),
                      Text(
                        j.schedule,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: c.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        j.prompt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              [
                                if (j.paused) 'Paused',
                                if (!j.paused && j.nextRun != null)
                                  'Next: ${j.nextRun}',
                                if (j.lastStatus != null)
                                  'Last: ${j.lastStatus}',
                              ].join(' · '),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                _act(() => b.runCron(j.id), 'Started'),
                            child: const Text('Run now'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

Future<bool?> showCronEditor(BuildContext context, {HermesMobileCronJob? job}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => HermesMobileScope(
      state: HermesMobileScope.read(context),
      child: _CronEditor(job: job),
    ),
  );
}

class _CronEditor extends StatefulWidget {
  const _CronEditor({this.job});
  final HermesMobileCronJob? job;
  @override
  State<_CronEditor> createState() => _CronEditorState();
}

class _CronEditorState extends State<_CronEditor> {
  late final _name = TextEditingController(text: widget.job?.name ?? '');
  late final _schedule = TextEditingController(
    text: widget.job?.schedule ?? 'every day at 8am',
  );
  late final _prompt = TextEditingController(text: widget.job?.prompt ?? '');
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final b = HermesMobileScope.read(context).backend;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.job == null) {
        await b.createCron(
          name: _name.text.trim(),
          schedule: _schedule.text.trim(),
          prompt: _prompt.text.trim(),
        );
      } else {
        await b.updateCron(widget.job!.id, {
          'name': _name.text.trim(),
          'schedule': _schedule.text.trim(),
          'prompt': _prompt.text.trim(),
        });
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this task?'),
        content: Text(widget.job!.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await HermesMobileScope.read(context).backend.deleteCron(widget.job!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.job == null ? 'New scheduled task' : 'Edit task',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _schedule,
            decoration: const InputDecoration(
              labelText: 'Schedule',
              helperText: 'Cron (0 7 * * *), "every 2h", or "every day at 8am"',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _prompt,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'What should Hermes do?',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: context.hermesMobile.danger),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.job != null)
                TextButton(
                  onPressed: _busy ? null : _delete,
                  style: TextButton.styleFrom(
                    foregroundColor: context.hermesMobile.danger,
                  ),
                  child: const Text('Delete'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(widget.job == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Skills / Memory / Usage ─────────────────────────────────────────────

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});
  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  Future<List<HermesMobileSkill>>? _skills;
  final Map<String, bool> _enabled = {};
  String _q = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _skills ??= HermesMobileScope.read(context).backend.listSkills();
  }

  void _reloadSkills() => setState(() {
    _skills = HermesMobileScope.read(context).backend.listSkills();
  });

  Future<void> _open(HermesMobileSkill s) async {
    final updated = await Navigator.of(context).push<HermesMobileSkill>(
      MaterialPageRoute(builder: (_) => SkillDetailScreen(skill: s)),
    );
    if (updated != null && mounted) {
      setState(() => _enabled[updated.name] = updated.enabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Skills')),
      body: SelectionArea(
        child: FutureBuilder<List<HermesMobileSkill>>(
          future: _skills,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonList();
            }
            if (snap.hasError) {
              return EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load skills',
                body: '${snap.error}',
                action: TextButton(
                  onPressed: _reloadSkills,
                  child: const Text('Retry'),
                ),
              );
            }
            final all = [
              for (final s in snap.data ?? const <HermesMobileSkill>[])
                s.copyWith(enabled: _enabled[s.name] ?? s.enabled),
            ];
            final q = _q.toLowerCase();
            final list = all
                .where(
                  (s) =>
                      q.isEmpty ||
                      s.name.toLowerCase().contains(q) ||
                      s.description.toLowerCase().contains(q) ||
                      s.category.toLowerCase().contains(q),
                )
                .toList();
            final off = all.where((s) => !s.enabled).length;
            return RefreshIndicator(
              onRefresh: () async => _reloadSkills(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                      hintText: 'Search ${all.length} skills',
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                    child: Text(
                      off == 0
                          ? 'Tap a skill to read its SKILL.md or turn it off.'
                          : '$off turned off · tap a skill to read or change it.',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  for (final s in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: HermesMobileCardFrame(
                        key: ValueKey('skill-${s.name}'),
                        onTap: () => _open(s),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.extension_outlined,
                              size: 20,
                              color: s.enabled
                                  ? context.hermesMobile.accent
                                  : context.hermesMobile.textTertiary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: s.enabled
                                              ? null
                                              : context.hermesMobile.textTertiary,
                                        ),
                                  ),
                                  if (s.description.isNotEmpty)
                                    Text(
                                      s.description,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (!s.enabled)
                                  Text(
                                    'off',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: context.hermesMobile.textTertiary,
                                        ),
                                  )
                                else if (s.category.isNotEmpty)
                                  Text(
                                    s.category,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: context.hermesMobile.textTertiary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});
  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  Future<List<HermesMobileMemoryItem>>? _items;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _items ??= HermesMobileScope.read(context).backend.listMemory();
  }

  void _reload() => setState(() {
    _items = HermesMobileScope.read(context).backend.listMemory();
  });

  Future<void> _openManager() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MemoryManagerScreen()));
    if (mounted) _reload();
  }

  Future<void> _open(HermesMobileMemoryItem i) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MemoryDetailScreen(item: i)),
    );
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory'),
        actions: [
          IconButton(
            tooltip: 'Manage memory',
            icon: const Icon(Icons.edit_note_rounded),
            onPressed: _openManager,
          ),
        ],
      ),
      body: SelectionArea(
        child: FutureBuilder<List<HermesMobileMemoryItem>>(
          future: _items,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonList();
            }
            if (snap.hasError) {
              return EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load memory',
                body:
                    'Memory is read from the dashboard (USER.md and MEMORY.md).\n${snap.error}',
                action: TextButton(
                  onPressed: _reload,
                  child: const Text('Retry'),
                ),
              );
            }
            final items = snap.data ?? const [];
            final manage = HermesMobileCardFrame(
              key: const ValueKey('memory-manager-entry'),
              onTap: _openManager,
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: context.hermesMobile.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Memory manager',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Add, edit, delete and pin entries, or turn on '
                          'incognito for a chat.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.hermesMobile.textTertiary,
                  ),
                ],
              ),
            );
            if (items.isEmpty) {
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    manage,
                    const EmptyState(
                      icon: Icons.psychology_outlined,
                      title: 'Nothing saved yet',
                      body:
                          'Hermes saves facts to USER.md and MEMORY.md as it learns.',
                    ),
                  ],
                ),
              );
            }
            final groups = <String, List<HermesMobileMemoryItem>>{};
            for (final i in items) {
              groups.putIfAbsent(i.scope ?? i.title, () => []).add(i);
            }
            String label(String scope) => switch (scope) {
              'USER.md' => 'About you · USER.md',
              'MEMORY.md' => 'Hermes notes · MEMORY.md',
              _ => scope,
            };
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _items;
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  manage,
                  for (final g in groups.entries) ...[
                    SectionHeader(
                      label(g.key),
                      trailing: Text(
                        '${g.value.length}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    for (final i in g.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: HermesMobileCardFrame(
                          onTap: () => _open(i),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      i.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      i.body,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: context.hermesMobile.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class UsageScreen extends StatelessWidget {
  const UsageScreen({super.key});

  String _n(int? v) {
    if (v == null) return '—';
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final b = HermesMobileScope.of(context).backend;
    return Scaffold(
      appBar: AppBar(title: const Text('Usage · 30 days')),
      body: FutureBuilder<HermesMobileUsage?>(
        future: b.usage(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SkeletonList(count: 3);
          }
          final u = snap.data;
          if (snap.hasError || u == null) {
            return EmptyState(
              icon: Icons.insights_outlined,
              title: 'Usage unavailable',
              body:
                  'Usage comes from the dashboard analytics.\n${snap.error ?? ''}',
            );
          }
          Widget stat(String label, String value) => Expanded(
            child: HermesMobileCardFrame(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
          final maxTokens = u.topModels.isEmpty ? 1 : u.topModels.first.value;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Row(
                children: [
                  stat('Sessions', _n(u.sessions)),
                  const SizedBox(width: 10),
                  stat(
                    'Cost',
                    u.costUsd == null
                        ? '—'
                        : '\$${u.costUsd!.toStringAsFixed(2)}',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  stat('Input tokens', _n(u.inputTokens)),
                  const SizedBox(width: 10),
                  stat('Output tokens', _n(u.outputTokens)),
                ],
              ),
              if (u.topModels.isNotEmpty) ...[
                const SectionHeader('Top models'),
                HermesMobileCardFrame(
                  child: Column(
                    children: [
                      for (final m in u.topModels)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(m.key)),
                                  Text(
                                    _n(m.value),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: m.value / maxTokens,
                                  minHeight: 5,
                                  backgroundColor: context.hermesMobile.surfaceMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ── Appearance / About ──────────────────────────────────────────────────

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final root = HermesMobileRoot.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SectionHeader('Theme'),
          HermesMobileCardFrame(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {root.themeMode},
              onSelectionChanged: (s) => root.setThemeMode(s.first),
            ),
          ),
        ],
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform().catchError(
          (_) => PackageInfo(
            appName: 'Petasos',
            packageName: 'io.github.bhargavmehta01.hermesmobile',
            version: '—',
            buildNumber: '',
          ),
        ),
        builder: (context, snap) {
          final v = snap.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              HermesMobileCardFrame(
                title: 'Petasos',
                icon: Icons.bolt_rounded,
                child: Text(
                  'Version ${v?.version ?? '…'}${v?.buildNumber.isNotEmpty == true ? ' (${v!.buildNumber})' : ''}\n\n'
                  'A mobile interface for your self-hosted Hermes Agent by '
                  'Nous Research. The connection, streaming, approvals, push and '
                  'turn-recovery engine comes from rusty4444/hermes-android '
                  '(MIT). Thank you, rusty4444.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 12),
              HermesMobileCardFrame(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.code_rounded),
                      title: const Text('Engine: rusty4444/hermes-android'),
                      trailing: const Icon(Icons.north_east_rounded, size: 16),
                      onTap: () => openExternal(
                        context,
                        'https://github.com/rusty4444/hermes-android',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Open-source licenses'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'Hermes',
                        applicationVersion: v?.version,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
