import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';

void main() {
  group('MobilePushService.messageFor', () {
    test('a server-revoked installation tells the user how to re-pair', () {
      final message =
          MobilePushService.messageFor(const DashboardHttpException(409));
      expect(message, contains('off and on'));
      expect(message, isNot(contains('not ready')));
    });

    test('existing status mappings are unchanged', () {
      expect(MobilePushService.messageFor(const DashboardHttpException(404)),
          contains('companion is unavailable'));
      expect(MobilePushService.messageFor(const DashboardHttpException(403)),
          contains('Server denied mobile push'));
      expect(MobilePushService.messageFor(const DashboardHttpException(500)),
          contains('Mobile push is not ready'));
    });
  });
}
