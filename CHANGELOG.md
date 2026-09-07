## 0.4.0

* Requires Flutter 3.32 / Dart 3.8 and updated `universal_io` and `flutter_lints`
* Added revenue tracking via the new `PlausibleRevenue` parameter of `event()`
* Added the `interactive` parameter so events that the user did not trigger can
  be kept out of the bounce rate
* `page` and `referrer` accept full urls now (including a scheme) and are passed
  on unchanged, so external referrers and utm parameters are attributed
  correctly. Plain names keep being reported below `app://localhost/`
* An empty `referrer`, `screen_width` or `props` is no longer sent
* `PlausibleNavigatorObserver` reports pops and replacements as well, uses the
  previously visible route as the referrer, skips non page routes such as
  dialogs and takes an optional `nameExtractor`
* `PlausibleNavigatorObserver` is exported from `plausible_analytics.dart`
* Sending an event no longer overwrites `serverUrl` and `userAgent`, and an
  empty `serverUrl` returns `1` instead of throwing
* Tests run against a local stub server instead of a live Plausible instance

## 0.3.0

* Added page navigation observer support

## 0.2.1

* Updated Readme, example and version bump

## 0.1.4

* Enabled for flutter web
* Added plausible event props
* Added example

## 0.1.3

* Added web check

## 0.1.2

* Added error handling for http request.

## 0.1.1

* Added disable feature.

## 0.1.0

* Initial working release.
