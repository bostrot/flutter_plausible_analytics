import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Turns a GitHub Actions filter pattern into an equivalent [RegExp].
///
/// Filter patterns are not regular expressions: `*` matches any run of
/// characters except `/`, `+` repeats the preceding character or character
/// range, and everything else - `.` included - is literal.
RegExp filterPattern(String pattern) {
  final buffer = StringBuffer('^');
  for (var i = 0; i < pattern.length; i++) {
    final character = pattern[i];
    switch (character) {
      case '*':
        buffer.write('[^/]*');
      case '+':
        buffer.write('+');
      case '[':
        final end = pattern.indexOf(']', i);
        if (end == -1) {
          buffer.write(RegExp.escape(character));
        } else {
          buffer.write(pattern.substring(i, end + 1));
          i = end;
        }
      default:
        buffer.write(RegExp.escape(character));
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString());
}

void main() {
  final workflow =
      loadYaml(File('.github/workflows/publish.yml').readAsStringSync())
          as YamlMap;
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;

  // `on` is a YAML 1.1 boolean, so which key it lands under depends on the
  // parser the reader happens to use.
  final triggers = (workflow['on'] ?? workflow[true]) as YamlMap;
  final push = triggers['push'] as YamlMap;
  final tagFilters = (push['tags'] as YamlList).cast<String>().toList();

  bool triggersOn(String ref) =>
      tagFilters.any((filter) => filterPattern(filter).hasMatch(ref));

  test('the tag filters cover the current pubspec version', () {
    expect(triggersOn('v${pubspec['version']}'), isTrue);
  });

  test('the tag filters cover build and prerelease suffixes', () {
    expect(triggersOn('v1.2.3+4'), isTrue);
    expect(triggersOn('v1.2.3-beta.1'), isTrue);
  });

  test('the tag filters ignore refs that are not a release tag', () {
    expect(triggersOn('1.2.3'), isFalse, reason: 'missing the v prefix');
    expect(triggersOn('v1.2'), isFalse, reason: 'not a full version');
    expect(triggersOn('v1.2.x'), isFalse, reason: 'not a number');
    expect(triggersOn('main'), isFalse);
  });

  test('the workflow does not publish on a branch push', () {
    expect(push.containsKey('branches'), isFalse);
    expect(triggers.containsKey('pull_request'), isFalse);
  });

  test('publishing waits for the analyze and test job', () {
    expect(workflow['jobs']['publish']['needs'], 'validate');
  });

  test('publishing keeps the permissions checkout and OIDC need', () {
    final permissions = workflow['jobs']['publish']['permissions'] as YamlMap;
    expect(permissions['contents'], 'read');
    expect(permissions['id-token'], 'write');
  });
}
