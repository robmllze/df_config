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
  group('translationSourceHash', () {
    test('is pinned — changing the algorithm orphans every stored entry', () {
      // Golden values. If this test fails, the hash algorithm has changed:
      // every `<key>@@<hash>` entry already stored in every consumer database
      // (df_localization clients, server-side translation maps) will silently
      // stop resolving. Do not update these expectations without shipping a
      // migration.
      expect(translationSourceHash('Welcome'), '684a08ca341f3c12');
      expect(translationSourceHash(''), '000015050000cde7');
      expect(translationSourceHash('Hello {__NAME__}'), '075c747b2b3675c3');
      expect(translationSourceHash('Größe — ¿señor? 你好'), '76115ea5365c2e83');
    });

    test('is deterministic and 16 lowercase hex chars', () {
      for (final s in ['a', 'ab', 'Welcome!', '{}', 'x' * 500]) {
        final h = translationSourceHash(s);
        expect(h, translationSourceHash(s));
        expect(h, matches(RegExp(r'^[0-9a-f]{16}$')));
      }
    });

    test('differs for edited copy, including equal-length edits', () {
      expect(
        translationSourceHash('Welcome!'),
        isNot(translationSourceHash('Welcome?')),
      );
      expect(
        translationSourceHash('aaaaaaaa'),
        isNot(translationSourceHash('aaaaaaab')),
      );
    });
  });

  group('versionedTranslationKey', () {
    test('composes key, separator, and source hash', () {
      expect(
        versionedTranslationKey('welcome_key', 'Welcome'),
        'welcome_key${kTranslationVersionSeparator}684a08ca341f3c12',
      );
    });

    test('separator is pinned to @@', () {
      // Also load-bearing in consumer databases — see the golden note above.
      expect(kTranslationVersionSeparator, '@@');
    });
  });
}
