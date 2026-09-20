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

/// Runs the awk expression the workflow uses to read a top level field out of
/// `pubspec.yaml`, so the shell and the parser cannot drift apart unnoticed.
String awkField(String field, String pubspecPath) {
  final result = Process.runSync('awk', [
    '/^$field:/ { print \$2; exit }',
    pubspecPath,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return (result.stdout as String).trim();
}

/// The steps of [job], as plain maps.
List<YamlMap> stepsOf(YamlMap job) =>
    (job['steps'] as YamlList).cast<YamlMap>().toList();

/// The index of the first step of [job] whose `run` or `uses` mentions
/// [needle], or -1 when there is none.
int indexOfStep(YamlMap job, String needle) => stepsOf(job).indexWhere(
  (step) =>
      '${step['run'] ?? ''}'.contains(needle) ||
      '${step['uses'] ?? ''}'.contains(needle),
);

/// Runs the awk program the release job uses to pull one version's section out
/// of `CHANGELOG.md`.
String changelogSection(String version, String changelogPath) {
  final result = Process.runSync('awk', [
    '-v',
    'heading=## $version',
    r'''
      $0 == heading { inside = 1; next }
      inside && /^## / { exit }
      inside { print }
    ''',
    changelogPath,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return (result.stdout as String).trim();
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

  group('the release only ever ships the tree as it is checked in', () {
    test('the dry run waits until the SDK rewrites are undone', () {
      final validate = workflow['jobs']['validate'] as YamlMap;
      final restore = indexOfStep(validate, 'git checkout -- .');
      final dryRun = indexOfStep(validate, 'dart pub publish --dry-run');
      expect(
        restore,
        isNonNegative,
        reason: 'the Flutter tool rewrites analysis_options.yaml',
      );
      expect(restore, lessThan(dryRun));
    });

    test('the archive is built after the rewrites are undone', () {
      final publish = workflow['jobs']['publish'] as YamlMap;
      final restore = indexOfStep(publish, 'git checkout -- .');
      final upload = indexOfStep(publish, 'dart pub publish --force');
      expect(restore, isNonNegative);
      expect(restore, lessThan(upload));
    });
  });

  group('the two ways of authenticating', () {
    final publish = workflow['jobs']['publish'] as YamlMap;
    final steps = stepsOf(publish);
    final oidc = steps.firstWhere(
      (step) => '${step['uses'] ?? ''}'.contains('dart-lang/setup-dart'),
    );
    final stored = steps.firstWhere(
      (step) => '${step['run'] ?? ''}'.contains('pub-credentials.json'),
    );

    test('never run together', () {
      // pub prefers the PUB_TOKEN that setup-dart exports over a stored
      // credential whatever the credentials file holds, so provisioning both
      // publishes as nobody.
      expect(oidc['if'], "env.PUB_CREDENTIALS == ''");
      expect(stored['if'], "env.PUB_CREDENTIALS != ''");
    });

    test('read the same secret', () {
      expect(publish['env']['PUB_CREDENTIALS'], contains('PUB_CREDENTIALS'));
    });
  });

  group('the version the workflow shell reads', () {
    test('is the one the pubspec parser reads', () {
      expect(awkField('version', 'pubspec.yaml'), '${pubspec['version']}');
      expect(awkField('name', 'pubspec.yaml'), '${pubspec['name']}');
    });

    test('ignores a version key nested under a dependency', () {
      final directory = Directory.systemTemp.createTempSync('pubspec');
      addTearDown(() => directory.deleteSync(recursive: true));
      final pubspecPath = '${directory.path}/pubspec.yaml';
      File(pubspecPath).writeAsStringSync(
        'name: demo\n'
        'version: 1.2.3\n'
        '\n'
        'dependencies:\n'
        '  something:\n'
        '    version: 9.9.9\n',
      );
      expect(awkField('version', pubspecPath), '1.2.3');
    });
  });

  test('a version that is already on pub.dev stops the release', () {
    final validate = workflow['jobs']['validate'] as YamlMap;
    final check = stepsOf(validate).firstWhere(
      (step) => '${step['run'] ?? ''}'.contains('pub.dev/api/packages'),
    );
    expect(check['if'], isNull, reason: 'a retried release has no tag to check');
    expect('${check['run']}', contains('exit 1'));
  });
  group('the GitHub release', () {
    final release = workflow['jobs']['release'] as YamlMap;

    test('waits for the publish job and only runs on a tag', () {
      expect(release['needs'], 'publish');
      expect(release['if'], "github.ref_type == 'tag'");
    });

    test('is the only job allowed to write to the repository', () {
      expect((release['permissions'] as YamlMap)['contents'], 'write');
      final publish = workflow['jobs']['publish'] as YamlMap;
      expect((publish['permissions'] as YamlMap)['contents'], 'read');
    });

    test('takes its notes from the changelog entry for this version', () {
      final section = changelogSection('${pubspec['version']}', 'CHANGELOG.md');
      expect(section, isNotEmpty);
      expect(section, isNot(contains('## ')));
    });

    test('stops at the previous entry, and is empty for a missing one', () {
      final directory = Directory.systemTemp.createTempSync('changelog');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}/CHANGELOG.md';
      File(path).writeAsStringSync(
        '## 2.0.0\n'
        '\n'
        '* the new one\n'
        '\n'
        '## 1.0.0\n'
        '\n'
        '* the old one\n',
      );
      expect(changelogSection('2.0.0', path), '* the new one');
      expect(changelogSection('9.9.9', path), isEmpty);
    });
  });
}
