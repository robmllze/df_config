# Changelog

## [0.8.3]

- chore: bump `df_string` constraint to `^0.4.0`. df_string 0.4.0 changes case-conversion digit-boundary handling (`phone_e164` instead of `phone_e_164`); df_config does not use the affected `String` case APIs directly, so this is a dependency-range update only.

## [0.8.2]

- fix: `Config.map`'s auto-wrap (`_wrapIfNeeded`) is now all-or-nothing instead of bracketing each delimiter independently. Previously an input that already ended in the closing token — every inline ICU plural template, e.g. `{count, plural, other{# items}}` — got a lone `{{` prepended with no matching `}}`, producing the unbalanced `{{{…}}`; the pattern engine then mangled the braces and downstream consumers such as an ICU `MessageFormat` build threw `mismatched { or }`. Auto-wrap now fires only for a bare key or a `default||key` expression and leaves any input that already carries partial delimiter structure (a lone `{`/`}`) without the key delimiter untouched — so `.tr()` passes inline ICU templates through verbatim. Fixes greyed screens in host apps that render an ICU plural before a config is installed or through a mapper-less `FileConfig`.

## [0.8.1]

- feat: Add `versionedTranslationKey(key, source)`, `translationSourceHash(source)`, and `kTranslationVersionSeparator` — a content-addressed key convention for versioned translation storage (`<key>@@<hash(sourceText)>`). Lives here rather than in `df_localization` so pure-Dart backends can key server-side translation maps with the exact convention the Flutter client resolves against. The hash is deterministic across platforms (web-safe integer math) and pinned by a golden test — do not change the algorithm.

## [0.8.0]

- Released @ 5/2026 (UTC)
- feat: Add `TranslationManager.onError` sink and `TranslationErrorSink` typedef so swallowed errors from `String.tr()` and `setConfig` can be observed
- feat: Add `PatternSettings.caseFold` for locale-aware key folding (Turkish, Azerbaijani, NFC normalisation, etc.) plus `PatternSettings.foldKey` helper
- feat: Add configurable `maxInputLength` / `maxMatches` parameters to `replacePatterns`
- fix: `TranslationFileReader` now joins paths with posix separators so translations load on Windows under Flutter's `rootBundle`
- breaking: `Config.setFields` now throws `StateError` when two source keys collide after `toString()`, and applies changes atomically (previous state is preserved on failure)
- breaking: `recursiveReplace` now throws `StateError` on cyclic input and enforces a hard depth cap to prevent unbounded loops
- breaking: `String.cf<T>` signature tightened to `Config<ConfigRef<dynamic, dynamic>>`

## [0.7.5]

- Released @ 6/2025 (UTC)
- Update dependencies

## [0.7.4]

- Released @ 6/2025 (UTC)
- Update dependencies

## [0.7.2]

- Released @ 6/2025 (UTC)
- chore: Update dependencies
- Update dependencies

## [0.7.1]

- Released @ 3/2025 (UTC)
- docs: Update readme

## [0.7.0]

- Released @ 3/2025 (UTC)
- breaking: Restructure and update dependencies

## [0.6.2]

- Released @ 2/2025 (UTC)
- fix: Fix dependency issue

## [0.6.1]

- Released @ 2/2025 (UTC)
- chore: Update dependencies

## [0.6.0]

- Released @ 2/2025 (UTC)
- breaking: Update dependencies

## [0.5.5]

- Released @ 2/2025 (UTC)
- fix: Bug happening with newline characters

## [0.5.4]

- Released @ 2/2025 (UTC)
- chore: Update dependencies

## [0.5.3]

- Released @ 2/2025 (UTC)
- chore: Update dependencies

## [0.5.1]

- Released @ 2/2025 (UTC)
- chore: Update dependencies and examples

## [0.5.0]

- Released @ 2/2025 (UTC)
- breaking: Update dependencies and docs

## [0.4.0]

- Released @ 2/2025 (UTC)
- chore: Clean code and update dependencies

## [0.3.0]

- Released @ 2/2025 (UTC)
- chore: Separate translation features into df_config library, update comments
- chore: Update license information in code files
- feat: Add a catagory param to the tr exension method

## [0.2.0]

- Released @ 2/2025 (UTC)
- chore: Update dependencies, docs and comments

## [0.1.2]

- Released @ 2/2025 (UTC)
- chore: Update workflow scripts

## [0.1.1]

- Released @ 2/2025 (UTC)
- chore: Update imports in \_index.g.dart

## [0.1.0]

- Released @ 2/2025 (UTC)
- Initial release
