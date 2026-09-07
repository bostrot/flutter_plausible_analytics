import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plausible_analytics/plausible_analytics.dart';

const String domain = "example.com";
const String screenWidth = "1000x1000";

void main() {
  late _FakePlausibleServer server;

  setUp(() async {
    server = await _FakePlausibleServer.start();
  });

  tearDown(() async {
    await server.stop();
  });

  test('make plausible event call with pageview', () async {
    final plausible = Plausible(server.url, domain, screenWidth: screenWidth);
    expect(plausible.serverUrl, server.url);
    expect(plausible.domain, domain);
    expect(plausible.screenWidth, screenWidth);

    expect(await plausible.event(), 202);

    final request = server.requests.single;
    expect(request.path, '/api/event');
    expect(request.body['domain'], domain);
    expect(request.body['name'], 'pageview');
    expect(request.body['url'], 'app://localhost/');
    expect(request.body['screen_width'], screenWidth);
    expect(request.body['interactive'], true);
    // Optional parameters are left out when they carry no information.
    expect(request.body.containsKey('referrer'), isFalse);
    expect(request.body.containsKey('props'), isFalse);
    expect(request.body.containsKey('revenue'), isFalse);

    expect(request.header('user-agent'), startsWith('Mozilla/5.0 ('));
    expect(request.header('content-type'), 'application/json; charset=utf-8');
    expect(request.header('x-forwarded-for'), '127.0.0.1');
  });

  test('make plausible event call with custom event', () async {
    final plausible = Plausible(server.url, domain, screenWidth: screenWidth);

    expect(
      await plausible.event(
        name: 'conversion',
        page: 'homescreen',
        referrer: 'referrerPage',
        props: {'app_version': 'v1.0.0'},
      ),
      202,
    );

    final request = server.requests.single;
    expect(request.body['name'], 'conversion');
    expect(request.body['url'], 'app://localhost/homescreen');
    expect(request.body['referrer'], 'app://localhost/referrerPage');
    expect(request.body['props'], {'app_version': 'v1.0.0'});
  });

  test('send revenue and non interactive events', () async {
    final plausible = Plausible(server.url, domain);

    expect(
      await plausible.event(
        name: 'Purchase',
        revenue: const PlausibleRevenue(currency: 'EUR', amount: 13.32),
        interactive: false,
      ),
      202,
    );

    final request = server.requests.single;
    expect(request.body['revenue'], {'currency': 'EUR', 'amount': 13.32});
    expect(request.body['interactive'], false);
    // Not configured, so it is not reported.
    expect(request.body.containsKey('screen_width'), isFalse);
  });

  test('pass full urls through unchanged', () async {
    final plausible = Plausible(server.url, domain);

    expect(
      await plausible.event(
        page: 'https://example.com/landing?utm_source=newsletter',
        referrer: 'https://news.ycombinator.com/',
      ),
      202,
    );

    final request = server.requests.single;
    expect(
      request.body['url'],
      'https://example.com/landing?utm_source=newsletter',
    );
    expect(request.body['referrer'], 'https://news.ycombinator.com/');
  });

  test('only treat a leading scheme as a full url', () async {
    final plausible = Plausible(server.url, domain);

    // A query parameter that happens to contain "://" is still an app page.
    expect(await plausible.event(page: 'search?q=https://example.com'), 202);
    // Leading slashes are not doubled up.
    expect(await plausible.event(page: '//home'), 202);

    expect(
      server.requests[0].body['url'],
      'app://localhost/search?q=https://example.com',
    );
    expect(server.requests[1].body['url'], 'app://localhost/home');
  });

  test('use a custom user agent when one is given', () async {
    final plausible = Plausible(
      server.url,
      domain,
      userAgent: 'MyApp/1.0 (Linux)',
    );

    expect(await plausible.event(), 202);

    expect(server.requests.single.header('user-agent'), 'MyApp/1.0 (Linux)');
    // The configured user agent is not overwritten by sending an event.
    expect(plausible.userAgent, 'MyApp/1.0 (Linux)');
  });

  test('strip trailing slashes from the server url', () async {
    final plausible = Plausible('${server.url}//', domain);

    expect(await plausible.event(), 202);

    expect(server.requests.single.path, '/api/event');
    // The configured url stays as the user set it.
    expect(plausible.serverUrl, '${server.url}//');
  });

  test('return the status code the server answered with', () async {
    server.statusCode = 400;
    final plausible = Plausible(server.url, domain);

    expect(await plausible.event(), 400);
  });

  test('check disabled call', () async {
    final plausible = Plausible(server.url, domain, screenWidth: screenWidth);
    plausible.enabled = false;

    expect(
      await plausible.event(
        name: 'conversion',
        page: 'homescreen',
        referrer: 'referrerPage',
      ),
      0,
    );
    expect(server.requests, isEmpty);
  });

  test('check failed http request', () async {
    final plausible = Plausible(
      "somewrongurl.asd21",
      domain,
      screenWidth: screenWidth,
    );
    expect(plausible.serverUrl, "somewrongurl.asd21");

    expect(
      await plausible.event(
        name: 'conversion',
        page: 'homescreen',
        referrer: 'referrerPage',
      ),
      1,
    );
  });

  test('an empty server url does not throw', () async {
    final plausible = Plausible("   ", domain);

    expect(await plausible.event(), 1);
  });

  group('PlausibleNavigatorObserver', () {
    late Plausible plausible;
    late PlausibleNavigatorObserver observer;

    setUp(() {
      plausible = Plausible(server.url, domain);
      observer = PlausibleNavigatorObserver(plausible);
    });

    test('reports a push with the previous route as referrer', () async {
      observer.didPush(_pageRoute('/settings'), _pageRoute('/home'));
      await server.waitForRequests(1);

      final body = server.requests.single.body;
      expect(body['url'], 'app://localhost/settings');
      expect(body['referrer'], 'app://localhost/home');
    });

    test('reports the route that becomes visible again on pop', () async {
      final home = _pageRoute('/home');
      final settings = _pageRoute('/settings');
      observer.didPop(settings, home);
      await server.waitForRequests(1);

      final body = server.requests.single.body;
      expect(body['url'], 'app://localhost/home');
      expect(body['referrer'], 'app://localhost/settings');
    });

    test('reports a replaced route', () async {
      observer.didReplace(
        newRoute: _pageRoute('/home'),
        oldRoute: _pageRoute('/splash'),
      );
      await server.waitForRequests(1);

      expect(server.requests.single.body['url'], 'app://localhost/home');
    });

    test('ignores unnamed routes and non page routes', () async {
      observer.didPush(_pageRoute(null), _pageRoute('/home'));
      observer.didPush(_popupRoute(), _pageRoute('/home'));
      observer.didPop(_pageRoute('/home'), null);

      // Give any (unwanted) request the chance to arrive before asserting.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.requests, isEmpty);
    });

    test('honours a custom name extractor', () async {
      final custom = PlausibleNavigatorObserver(
        plausible,
        nameExtractor: (settings) => (settings.arguments as String?) ?? 'other',
      );
      custom.didPush(
        PageRouteBuilder<void>(
          settings: const RouteSettings(name: '/a', arguments: 'checkout'),
          pageBuilder: (context, animation, secondaryAnimation) =>
              const SizedBox(),
        ),
        null,
      );
      await server.waitForRequests(1);

      expect(server.requests.single.body['url'], 'app://localhost/checkout');
    });
  });
}

PageRoute<void> _pageRoute(String? name) => PageRouteBuilder<void>(
  settings: RouteSettings(name: name),
  pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
);

ModalRoute<void> _popupRoute() => _NotAPageRoute();

class _NotAPageRoute extends PopupRoute<void> {
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const SizedBox();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  RouteSettings get settings => const RouteSettings(name: '/dialog');
}

/// A request the [_FakePlausibleServer] received.
class _RecordedRequest {
  _RecordedRequest(this.path, this.headers, this.body);

  final String path;
  final Map<String, List<String>> headers;
  final Map<String, dynamic> body;

  String? header(String name) => headers[name]?.join(', ');
}

/// A local stand in for a Plausible server, so the tests never leave the
/// machine they run on.
class _FakePlausibleServer {
  _FakePlausibleServer._(this._server);

  final HttpServer _server;

  /// Every request received so far, in the order they arrived.
  final List<_RecordedRequest> requests = <_RecordedRequest>[];

  /// The status code answered with, `202` like a real Plausible server.
  int statusCode = 202;

  static Future<_FakePlausibleServer> start() async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final _FakePlausibleServer fake = _FakePlausibleServer._(server);
    server.listen((HttpRequest request) async {
      final String raw = await utf8.decoder.bind(request).join();
      final Map<String, List<String>> headers = <String, List<String>>{};
      request.headers.forEach((String name, List<String> values) {
        headers[name.toLowerCase()] = values;
      });
      fake.requests.add(
        _RecordedRequest(
          request.uri.path,
          headers,
          json.decode(raw) as Map<String, dynamic>,
        ),
      );
      request.response.statusCode = fake.statusCode;
      await request.response.close();
    });
    return fake;
  }

  String get url => 'http://${_server.address.address}:${_server.port}';

  /// Waits until [count] requests arrived, so fire and forget calls such as the
  /// ones of [PlausibleNavigatorObserver] can be asserted on.
  Future<void> waitForRequests(
    int count, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (requests.length < count) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Expected $count request(s) but got ${requests.length}.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> stop() => _server.close(force: true);
}
