# Split SDK for Dart

## Overview
This SDK is designed to work with Split, the platform for controlled rollouts, which serves features to your users via feature flags to manage your complete customer experience.

## Compatibility
The Dart SDK is a client-side library. It supports the Dart VM and Flutter across every Dart target: Android, iOS, Web, and Desktop (macOS, Windows, Linux).

It supports **Dart SDK `>=3.0.0 <4.0.0`**.

## Installation
Add the SDK to your `pubspec.yaml`:
```yaml
dependencies:
  splitio_client_side: ^2.0.0
```

## Getting started
Below is a simple Dart example that describes the instantiation and most basic usage of our SDK:
```dart
// Import the SDK
import 'package:splitio_client_side/splitio_client_side.dart';

void main() {
  // Instantiate the SDK with your SDK key and the key of the current user.
  // Pass a Key instead of a String if you also need a bucketing key:
  // const Key(matchingKey: 'CUSTOMER_ID', bucketingKey: 'BUCKETING_KEY').
  final factory = SplitFactory.create(
    'YOUR_SDK_KEY',
    const SplitClientConfig(),
    'CUSTOMER_ID',
  );

  // Get the client for that user.
  final client = factory.client();

  // Evaluate once the SDK is ready; the UI stays responsive meanwhile.
  client.whenReady().then((_) {
    final treatment = client.getTreatment('FEATURE_FLAG_NAME');
    if (treatment == 'on') {
      // insert code here for on treatment
    } else if (treatment == 'off') {
      // insert code here for off treatment
    } else {
      // insert your control treatment code here
    }
  });

  // Optional: fires only if `readyTimeout` elapses before the SDK is ready.
  client.whenTimeout().then((_) {
    // insert your fallback code here (evaluations return 'control')
  });

  // Optional: emits the names of the flags that changed after the SDK is ready.
  client.whenUpdated().listen((changedFlags) {
    // insert your re-evaluation code here
  });
}
```

## Usage
All the examples below assume `client.whenReady()` has completed.

### Evaluate a feature flag
```dart
final treatment = client.getTreatment('new_checkout');
// 'on'

// Pass attributes used by your targeting rules:
final premium = client.getTreatment(
  'new_checkout',
  attributes: {'plan': 'premium', 'age': 30},
);
// 'on'
```
A treatment is `'control'` when the SDK is not ready, the flag doesn't exist or the input is invalid.

### Evaluate several feature flags
```dart
final treatments = client.getTreatments(['new_checkout', 'dark_mode']);
// {'new_checkout': 'on', 'dark_mode': 'off'}

// Every flag in the given flag sets:
final bySet = client.getTreatmentsByFlagSets(['checkout']);
// {'new_checkout': 'on', 'one_click_pay': 'off'}
```

### Get the dynamic configuration
```dart
final result = client.getTreatmentWithConfig('new_checkout');
// result.treatment == 'on'
// result.config == '{"color":"blue"}'   (null when the treatment has no config)

final results = client.getTreatmentsWithConfig(['new_checkout', 'dark_mode']);
// results['new_checkout']!.treatment == 'on'
// results['dark_mode']!.config == null
```
`getTreatmentsWithConfigByFlagSets` works the same way for flag sets.

### Track events
```dart
final queued = client.track(
  'checkout_completed', // event type
  'user',               // traffic type
  value: 49.99,
  properties: {'plan': 'premium'},
);
// true (false if the event is invalid and was dropped)
```

### Inspect feature flags
```dart
final manager = factory.manager();

manager.names();
// ['new_checkout', 'dark_mode']

final view = manager.split('new_checkout');
// view?.treatments == ['on', 'off']
// view?.defaultTreatment == 'off'
// view?.configs == {'on': '{"color":"blue"}'}
// null if the flag doesn't exist

manager.splits();
// a List<SplitView> with one entry per flag
```

### Other users
```dart
final other = factory.client('OTHER_CUSTOMER_ID');
await other.whenReady(); // each client syncs its own segments
other.getTreatment('new_checkout');
// 'on'
```

### Configuration
```dart
final factory = SplitFactory.create(
  'YOUR_SDK_KEY',
  const SplitClientConfig(
    logLevel: LogLevel.info, // default: LogLevel.none
    impressionsMode: ImpressionsMode.optimized,
    sync: SyncConfig(
      featureFlagsPollingRate: 60, // seconds
      readyTimeout: 10, // seconds
      streamingEnabled: true,
    ),
  ),
  'CUSTOMER_ID',
);
```

### Shutdown
```dart
await client.flush(); // send queued impressions and events now
await factory.destroy(); // flush and release every resource
```

Please refer to the [Split documentation](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/) to learn about all the functionality provided by our SDK, as well as the configuration options available for tailoring it to your current application setup.

## License
Licensed under the Apache License, Version 2.0. See: [Apache License](https://www.apache.org/licenses/).

## About Split

Split is the leading Feature Delivery Platform for engineering teams that want to confidently deploy features as fast as they can develop them. Split's fine-grained management, real-time monitoring, and data-driven experimentation ensure that new features will improve the customer experience without breaking or degrading performance. Companies like Twilio, Salesforce, GoDaddy and WePay trust Split to power their feature delivery.

To learn more about Split, contact hello@split.io, or get started with feature flags for free at https://www.split.io/signup.

Split has built and maintains SDKs for:

* .NET [Github](https://github.com/splitio/dotnet-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/server-side-sdks/net-sdk/)
* Android [Github](https://github.com/splitio/android-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/client-side-sdks/android-sdk/)
* Angular [Github](https://github.com/splitio/angular-sdk-plugin) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/client-side-sdks/angular-utilities/)
* Elixir thin-client [Github](https://github.com/splitio/elixir-thin-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/server-side-sdks/elixir-thin-client-sdk/)
* Flutter [Github](https://github.com/splitio/flutter-sdk-plugin) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/client-side-sdks/flutter-plugin/)
* GO [Github](https://github.com/splitio/go-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/server-side-sdks/go-sdk/)
* iOS [Github](https://github.com/splitio/ios-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/client-side-sdks/ios-sdk/)
* Java [Github](https://github.com/splitio/java-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/server-side-sdks/java-sdk/)
* JavaScript [Github](https://github.com/splitio/javascript-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/client-side-sdks/javascript-sdk/)
* JavaScript for Browser [Github](https://github.com/splitio/javascript-browser-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/client-side-sdks/browser-sdk/)
* Node.js [Github](https://github.com/splitio/javascript-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/server-side-sdks/nodejs-sdk/)
* PHP [Github](https://github.com/splitio/php-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/server-side-sdks/php-sdk/)
* PHP thin-client [Github](https://github.com/splitio/php-thin-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/server-side-sdks/php-thin-client-sdk/)
* Python [Github](https://github.com/splitio/python-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/server-side-sdks/python-sdk/)
* React [Github](https://github.com/splitio/react-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/client-side-sdks/react-sdk/)
* React Native [Github](https://github.com/splitio/react-native-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/client-side-sdks/react-native-sdk/)
* Redux [Github](https://github.com/splitio/redux-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/client-side-sdks/redux-sdk/)
* Ruby [Github](https://github.com/splitio/ruby-client) [Docs](https://developer.harness.io/docs/feature-management-experimentation/sdks-and-infrastructure/server-side-sdks/ruby-sdk/)

For a comprehensive list of open source projects visit our [Github page](https://github.com/splitio?utf8=%E2%9C%93&query=%20only%3Apublic%20).

**Learn more about Split:**

Visit [split.io/product](https://www.split.io/product) for an overview of Split, or visit our documentation at [help.split.io](https://help.split.io) for more detailed information.
