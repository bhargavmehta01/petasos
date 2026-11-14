import 'package:flutter/material.dart';

import '../../core/services/desktop_gateway_client.dart';
import '../../core/services/hermes_mobile_connector_inventory.dart';
import '../hermes_mobile_app.dart';

/// Read-only profile-scoped account/connection inventory.
/// Never displays raw connector records, credentials, URLs or tokens.
class HermesMobileAccountsScreen extends StatefulWidget {
  const HermesMobileAccountsScreen({super.key, this.testLoader});
  final Future<HermesMobileConnectorInventory> Function()? testLoader;

  @override
  State<HermesMobileAccountsScreen> createState() => _HermesMobileAccountsScreenState();
}

class _HermesMobileAccountsScreenState extends State<HermesMobileAccountsScreen> {
  HermesMobileConnectorInventory? data;
  String? error;
  bool loading = false;
  String? connectionId;
  bool initialized = false;
  int ticket = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = HermesMobileRoot.of(context).activeConnection?.id;
    if (!initialized || active != connectionId) {
      initialized = true;
      connectionId = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  Future<void> _refresh() async {
    final root = HermesMobileRoot.of(context);
    final active = root.activeConnection?.id;
    final current = ++ticket;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final HermesMobileConnectorInventory result;
      if (widget.testLoader != null) {
        result = await widget.testLoader!();
      } else {
        final manager = root.connections;
        if (manager == null || active == null) throw StateError('No gateway');
        final saved = await manager.loadConnectionsWithSecrets();
        final connection = saved.where((c) => c.id == active).firstOrNull;
        if (connection == null) throw StateError('Connection not found');
        final gateway = DesktopGatewayClient.fromConnection(connection);
        try {
          result = await HermesMobileConnectorInventoryReader(
              gateway.readConnectorInventoryRpc).load();
        } finally {
          gateway.close();
        }
      }
      if (!mounted || current != ticket) return;
      setState(() => data = result);
    } catch (_) {
      if (!mounted || current != ticket) return;
      setState(() {
        data = null;
        error = 'Unable to load accounts. Verify your Hermes gateway login.';
      });
    } finally {
      if (mounted && current == ticket) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    ticket++;
    super.dispose();
  }

  Widget _header(String title) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  @override
  Widget build(BuildContext context) {
    final root = HermesMobileRoot.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts & connections'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh accounts',
            onPressed: loading ? null : _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text('Read-only account names and connection status. '
              'Secrets and saved passwords are never displayed.'),
          if (loading) const LinearProgressIndicator(),
          if (error != null) ListTile(title: Text(error!)),
          _header('Hosted connector accounts'),
          if (data?.accountIssue != null)
            ListTile(title: Text(data!.accountIssue!))
          else if (data != null && data!.accounts.isEmpty)
            const ListTile(title: Text('No hosted accounts connected'))
          else
            for (final a in data?.accounts ?? <HermesMobileHostedAccount>[])
              ListTile(
                key: ValueKey('account-${a.app}-${a.label}'),
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(a.app),
                subtitle: Text(a.label),
                trailing: Text(a.retired ? 'Retired' : a.status),
              ),
          _header('Local MCP connections'),
          if (data?.mcpIssue != null)
            ListTile(title: Text(data!.mcpIssue!))
          else if (data != null && data!.mcpServers.isEmpty)
            const ListTile(title: Text('No local MCP servers configured'))
          else
            for (final item in data?.mcpServers ?? <HermesMobileMcpConnection>[])
              ListTile(
                key: ValueKey('mcp-${item.name}'),
                leading: const Icon(Icons.extension_outlined),
                title: Text(item.name),
                trailing: Text(item.enabled ? 'Enabled' : 'Disabled'),
              ),
          _header('Saved Petasos gateways'),
          if (root.savedConnections.isEmpty)
            const ListTile(title: Text('No saved gateways'))
          else
            for (final gateway in root.savedConnections)
              ListTile(
                key: ValueKey('gateway-${gateway.id}'),
                leading: Icon(gateway.id == root.activeConnection?.id
                    ? Icons.radio_button_checked
                    : Icons.dns_outlined),
                title: Text(gateway.label),
                subtitle: Text(gateway.host),
                trailing: gateway.id == root.activeConnection?.id
                    ? const Text('Current')
                    : null,
              ),
          const SizedBox(height: 18),
          const Text('Manage hosted accounts in Hermes Desktop → Connectors; '
              'model providers in Providers → Accounts; and phone gateways '
              'in Petasos Profile → Connection.'),
        ],
      ),
    );
  }
}
