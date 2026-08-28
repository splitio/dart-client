import 'dart:io';

import 'package:splitio_client_side/splitio_client_side.dart';

Future<void> main(List<String> args) async {
  final sdkKey =
      Platform.environment['SPLIT_SDK_KEY'] ?? (args.isNotEmpty ? args[0] : '');
  if (sdkKey.isEmpty) {
    print('Usage: dart run bin/get_treatment.dart <SDK_KEY>');
    print('   or: SPLIT_SDK_KEY=<key> dart run bin/get_treatment.dart');
    exit(1);
  }

  final flagName = args.length > 1 ? args[1] : 'flagName';
  final userKey = args.length > 2 ? args[2] : 'userKey';

  print('Initializing Split SDK...');
  print('  SDK Key: ${sdkKey.substring(0, 8)}...');
  print('  Flag: $flagName');
  print('  User: $userKey');
  print('');

  final key = Key(matchingKey: userKey);

  final factory = SplitFactory.create(
    sdkKey,
    const SplitClientConfig(
      sync: SyncConfig(
          featureFlagsPollingRate: 10,
          impressionsPushRate: 30,
          readyTimeout: 15),
      impressionsMode: ImpressionsMode.debug,
      logLevel: LogLevel.verbose,
    ),
    key,
  );

  final client = factory.client(key);

  // Optional: get notified if readyTimeout elapses before READY fires.
  // Fire-and-forget — does not block the main flow.
  client.whenTimeout().then(
      (_) => print('  WARNING: readyTimeout elapsed, still waiting for READY...'));

  print('Waiting for SDK to be ready...');
  await client.whenReady();
  print('  SDK is READY!');
  print('');

  // Evaluate the flag
  final treatment = client.getTreatment(flagName);
  final result = client.getTreatmentWithConfig(flagName);
  print('getTreatment("$flagName"):');
  print('  treatment: $treatment');
  print('  config: ${result.config ?? "(none)"}');
  print('');

  await Future.delayed(const Duration(seconds: 20));

  // Show all available flags
  final manager = factory.manager();
  final allFlags = manager.names();
  print('Available flags (${allFlags.length}):');
  for (final name in allFlags.take(20)) {
    final view = manager.split(name)!;
    print(
        '  - $name [treatments: ${view.treatments.join(", ")}] ${view.killed ? "(KILLED)" : ""}');
  }
  if (allFlags.length > 20) {
    print('  ... and ${allFlags.length - 20} more');
  }

  print('');
  print('Shutting down...');
  await factory.destroy();
  print('Done.');
}
