import 'package:flutter/material.dart';

import '../../core/services/mobile_push_service.dart';
import '../features/wave3_control/cron_studio_screen.dart';

/// Opens only a server-authenticated result from a live paired installation.
/// Notification hints themselves contain no cron output or navigation URLs.
class HermesMobileCronPushResultScreen extends StatefulWidget {
  const HermesMobileCronPushResultScreen({super.key, required this.route});
  final MobilePushRoute route;

  @override
  State<HermesMobileCronPushResultScreen> createState() => _HermesMobileCronPushResultScreenState();
}

class _HermesMobileCronPushResultScreenState extends State<HermesMobileCronPushResultScreen> {
  late final Future<String> _result =
      MobilePushService.shared.loadCronResult(widget.route);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled result')),
      body: FutureBuilder<String>(
        future: _result,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'This result is unavailable or its secure access has expired. '
                  'You can still inspect the saved run in Cron studio.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SelectableText(snapshot.data ?? ''),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: const Text('View scheduled tasks'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CronStudioScreen()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
