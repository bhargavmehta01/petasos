import 'ws_client.dart';

/// Safe-to-display connector metadata. Raw credentials never leave this reader.
class HermesMobileHostedAccount {
  const HermesMobileHostedAccount(this.app, this.label, this.status, this.retired);
  final String app;
  final String label;
  final String status;
  final bool retired;
}

class HermesMobileMcpConnection {
  const HermesMobileMcpConnection(this.name, this.enabled);
  final String name;
  final bool enabled;
}

class HermesMobileConnectorInventory {
  const HermesMobileConnectorInventory(this.accounts, this.mcpServers,
      {this.accountIssue, this.mcpIssue});
  final List<HermesMobileHostedAccount> accounts;
  final List<HermesMobileMcpConnection> mcpServers;
  final String? accountIssue;
  final String? mcpIssue;
}

typedef HermesMobileInventoryRpc = Future<Map<String, dynamic>> Function(String method);

class HermesMobileConnectorInventoryReader {
  const HermesMobileConnectorInventoryReader(this.request);
  final HermesMobileInventoryRpc request;

  static String text(Object? value, [String fallback = '']) {
    if (value is! String) return fallback;
    final v = value.trim();
    if (v.isEmpty) return fallback;
    return v.length > 140 ? v.substring(0, 140) : v;
  }

  static Map<String, dynamic> unwrap(
      String method, Map<String, dynamic> response) {
    final error = response['error'];
    if (error is Map) {
      throw JsonRpcError.fromGateway(method, error,
          fallbackMessage: 'Connector inventory unavailable');
    }
    final result = response['result'];
    if (result is! Map) throw const FormatException('Invalid connector inventory');
    return Map<String, dynamic>.from(result);
  }

  static String issue(Object error) {
    if (error is JsonRpcError) {
      if (error.code == -32601) {
        return 'The connected Hermes gateway is too old for this view.';
      }
      if (error.reason == 'NEEDS_NOUS_AUTH') {
        return 'Sign in to Nous Portal in Hermes Desktop to view hosted accounts.';
      }
    }
    return 'Unable to read this list. Check gateway access and sign-in.';
  }

  Future<HermesMobileConnectorInventory> load() async {
    var accounts = <HermesMobileHostedAccount>[];
    var servers = <HermesMobileMcpConnection>[];
    String? accountsError;
    String? mcpError;
    try {
      final result = unwrap('connectors.accounts', await request('connectors.accounts'));
      final items = result['accounts'];
      if (items is! List) throw const FormatException('Missing accounts');
      accounts = [
        for (final raw in items)
          if (raw is Map && text(raw['connector']).isNotEmpty)
            HermesMobileHostedAccount(
              text(raw['connector']),
              text(raw['alias'], text(raw['label'], 'Unnamed account')),
              text(raw['status'], 'unknown'),
              raw['disabled'] == true,
            ),
      ]..sort((a, b) {
        final result = a.app.compareTo(b.app);
        return result != 0 ? result : a.label.compareTo(b.label);
      });
    } catch (e) {
      accountsError = issue(e);
    }
    try {
      final result = unwrap('mcp.servers.list', await request('mcp.servers.list'));
      final items = result['servers'];
      if (items is! List) throw const FormatException('Missing MCP servers');
      servers = [
        for (final raw in items)
          if (raw is Map && text(raw['name']).isNotEmpty)
            HermesMobileMcpConnection(text(raw['name']), raw['enabled'] == true),
      ]..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      mcpError = issue(e);
    }
    return HermesMobileConnectorInventory(accounts, servers,
        accountIssue: accountsError, mcpIssue: mcpError);
  }
}
