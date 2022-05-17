import 'package:plausible_analytics/plausible_analytics.dart';

String analyticsUrl = "https://youranalyticsurl.com";
const String analyticsName = "yourappname"; // this is actually the site name

void main() {
  Plausible plausible = Plausible(analyticsUrl, analyticsName);
  // Send goal
  plausible.event(name: 'Device', props: {
    'app_version': 'v1.0.0',
    'app_platform': 'windows',
    'app_locale': 'de-DE',
    'app_theme': 'darkmode',
  });

  // Page open event
  plausible.event(name: "settings_page");

  // Click event
  plausible.event();
}
