import 'package:flutter/widgets.dart';

import 'plausible_analytics.dart';

/// Resolves the page name that is reported for a route.
///
/// Return `null` to not report the route at all.
typedef PlausibleRouteNameExtractor = String? Function(RouteSettings settings);

/// A [NavigatorObserver] that reports page views to [Plausible].
///
/// Pushing, popping and replacing a [PageRoute] all report a pageview for the
/// route that becomes visible, using the route that was visible before as the
/// referrer.
class PlausibleNavigatorObserver extends NavigatorObserver {
  /// Creates a [PlausibleNavigatorObserver].
  PlausibleNavigatorObserver(
    this.plausible, {
    this.nameExtractor = defaultNameExtractor,
  });

  /// The [Plausible] instance to report page views to.
  final Plausible plausible;

  /// Resolves the page name reported for a route. Defaults to
  /// [defaultNameExtractor].
  final PlausibleRouteNameExtractor nameExtractor;

  /// Reports a route under its [RouteSettings.name].
  static String? defaultNameExtractor(RouteSettings settings) => settings.name;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _sendPageView(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    // The previous route becomes visible again, the popped one is its referrer.
    _sendPageView(previousRoute, route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _sendPageView(newRoute, oldRoute);
  }

  /// Reports a pageview for [route] unless it is not a [PageRoute] (e.g. a
  /// dialog or a popup menu) or [nameExtractor] does not name it.
  void _sendPageView(Route<dynamic>? route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) {
      return;
    }
    final String? page = nameExtractor(route.settings);
    if (page == null) {
      return;
    }
    final String? referrer = previousRoute is PageRoute
        ? nameExtractor(previousRoute.settings)
        : null;
    plausible.event(page: page, referrer: referrer ?? '');
  }
}
