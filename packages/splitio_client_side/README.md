# Split SDK for Dart

## Overview
This SDK is designed to work with Split, the platform for controlled rollouts, which serves features to your users via feature flags to manage your complete customer experience.

## Compatibility
The Dart SDK is a client-side library. It supports the Dart VM and Flutter across every Dart target: Android, iOS, Web, and Desktop (macOS, Windows, Linux).

It supports **Dart SDK `>=3.0.0 <4.0.0`**.

## Getting started
Below is a simple Dart example that describes the instantiation and most basic usage of our SDK:
```dart
// Import the SDK
import 'package:splitio_client_side/splitio_client_side.dart';

void main() {
  // Instantiate the SDK — you can pass either a bare String matching key…
  final factory = SplitFactory.create(
    'YOUR_SDK_KEY',
    const SplitClientConfig(),
    'CUSTOMER_ID',
  );

  // …or a Key value if you also need a bucketing key.
  //
  //   final factory = SplitFactory.create(
  //     'YOUR_SDK_KEY',
  //     const SplitClientConfig(),
  //     const Key(matchingKey: 'CUSTOMER_ID'),
  //   );

  // Get the client instance you'll use — String or Key both work here too.
  final client = factory.client('CUSTOMER_ID');

  // Subscribe to the SDK-ready event instead of blocking the main flow —
  // this is the idiomatic client-side pattern (UI stays responsive; the
  // callback fires once the SDK has synced its rules).
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

  // Optional: get notified if `readyTimeout` elapses before READY fires.
  // This future only resolves on timeout — once READY fires, it stays
  // pending for the lifetime of the client.
  client.whenTimeout().then((_) {
    // insert your fallback-UI code here (evaluations will return 'control')
  });

  // Optional: react to feature-flag updates after the SDK is ready.
  // The stream emits the list of changed flag names on every update.
  client.whenUpdated().listen((changedFlags) {
    // insert your re-evaluation code here for the changed flags
  });
}
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
