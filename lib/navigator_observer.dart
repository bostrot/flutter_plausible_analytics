import 'package:flutter/widgets.dart';
import 'package:plausible_analytics/plausible_analytics.dart';

/// A [NavigatorObserver] that reports page views to [Plausible].
class PlausibleNavigatorObserver extends NavigatorObserver {
  /// The [Plausible] instance to report page views to.
  final Plausible plausible;

  /// Creates a [PlausibleNavigatorObserver].
  PlausibleNavigatorObserver(this.plausible);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    plausible.event(page: route.settings.name ?? '');
  }
}
