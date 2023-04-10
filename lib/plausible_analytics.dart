library plausible_analytics;

import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart'; // instead of 'dart:io';
import 'dart:convert';

/// Plausible class. Use the constructor to set the parameters.
class Plausible {
  /// The url of your plausible server e.g. https://plausible.io
  String serverUrl;
  String userAgent;
  String domain;
  String screenWidth;
  bool enabled = true;

  /// Constructor
  Plausible(this.serverUrl, this.domain,
      {this.userAgent = "", this.screenWidth = ""});

  /// Post event to plausible
  Future<int> event(
      {String name = "pageview",
      String referrer = "",
      String page = "",
      Map<String, String> props = const {}}) async {
    if (!enabled) {
      return 0;
    }

    // Post-edit parameters
    int lastCharIndex = serverUrl.length - 1;
    if (serverUrl.toString()[lastCharIndex] == '/') {
      // Remove trailing slash '/'
      serverUrl = serverUrl.substring(0, lastCharIndex);
    }
    page = "app://localhost/" + page;
    referrer = "app://localhost/" + referrer;

    // Get and set device infos
    String version = Platform.operatingSystemVersion.replaceAll('"', '');

    if (userAgent == "") {
      userAgent = "Mozilla/5.0 ($version; rv:53.0) Gecko/20100101 Chrome/53.0";
    }

    // Http Post request see https://plausible.io/docs/events-api
    try {
      HttpClient client = HttpClient();
      HttpClientRequest request =
          await client.postUrl(Uri.parse(serverUrl + '/api/event'));
      request.headers.set('User-Agent', userAgent);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('X-Forwarded-For', '127.0.0.1');
      Object body = {
        "domain": domain,
        "name": name,
        "url": page,
        "referrer": referrer,
        "screen_width": screenWidth,
        "props": props,
      };
      request.write(json.encode(body));
      final HttpClientResponse response = await request.close();
      client.close();
      return response.statusCode;
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }

    return 1;
  }
}
