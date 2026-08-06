//.title
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
//
// Copyright © dev-cetera.com & contributors.
//
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
//.title~

import 'package:df_config/df_config.dart';
import 'package:test/test.dart';

void main() {
  group('Config — construction', () {
    test('default settings is PrimaryPatternSettings', () {
      final c = Config<ConfigRef<dynamic, dynamic>>();
      expect(c.settings.opening, '{{');
      expect(c.settings.closing, '}}');
      expect(c.settings.delimiter, '||');
      expect(c.settings.caseSensitive, isFalse);
    });

    test('ref defaults to null', () {
      expect(Config<ConfigRef<dynamic, dynamic>>().ref, isNull);
    });

    test('parsedFields and data are independently initialised', () {
      final c = Config<ConfigRef<dynamic, dynamic>>();
      expect(c.data, isEmpty);
      expect(c.parsedFields, isEmpty);
      expect(identical(c.data, c.parsedFields), isFalse);
    });
  });

  group('Config.setFields', () {
    test('mirrors raw data into .data', () {
      final c = Config<ConfigRef<dynamic, dynamic>>();
      c.setFields({'a': 1, 'b': '2'});
      expect(c.data, {'a': 1, 'b': '2'});
    });

    test('flattens nested maps into dotted parsedFields keys', () {
      final c = Config<ConfigRef<dynamic, dynamic>>();
      c.setFields({
        'user': {'name': 'Ada'},
      });
      expect(c.parsedFields['user.name'], 'Ada');
    });

    test('resolves cross-references during ingestion', () {
      final c = Config<ConfigRef<dynamic, dynamic>>();
      c.setFields({
        'greet': 'Hello',
        'msg': '{{greet}}, world',
      });
      expect(c.parsedFields['msg'], 'Hello, world');
    });

    test('clears previous state before applying new fields', () {
      final c = Config<ConfigRef<dynamic, dynamic>>();
      c.setFields({'a': 1});
      c.setFields({'b': 2});
      expect(c.data.containsKey('a'), isFalse);
      expect(c.parsedFields.containsKey('a'), isFalse);
      expect(c.data['b'], 2);
    });
  });

  group('Config.map', () {
    late Config<ConfigRef<dynamic, dynamic>> c;
    setUp(() {
      c = Config<ConfigRef<dynamic, dynamic>>();
      c.setFields({'name': 'World', 'count': '7'});
    });

    test('substitutes a known key', () {
      expect(c.map<String>('Hello {{name}}'), 'Hello World');
    });

    test('returns null when result is not the requested type', () {
      // 'name' is a string, so int conversion fails — and the fallback is
      // null in this overload.
      expect(c.map<int>('{{name}}'), isNull);
    });

    test('honours T when value can be parsed (string→int)', () {
      expect(c.map<int>('{{count}}'), 7);
    });

    test('uses fallback when the type does not match', () {
      expect(c.map<int>('{{name}}', fallback: -1), -1);
    });

    test('args take precedence over parsedFields', () {
      expect(
        c.map<String>('{{name}}', args: {'name': 'Override'}),
        'Override',
      );
    });

    test('wraps bare input that has no delimiters', () {
      expect(c.map<String>('Default||name'), 'World');
    });

    test('does not half-wrap an inline ICU template ending in }}', () {
      // An inline ICU plural template contains the closing delimiter `}}`
      // but no opening `{{`. It must pass through untouched — never get a
      // lone `{{` prepended, which would produce the unbalanced
      // `{{{count, plural, ...}}` and corrupt the template downstream.
      const icu = '{count, plural, one{# item} other{# items}}';
      expect(c.map<String>(icu), icu);
    });

    test('does not half-wrap input containing only the opening delimiter', () {
      const input = '{{name} trailing';
      expect(c.map<String>(input), input);
    });

    test('still wraps a {secondary}||key expression so the key resolves', () {
      // The braces make `{X}` the default; the `||` marks `name` as the
      // key. Because the key delimiter is present, the whole expression is
      // wrapped and the key wins over the braced default.
      expect(c.map<String>('{X}||name'), 'World');
    });

    test('preferKey overrides the parsed key', () {
      c.setFields({'name': 'World', 'other': 'Other'});
      expect(
        c.map<String>('{{X||name}}', preferKey: 'other'),
        'Other',
      );
    });

    test('settings override applies only to that call', () {
      // The override uses single braces; the config's default still has
      // double braces, but this single call uses the override.
      expect(
        c.map<String>(
          '{name}',
          settings: const SecondaryPatternSettings(),
        ),
        'World',
      );
      // After the call, the config still works with the default settings.
      expect(c.map<String>('{{name}}'), 'World');
    });
  });

  group('Config — equality', () {
    test('same ref → equal', () {
      final a = Config<ConfigRef<dynamic, dynamic>>(
        ref: const ConfigRef<dynamic, dynamic>(ref: 'X'),
      );
      final b = Config<ConfigRef<dynamic, dynamic>>(
        ref: const ConfigRef<dynamic, dynamic>(ref: 'X'),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different ref → not equal', () {
      final a = Config<ConfigRef<dynamic, dynamic>>(
        ref: const ConfigRef<dynamic, dynamic>(ref: 'X'),
      );
      final b = Config<ConfigRef<dynamic, dynamic>>(
        ref: const ConfigRef<dynamic, dynamic>(ref: 'Y'),
      );
      expect(a, isNot(equals(b)));
    });

    test('both ref null → equal (matches set semantics for refless)', () {
      final a = Config<ConfigRef<dynamic, dynamic>>();
      final b = Config<ConfigRef<dynamic, dynamic>>();
      expect(a, equals(b));
    });
  });

  group('Config — recursive feature surface', () {
    // The point of df_config: a config file can reference itself, so the
    // user only has to write a string once and reference it from many
    // places. These tests pin the contract end-to-end through Config.
    test('cross-references inside the source map are resolved up-front', () {
      final c = Config<ConfigRef<dynamic, dynamic>>();
      c.setFields({
        'app': {
          'name': 'AcmeApp',
          'tagline': 'Welcome to {{app.name}}',
        },
      });
      expect(c.parsedFields['app.tagline'], 'Welcome to AcmeApp');
    });

    test('chains of references resolve correctly', () {
      final c = Config<ConfigRef<dynamic, dynamic>>();
      c.setFields({
        'a': 'X',
        'b': '{{a}}',
        'c': '{{b}}',
      });
      expect(c.parsedFields['c'], 'X');
    });

    test('lookups can reach into nested keys', () {
      final c = Config<ConfigRef<dynamic, dynamic>>();
      c.setFields({
        'user': {
          'profile': {'name': 'Ada'},
        },
      });
      expect(c.map<String>('{{user.profile.name}}'), 'Ada');
    });
  });
}
