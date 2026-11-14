import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/hermes_mobile_connector_inventory.dart';

void main() {
  test('reads sanitized hosted accounts and MCP names', () async {
    final calls = <String>[];
    final reader = HermesMobileConnectorInventoryReader((method) async {
      calls.add(method);
      if (method == 'connectors.accounts') {
        return {
          'result': {
            'accounts': [
              {
                'connector': 'gmail', 'alias': 'work', 'label': 'a@example.com',
                'status': 'active', 'access_token': 'must-not-appear'
              },
              {
                'connector': 'github', 'label': 'account', 'status': 'expired',
                'disabled': true,
              },
            ]
          },
        };
      }
      return {
        'result': {
          'servers': [
            {'name': 'linear', 'enabled': true, 'url': 'https://secret'},
          ]
        },
      };
    });
    final result = await reader.load();
    expect(calls, ['connectors.accounts', 'mcp.servers.list']);
    expect(result.accounts, hasLength(2));
    expect(result.accounts.last.label, 'work');
    expect(result.accounts.first.retired, true);
    expect(result.mcpServers.single.name, 'linear');
    expect(result.accountIssue, null);
    expect(result.mcpIssue, null);
  });

  test('an unsupported hosted RPC does not hide local MCP servers', () async {
    final reader = HermesMobileConnectorInventoryReader((method) async {
      if (method == 'connectors.accounts') {
        return {'error': {'code': -32601, 'message': 'Method not found'}};
      }
      return {'result': {'servers': []}};
    });
    final result = await reader.load();
    expect(result.accountIssue, contains('too old'));
    expect(result.mcpIssue, null);
    expect(result.accounts, isEmpty);
  });
}
