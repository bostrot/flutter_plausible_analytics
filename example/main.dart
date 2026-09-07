import 'package:flutter/material.dart';
import 'package:plausible_analytics/plausible_analytics.dart';

String analyticsUrl = "https://youranalyticsurl.com";
const String analyticsName = "yourappname"; // this is actually the site name

final Plausible plausible = Plausible(analyticsUrl, analyticsName);

void main() {
  // Send goal
  plausible.event(
    name: 'Device',
    props: {
      'app_version': 'v1.0.0',
      'app_platform': 'windows',
      'app_locale': 'de-DE',
      'app_theme': 'darkmode',
    },
  );

  // Page open event
  plausible.event(name: "settings_page");

  // Click event
  plausible.event();

  // A purchase including its revenue
  plausible.event(
    name: 'Purchase',
    revenue: const PlausibleRevenue(currency: 'EUR', amount: 13.32),
  );

  // Something the user did not trigger, so it does not count towards the
  // bounce rate
  plausible.event(name: 'sync_finished', interactive: false);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Automatically report a pageview whenever a route is pushed, popped or
      // replaced.
      navigatorObservers: [PlausibleNavigatorObserver(plausible)],
      home: const Scaffold(body: Center(child: Text('Home'))),
    );
  }
}
