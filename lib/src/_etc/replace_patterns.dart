//.title
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
//
// Copyright © dev-cetera.com & contributors.
//
// The use of this source code is governed by an MIT-style license described in
// the LICENSE file located in this project's root directory.
//
// See: https://opensource.org/license/mit
//
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
//.title~

import '/_common.dart';
import '_etc.g.dart';

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

/// Default cap on the input length [replacePatterns] will accept.
///
/// Keeping this finite prevents an attacker (or a buggy producer) from
/// feeding a multi-gigabyte string and exhausting memory. Callers can
/// override via the `maxInputLength` parameter when their domain
/// genuinely needs larger inputs (e.g. medical drug-interaction
/// catalogs that exceed 1 MiB).
const int kReplacePatternsMaxInputLength = 1 << 20; // 1 MiB

/// Default cap on placeholders processed in a single call. Bounds the
/// worst case where every character starts a new placeholder match.
const int kReplacePatternsMaxMatches = 10000;

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

/// Replaces placeholders in [input] with values from [data], supporting
/// default values and custom delimiters via [settings].
///
/// Substitution is a *single* left-to-right pass — values inserted by
/// the pass are not themselves re-scanned. This is deliberate:
/// re-scanning would let a malicious or recursive value (e.g.
/// `a = '{{a}}'`) loop forever, and would also make the order of
/// substitutions matter in subtle ways. Callers that want multi-level
/// resolution should pre-process their data via [recursiveReplace]
/// (which performs bounded resolution at load time, not at lookup
/// time).
///
/// **Regex shape (important for `{{{...}}}` inputs).** The opening and
/// closing delimiters are matched with a greedy `+` quantifier, so
/// `{{{x}}}` is treated as a single placeholder whose body is `x` —
/// the extra brace on each side is consumed. This is intentional and
/// is what makes the auto-wrap path in [Config.map] safe: an input
/// such as `'{X}||k'` gets wrapped to `'{{{X}||k}}'`, and the greedy
/// match swallows the outer `{` correctly. If you need literal triple
/// braces in your output, render them outside any placeholder.
///
/// **Direction-agnostic.** Matching operates on UTF-16 code units, so
/// Arabic/Hebrew/Persian content and bidi-control characters pass
/// through unchanged. To get locale-aware key folding (Turkish, etc.)
/// or Unicode normalisation, supply [PatternSettings.caseFold].
///
/// **Safety:**
///  - A buggy `settings.callback` cannot derail the whole call. Each
///    invocation is wrapped in try/catch; on failure the value chain
///    falls through to `suggested.toString()` ?? `default`. The
///    swallowed error is surfaced via
///    [TranslationManager.reportError] so a host that has installed an
///    [TranslationManager.onError] sink can detect it.
///  - [maxInputLength] and [maxMatches] are configurable so
///    safety-critical callers can tighten or loosen the limits to fit
///    their domain.
@internal
String replacePatterns(
  String input,
  Map<dynamic, dynamic> data, {
  String? preferKey,
  PatternSettings settings = const PatternSettings(),
  int maxInputLength = kReplacePatternsMaxInputLength,
  int maxMatches = kReplacePatternsMaxMatches,
}) {
  if (maxInputLength <= 0) {
    throw ArgumentError.value(maxInputLength, 'maxInputLength', 'must be > 0');
  }
  if (maxMatches <= 0) {
    throw ArgumentError.value(maxMatches, 'maxMatches', 'must be > 0');
  }
  if (input.length > maxInputLength) {
    throw ArgumentError.value(
      input.length,
      'input.length',
      'exceeds maxInputLength ($maxInputLength)',
    );
  }
  if (settings.opening.isEmpty || settings.closing.isEmpty) {
    // Cannot meaningfully match anything; return the input unchanged.
    return input;
  }
  final opening = RegExp.escape(settings.opening);
  final closing = RegExp.escape(settings.closing);
  final regex = RegExp(
    '$opening+(.*?)$closing+',
    multiLine: true,
    dotAll: true,
  );
  // Lazily build the case-folded lookup map once per call when the
  // config is case-insensitive. Rebuilding it for every match would be
  // O(n*m). The fold function is taken from [PatternSettings] so a
  // host that needs locale-aware folding (Turkish, Azerbaijani, RTL
  // normalisation) gets a consistent fold across both key parsing and
  // data lookup.
  Map<dynamic, dynamic>? foldedCache;
  Map<dynamic, dynamic> lookup() => foldedCache ??= foldLookupKeys(
        data,
        settings,
      );

  final out = StringBuffer();
  var cursor = 0;
  var matches = 0;
  for (final match in regex.allMatches(input)) {
    matches++;
    if (matches > maxMatches) {
      throw StateError(
        'replacePatterns: exceeded maxMatches ($maxMatches)',
      );
    }
    out.write(input.substring(cursor, match.start));
    final body = match.group(1)!;
    out.write(
      resolvePlaceholderBody(
        body,
        lookup(),
        preferKey: preferKey,
        settings: settings,
      ),
    );
    cursor = match.end;
  }
  out.write(input.substring(cursor));
  return out.toString();
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

/// Case-folds [data]'s keys per [settings] so lookups match the folded
/// keys [getKeyAndDefaultValue] produces. Returns [data] unchanged when
/// the settings are case-sensitive.
///
/// Callers that resolve many placeholders should cache the result — this
/// is O(n) in the map size and rebuilding it per placeholder would make
/// a whole-string pass O(n*m).
@internal
Map<dynamic, dynamic> foldLookupKeys(
  Map<dynamic, dynamic> data,
  PatternSettings settings,
) {
  if (settings.caseSensitive) return data;
  return data.map((k, v) => MapEntry(settings.foldKey(k.toString()), v));
}

/// Resolves ONE placeholder body — the text between the delimiters, or
/// an entire input that is conceptually a single placeholder — to its
/// replacement.
///
/// [lookup] must already be folded via [foldLookupKeys].
///
/// This is the whole of a placeholder's value chain in one place:
/// [PatternSettings.callback] first, then the looked-up value, then the
/// embedded default. It exists as its own function because there are
/// two callers with genuinely different framing, and they used to
/// disagree: [replacePatterns] resolves bodies it found with a regex,
/// while [Config.map] resolves an input it already KNOWS is one whole
/// placeholder and must not re-parse for delimiters. Sharing the chain
/// keeps a future change to it from landing on only one of them.
@internal
String resolvePlaceholderBody(
  String body,
  Map<dynamic, dynamic> lookup, {
  String? preferKey,
  required PatternSettings settings,
}) {
  final p = getKeyAndDefaultValue(body, settings, preferKey: preferKey);
  final suggested = lookup[p.key];
  return _safeCallback(settings, p, suggested) ??
      suggested?.toString() ??
      p.defaultValue;
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

/// Invokes [PatternSettings.callback] safely. If the user callback
/// throws, the error is forwarded to [TranslationManager.reportError]
/// (no-op when no sink is installed) and `null` is returned so the
/// normal `suggested ?? default` fallback chain proceeds.
String? _safeCallback(
  PatternSettings settings,
  TGetKeyAndDefaultValueResult p,
  dynamic suggested,
) {
  final cb = settings.callback;
  if (cb == null) return null;
  try {
    return cb(p.key, suggested, p.defaultValue);
  } catch (e, s) {
    TranslationManager.reportError('settings.callback', e, s);
    return null;
  }
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

@internal
extension ReplaceAllPatternsOnStringX on String {
  /// Replaces placeholders in this string with corresponding values
  /// from a provided map, supporting default values and custom
  /// delimiters.
  @internal
  String replacePatterns(
    Map<dynamic, dynamic> data, {
    String? preferKey,
    PatternSettings settings = const PatternSettings(),
  }) {
    return _replacePatterns(
      this,
      data,
      preferKey: preferKey,
      settings: settings,
    );
  }
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

const _replacePatterns = replacePatterns;
