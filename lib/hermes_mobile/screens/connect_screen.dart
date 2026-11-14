import 'package:flutter/material.dart';

import '../../core/services/connection_manager.dart';
import '../hermes_mobile_app.dart';
import '../theme/hermes_mobile_theme.dart';

/// First run (and "Edit connection"): API server address + key, optional
/// dashboard for cron, skills, memory, usage, projects and panels.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, this.existing});
  final SavedConnection? existing;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(
    text: widget.existing?.label ?? 'My Hermes',
  );
  late final _host = TextEditingController(
    text: widget.existing == null
        ? ''
        : '${widget.existing!.useHttps ? 'https://' : ''}${widget.existing!.host}',
  );
  late final _port = TextEditingController(
    text: widget.existing?.port.toString() ?? '8642',
  );
  late final _key = TextEditingController(text: widget.existing?.apiKey ?? '');
  late final _dash = TextEditingController(
    text: widget.existing?.desktopGatewayUrl ?? '',
  );
  late final _dashUser = TextEditingController(
    text: widget.existing?.dashboardUsername ?? '',
  );
  late final _dashPass = TextEditingController(
    text: widget.existing?.dashboardPassword ?? '',
  );
  bool _showKey = false;
  bool _advanced = false;
  bool _busy = false;
  String? _status;
  bool? _ok;

  @override
  void initState() {
    super.initState();
    _advanced = (widget.existing?.desktopGatewayUrl ?? '').isNotEmpty;
  }

  Future<void> _test() async {
    final n = SavedConnection.normalizeHostAndPort(
      _host.text,
      int.tryParse(_port.text),
    );
    setState(() {
      _busy = true;
      _status = 'Checking…';
      _ok = null;
    });
    final client = ApiClient(
      baseUrl:
          '${Uri(scheme: n.useHttps ? 'https' : 'http', host: n.host)}:${n.port}',
      apiKey: _key.text.trim(),
    );
    try {
      final r = await client.checkHealth();
      setState(() {
        _ok = r.isHealthy;
        _status = r.isHealthy
            ? 'Connected to Hermes.'
            : r.userMessage(apiKeyProvided: _key.text.trim().isNotEmpty);
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _status = '$e';
      });
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final root = HermesMobileRoot.of(context);
    final cm = root.connections;
    if (cm == null) return;
    setState(() => _busy = true);
    try {
      final dash = _dash.text.trim();
      if (widget.existing == null) {
        await cm.saveConnection(
          _label.text.trim(),
          _host.text.trim(),
          int.tryParse(_port.text.trim()),
          _key.text.trim(),
          desktopGatewayUrl: dash.isEmpty ? null : dash,
          dashboardUsername: _dashUser.text.trim().isEmpty
              ? null
              : _dashUser.text.trim(),
          dashboardPassword: _dashPass.text.isEmpty ? null : _dashPass.text,
        );
        final saved = cm.getConnections().first;
        await root.useConnection(saved.id);
      } else {
        await cm.updateConnection(
          widget.existing!.id,
          _label.text.trim(),
          _host.text.trim(),
          int.tryParse(_port.text.trim()),
          _key.text.trim(),
          desktopGatewayUrl: dash,
          dashboardUsername: _dashUser.text.trim(),
          dashboardPassword: _dashPass.text,
        );
        await root.useConnection(widget.existing!.id);
      }
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      setState(() {
        _ok = false;
        _status = 'Could not save: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final root = HermesMobileRoot.of(context);
    final editing = widget.existing != null;
    return Scaffold(
      appBar: editing ? AppBar(title: const Text('Connection')) : null,
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              if (!editing) ...[
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(Icons.bolt_rounded, color: c.accent, size: 30),
                ),
                const SizedBox(height: 18),
                Text(
                  'Connect to your Hermes',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Use the API server address (usually port 8642) and its API '
                  'key. Over Tailscale, use the machine\'s 100.x address.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: 24),
              ],
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _host,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        hintText: '100.64.12.34 or https://…',
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Enter an address' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Port'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _key,
                obscureText: !_showKey,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'API key',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _advanced = !_advanced),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Text(
                        'Dashboard (cron, skills, memory, projects, panels)',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: c.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        _advanced
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: c.accent,
                      ),
                    ],
                  ),
                ),
              ),
              if (_advanced) ...[
                TextFormField(
                  controller: _dash,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Dashboard URL',
                    hintText: 'http://100.64.12.34:9119',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _dashUser,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Username (optional)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _dashPass,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password (optional)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _ok == true
                            ? Icons.check_circle_rounded
                            : _ok == false
                            ? Icons.error_outline_rounded
                            : Icons.hourglass_top_rounded,
                        size: 18,
                        color: _ok == true
                            ? c.success
                            : _ok == false
                            ? c.danger
                            : c.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _status!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _test,
                      child: const Text('Test'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy || root.connections == null ? null : _save,
                      child: Text(editing ? 'Save' : 'Connect'),
                    ),
                  ),
                ],
              ),
              if (!editing) ...[
                const SizedBox(height: 20),
                Center(
                  child: TextButton.icon(
                    onPressed: root.enterDemo,
                    icon: const Icon(Icons.science_outlined, size: 18),
                    label: const Text('Explore the demo instead'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
