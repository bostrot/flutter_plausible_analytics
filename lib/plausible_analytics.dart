/// A Flutter package for Plausible Analytics.
///
/// It uses the [events API](https://plausible.io/docs/events-api) to send
/// pageviews, custom events, goals and revenue to a Plausible server.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart'; // instead of 'dart:io';

export 'navigator_observer.dart';

/// Revenue attached to an event.
///
/// Used for the ecommerce revenue tracking of Plausible, see
/// https://plausible.io/docs/ecommerce-revenue-tracking
@immutable
class PlausibleRevenue {
  /// Creates the revenue data of a single transaction.
  const PlausibleRevenue({required this.currency, required this.amount});

  /// The three letter ISO 4217 currency code, e.g. `USD`.
  final String currency;

  /// The monetary value of the transaction, e.g. `13.32`.
  final num amount;

  /// The representation expected by the Plausible events API.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'currency': currency,
    'amount': amount,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlausibleRevenue &&
          other.currency == currency &&
          other.amount == amount;

  @override
  int get hashCode => Object.hash(currency, amount);

  @override
  String toString() => 'PlausibleRevenue(currency: $currency, amount: $amount)';
}

/// Plausible class. Use the constructor to set the parameters.
class Plausible {
  /// Constructor
  Plausible(
    this.serverUrl,
    this.domain, {
    this.userAgent = "",
    this.screenWidth = "",
  });

  /// The origin every app internal page and referrer is reported under.
  static const String appOrigin = 'app://localhost';

  /// The url of your plausible server e.g. https://plausible.io
  String serverUrl;

  /// The user agent sent with every event. When left empty a user agent
  /// containing the current operating system and version is generated.
  String userAgent;

  /// The domain (site name) as registered in your Plausible account.
  String domain;

  /// The screen width reported with every event, e.g. `1920`. Left out of the
  /// request when empty.
  String screenWidth;

  /// Set to `false` to stop sending any event, e.g. when a user opts out.
  bool enabled = true;

  /// Post event to plausible.
  ///
  /// Returns the status code of the request (`202` when Plausible accepted the
  /// event), `0` when this instance is [enabled] `false` and `1` when the
  /// request could not be made.
  ///
  /// [page] and [referrer] may either be a plain app internal name such as
  /// `homescreen` (reported below [appOrigin]) or a full url including a
  /// scheme, which is passed on unchanged so external referrers and utm
  /// parameters are attributed correctly.
  ///
  /// Set [interactive] to `false` for events that were not triggered by the
  /// user so they do not count towards the bounce rate.
  Future<int> event({
    String name = "pageview",
    String referrer = "",
    String page = "",
    Map<String, String> props = const {},
    PlausibleRevenue? revenue,
    bool interactive = true,
  }) async {
    if (!enabled) {
      return 0;
    }

    final String baseUrl = _normalizedServerUrl();
    if (baseUrl.isEmpty) {
      if (kDebugMode) {
        print('Plausible: serverUrl is empty, dropping event "$name".');
      }
      return 1;
    }

    // Http Post request see https://plausible.io/docs/events-api
    final Map<String, dynamic> body = <String, dynamic>{
      "domain": domain,
      "name": name,
      "url": _absoluteUrl(page),
      "interactive": interactive,
    };
    if (referrer.isNotEmpty) {
      body["referrer"] = _absoluteUrl(referrer);
    }
    if (screenWidth.isNotEmpty) {
      body["screen_width"] = screenWidth;
    }
    if (props.isNotEmpty) {
      body["props"] = props;
    }
    if (revenue != null) {
      body["revenue"] = revenue.toJson();
    }

    try {
      final HttpClient client = HttpClient();
      try {
        final HttpClientRequest request = await client.postUrl(
          Uri.parse('$baseUrl/api/event'),
        );
        request.headers.set('User-Agent', _resolvedUserAgent());
        request.headers.set('Content-Type', 'application/json; charset=utf-8');
        request.headers.set('X-Forwarded-For', '127.0.0.1');
        request.write(json.encode(body));
        final HttpClientResponse response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }

    return 1;
  }

  /// [serverUrl] without any trailing slashes and surrounding whitespace.
  String _normalizedServerUrl() {
    String url = serverUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Matches a value that already starts with a scheme, e.g. `https://`.
  static final RegExp _schemePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');

  /// Turns an app internal page name into a url below [appOrigin]. Values that
  /// already carry a scheme are left untouched.
  static String _absoluteUrl(String value) {
    if (_schemePattern.hasMatch(value)) {
      return value;
    }
    final String path = value.startsWith('/')
        ? value.replaceFirst(RegExp(r'^/+'), '')
        : value;
    return '$appOrigin/$path';
  }

  /// The configured [userAgent] or a generated one containing the current
  /// operating system and version.
  String _resolvedUserAgent() {
    if (userAgent.isNotEmpty) {
      return userAgent;
    }
    // Get and set device infos
    final String version = Platform.operatingSystemVersion.replaceAll('"', '');
    return "Mozilla/5.0 ($version; rv:53.0) Gecko/20100101 Chrome/53.0";
  }
}
