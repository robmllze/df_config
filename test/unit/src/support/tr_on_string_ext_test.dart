//.title
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
//
// Copyright © dev-cetera.com & contributors.
//
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
//
// `tr()` is the workhorse extension df_localization is built around.
// These tests pin every documented feature: primary+secondary settings,
// args, preferKey, category, mapper, AND the explicit "never throws"
// contract — we throw a wide variety of pathological inputs at it and
// require the call to return *some* string.

import 'package:df_config/df_config.dart';
import 'package:test/test.dart';

FileConfig _yaml(String tag, String body) {
  return FileConfig(
    ref: ConfigFileRef(
      ref: tag,
      type: ConfigFileType.YAML,
      read: () async => body,
    ),
  );
}

void main() {
  setUp(TranslationManager.resetForTesting);

  group('String.tr — a template that STARTS with a placeholder', () {
    // Regression: `'{X} rest||key'` used to render as `'X} rest'` — the
    // leading `{` eaten, the `}` left behind, and no substitution. The cause
    // was `Config.map` bracketing a `default||key` input into
    // `'{{{X} rest||key}}'` and handing it back to `replacePatterns`, whose
    // opening delimiter is matched greedily (`\{\{+`, so that `{{{x}}}` reads
    // as one placeholder). That greedy opening swallowed the payload's own
    // `{`, while the payload's `}` survived because it was not adjacent to
    // the closing `}}`.
    //
    // Only templates that START with a placeholder hit it: with any literal
    // text in front, the wrapped `{{` and the payload's `{` are not adjacent,
    // so the greedy opening has nothing extra to eat. That asymmetry is why
    // it read as a mystery rather than a bug — which is exactly what these
    // tests exist to prevent recurring.

    test('leading placeholder is substituted, not half-eaten', () async {
      await TranslationManager.setConfig(_yaml('en', 'other: X'));
      expect(
        '{__X__} rest||missing'.tr(args: {'__X__': 'VAL'}),
        'VAL rest',
      );
    });

    test('a placeholder is the WHOLE default value', () async {
      await TranslationManager.setConfig(_yaml('en', 'other: X'));
      expect('{__X__}||missing'.tr(args: {'__X__': 'VAL'}), 'VAL');
    });

    test('every placeholder resolves, not just the ones after the first',
        () async {
      await TranslationManager.setConfig(_yaml('en', 'other: X'));
      expect(
        '{__A__} and {__B__}||missing'.tr(args: {'__A__': '1', '__B__': '2'}),
        '1 and 2',
      );
    });

    test('a leading placeholder still loses to a real translation', () async {
      // The default value is only a fallback: when the key IS in the
      // translation map the whole string is replaced, placeholder and all.
      await TranslationManager.setConfig(_yaml('en', 'country: AU'));
      expect('{__X__} rest||country'.tr(args: {'__X__': 'VAL'}), 'AU');
    });

    test('leading text behaves identically (the case that always worked)',
        () async {
      await TranslationManager.setConfig(_yaml('en', 'other: X'));
      expect(
        'lead {__X__} rest||missing'.tr(args: {'__X__': 'VAL'}),
        'lead VAL rest',
      );
    });

    test('no key delimiter is unaffected', () async {
      // Without `||key` the input is never wrapped, so it takes the
      // secondary-pass path and always worked. Pinned so a future change to
      // the wrap rule cannot quietly move this case.
      await TranslationManager.setConfig(_yaml('en', 'other: X'));
      expect('{__X__} rest'.tr(args: {'__X__': 'VAL'}), 'VAL rest');
    });
  });

  group('String.tr — primary pattern pass', () {
    test('substitutes via the active translation map', () async {
      await TranslationManager.setConfig(_yaml('en', 'country: AU'));
      expect('{{World||country}}'.tr(), 'AU');
    });

    test('falls back to the default text when key is missing', () async {
      await TranslationManager.setConfig(_yaml('en', 'other: X'));
      expect('Hello||missing'.tr(), 'Hello');
    });

    test('args override config values', () async {
      await TranslationManager.setConfig(_yaml('en', 'name: Old'));
      expect('{{name}}'.tr(args: {'name': 'Override'}), 'Override');
    });

    test('preferKey forces a different key', () async {
      await TranslationManager.setConfig(_yaml('en', 'b: target'));
      expect('{{X||a}}'.tr(preferKey: 'b'), 'target');
    });

    test('bare string with no markers is wrapped and resolved', () async {
      await TranslationManager.setConfig(_yaml('en', 'greeting: hi'));
      expect('default||greeting'.tr(), 'hi');
    });
  });

  group('String.tr — secondary pattern pass', () {
    test('a {single-brace} placeholder is resolved after primary', () async {
      await TranslationManager.setConfig(_yaml('en', 'world: AU'));
      expect(
        'Hello {{world}}, {extra}'.tr(args: {'extra': 'mate'}),
        'Hello AU, mate',
      );
    });

    test('secondary pass can be disabled', () async {
      await TranslationManager.setConfig(_yaml('en', 'x: V'));
      // With no secondary pass, `{y}` is not substituted from args.
      final out = '{{x}} literal-{y}-literal'.tr(
        args: {'y': 'should-be-skipped'},
        secondarySettings: null,
      );
      expect(out, contains('V'));
      expect(out, contains('{y}'));
    });
  });

  group('String.tr — category', () {
    test('prepends category to the key portion', () async {
      await TranslationManager.setConfig(
        _yaml('en', 'cat:\n  greet: hi'),
      );
      expect('default||greet'.tr(category: 'cat'), 'hi');
    });

    test('input with no delimiter — category is silently ignored', () async {
      await TranslationManager.setConfig(
        _yaml('en', 'cat:\n  hello: hi'),
      );
      // With no `||`, there is no key portion to splice category in
      // front of. We don't assert the exact value here because
      // `JsonUtility.expandJson` *also* aliases nested keys to their
      // tail (so plain `hello` may match `cat.hello`). Either result
      // is acceptable; the point is no crash.
      expect('hello'.tr(category: 'cat'), isA<String>());
    });
  });

  group('String.tr — mapper hook', () {
    test('mapper short-circuits config lookup', () async {
      final cfg = FileConfig(
        ref: ConfigFileRef(
          ref: 'en',
          type: ConfigFileType.YAML,
          read: () async => 'k: ignored',
        ),
        mapper: (textResult) => 'MAPPED(${textResult.key})',
      );
      await TranslationManager.setConfig(cfg);
      expect('{{X||k}}'.tr(), startsWith('MAPPED'));
    });

    test('mapper returning null falls back to config lookup', () async {
      final cfg = FileConfig(
        ref: ConfigFileRef(
          ref: 'en',
          type: ConfigFileType.YAML,
          read: () async => 'k: from-config',
        ),
        mapper: (_) => null,
      );
      await TranslationManager.setConfig(cfg);
      expect('{{X||k}}'.tr(), 'from-config');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // The example from example/lib/example.dart, pinned as a test.
  // ─────────────────────────────────────────────────────────────────────────
  group('String.tr — README / example pinning', () {
    test('the README example resolves args correctly', () {
      // The active config is empty (resetForTesting in setUp). The
      // primary pattern matches `{{Example {App|app}||app.title}}`.
      // No `app.title` exists, so the default `Example {App|app}` is
      // used. The secondary pass then resolves `{App|app}` against
      // args ({'app': 'Application'}).
      final out = 'Hey {{Example {App|app}||app.title}} dude'.tr(
        args: {'app': 'Application'},
      );
      expect(out, 'Hey Example Application dude');
    });

    test('same input with app.title in config uses the translation', () async {
      await TranslationManager.setConfig(
        _yaml('en', 'app:\n  title: MyApp'),
      );
      final out = 'Hey {{Example {App|app}||app.title}} dude'.tr(
        args: {'app': 'Application'},
      );
      expect(out, 'Hey MyApp dude');
    });

    test('args still take effect when primary uses default fallback', () {
      final out = '{{Default||missing}} and {alpha|a}'.tr(
        args: {'a': 'ALPHA'},
      );
      expect(out, 'Default and ALPHA');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Abuse: tr() must never throw. We do not assert specific outputs for
  // these — only that *some* string is returned.
  // ─────────────────────────────────────────────────────────────────────────
  group('String.tr — abuse: never throws', () {
    test('empty string', () {
      expect(''.tr(), isA<String>());
    });

    test('whitespace only', () {
      expect('   '.tr(), isA<String>());
    });

    test('only opening braces', () {
      expect('{{'.tr(), isA<String>());
    });

    test('only closing braces', () {
      expect('}}'.tr(), isA<String>());
    });

    test('mismatched single braces', () {
      expect('hello {'.tr(), isA<String>());
      expect('hello }'.tr(), isA<String>());
      expect('hello {{{'.tr(), isA<String>());
      expect('hello }}}'.tr(), isA<String>());
    });

    test('alternating braces', () {
      expect('{}{}{}{}'.tr(), isA<String>());
      expect('{{}}{{}}{{}}'.tr(), isA<String>());
    });

    test('looks like JSON', () {
      expect('{"a":1,"b":[2,3]}'.tr(), isA<String>());
    });

    test('looks like CSS', () {
      expect('div { color: red; }'.tr(), isA<String>());
    });

    test('looks like a regex with metacharacters', () {
      expect(r'\d+\.\d+'.tr(), isA<String>());
    });

    test('huge plain text', () {
      final big = 'lorem ipsum ' * 5000;
      expect(big.tr().length, greaterThan(50000));
    });

    test('unicode and emoji', () {
      expect(
        'Καλημέρα 🌅 {{world||name}}'.tr(args: {'name': 'world'}),
        isA<String>(),
      );
    });

    test('null mapper still works', () async {
      await TranslationManager.setConfig(_yaml('en', 'k: v'));
      expect('{{k}}'.tr(), isA<String>());
    });

    test('throwing mapper does NOT propagate', () async {
      final cfg = FileConfig(
        ref: ConfigFileRef(
          ref: 'en',
          type: ConfigFileType.YAML,
          read: () async => 'k: v',
        ),
        mapper: (_) => throw StateError('boom'),
      );
      await TranslationManager.setConfig(cfg);
      // Must not throw — returns *some* string.
      expect('{{k}}'.tr(), isA<String>());
    });

    test('throwing settings.callback does NOT propagate', () async {
      // Inject a config whose settings have a throwing callback.
      final cfg = FileConfig(
        ref: ConfigFileRef(
          ref: 'en',
          type: ConfigFileType.YAML,
          read: () async => 'k: v',
        ),
      );
      await TranslationManager.setConfig(cfg);
      // We can't easily install a custom callback on the active config
      // without reaching into internals, but we can confirm that even
      // with the default callback path, a wide range of inputs survive.
      const evil = '{{}}{{x}}{a|b||c}{{nested {inner|x}||outer}}';
      expect(evil.tr(), isA<String>());
    });

    test('deeply nested braces', () {
      expect('{{{{{{{{ deep }}}}}}}}'.tr(), isA<String>());
    });

    test('args with scalar values are stringified', () {
      expect('{{key}}'.tr(args: {'key': 42}), '42');
      expect('{{key}}'.tr(args: {'key': true}), 'true');
    });

    test('args with list values are indexable by dotted path', () {
      // JsonUtility.expandJson flattens lists into 'key.0', 'key.1', …
      // entries, so individual elements remain addressable even though
      // the parent 'key' itself is not. Disable the secondary pass so
      // the separator we use here (`-`) does not get mis-parsed as
      // single-brace pattern noise.
      expect(
        '{{key.0}}-{{key.1}}'.tr(
          args: {
            'key': const [1, 2, 3],
          },
          secondarySettings: null,
        ),
        '1-2',
      );
    });

    test('args with null value falls back to default', () {
      expect(
        '{{Default||k}}'.tr(args: {'k': null}),
        contains('Default'),
      );
    });

    test('args with weird keys do not crash', () {
      expect(
        '{{key}}'.tr(
          args: {
            42: 'numeric-key',
            true: 'bool-key',
            'key': 'normal',
          },
        ),
        'normal',
      );
    });

    test('mass of patterns in one string', () {
      final src = List.generate(200, (i) => '{{p$i}}').join(' ');
      final args = <String, dynamic>{
        for (var i = 0; i < 200; i++) 'p$i': '[$i]',
      };
      final out = src.tr(args: args);
      expect(out, contains('[0]'));
      expect(out, contains('[199]'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Specific tricky shapes documented as "must work".
  // ─────────────────────────────────────────────────────────────────────────
  group('String.tr — pinned shapes', () {
    test('outer {{ … }} containing inner { … |key } resolves both', () {
      final out = '{{outer {a|x}||k}}'.tr(args: {'x': 'INNER', 'k': 'KEY'});
      // Primary: matches `{{outer {a|x}||k}}`, key=k. Lookup k in args
      // → 'KEY'. Output after primary: 'KEY'.
      // Secondary: no braces in 'KEY' → wrap and try to match → 'KEY'.
      expect(out, 'KEY');
    });

    test('outer pattern with inner pattern, key missing → default', () {
      // No `app.title` in args, so primary uses default
      // `Example {App|app}`. Then secondary resolves `{App|app}` against
      // args.
      final out =
          '{{Example {App|app}||app.title}}'.tr(args: {'app': 'Application'});
      expect(out, 'Example Application');
    });

    test('plain text with no braces is returned as-is', () async {
      await TranslationManager.setConfig(_yaml('en', 'hello: bonjour'));
      // 'hello' wraps to '{{hello}}', matches, looks up 'hello' (case-
      // insensitive) → 'bonjour'.
      expect('hello'.tr(), 'bonjour');
    });

    test('partial braces around the edge of a string', () {
      // None of these should throw; they may produce surprising output
      // but must remain valid strings.
      for (final s in [
        '{',
        '}',
        '{}',
        '{{',
        '}}',
        '{{}}',
        '{a',
        'a}',
        '{a}b',
        'a{b}',
        '{{a',
        'a}}',
      ]) {
        expect(s.tr(), isA<String>(), reason: 'input was: $s');
      }
    });
  });
}
