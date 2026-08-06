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
import '/src/_etc/_etc.g.dart';

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

/// A configuration class that maps placeholder strings to values.
///
/// Holds two parallel representations of the same data:
///  - [data] is the raw, untouched map as ingested via [setFields].
///  - [parsedFields] is the same map after recursive placeholder
///    resolution and flatten/expand into dotted keys, suitable for direct
///    lookup by [map].
class Config<TConfigRef extends ConfigRef<dynamic, dynamic>> extends Equatable {
  //
  //
  //

  /// The reference to the config file (or `null` for an in-memory config).
  final TConfigRef? ref;

  /// The parsed, flattened-and-expanded fields used for lookups.
  late final Map<dynamic, dynamic> parsedFields;

  /// The unparsed data as it was ingested.
  late final Map<dynamic, dynamic> data;

  /// Optional hook to override how a key/default pair resolves before the
  /// normal map lookup is attempted.
  final dynamic Function(TGetKeyAndDefaultValueResult textResult)? mapper;

  /// Placeholder syntax used by this config.
  final PatternSettings settings;

  //
  //
  //

  Config({
    this.ref,
    this.settings = const PatternSettings(),
    this.mapper,
  }) {
    parsedFields = <dynamic, dynamic>{};
    data = <dynamic, dynamic>{};
  }

  //
  //
  //

  /// Replaces the fields of this config with those derived from
  /// [source].
  ///
  /// **Atomicity.** Both [data] and [parsedFields] are derived into
  /// local variables first; only after every step succeeds are the
  /// underlying maps cleared and repopulated. If any step throws (a
  /// cycle, an over-deep recursion, a key collision, etc.), the
  /// config's previous state is preserved unchanged. Safety-critical
  /// hosts must be able to rely on never observing a half-applied
  /// config.
  ///
  /// **Key-collision safety.** If two distinct top-level keys in
  /// [source] stringify to the same string (e.g. `1` and `"1"`),
  /// [setFields] throws [StateError]. Silently overwriting one with
  /// the other would be a data-loss bug in safety-critical contexts.
  void setFields(Map<dynamic, dynamic> source) {
    final stringifiedKeys = <String>{};
    for (final k in source.keys) {
      final s = k.toString();
      if (!stringifiedKeys.add(s)) {
        throw StateError(
          'Config.setFields: duplicate key after stringification: "$s". '
          'Two distinct source keys collide on toString() — refusing to '
          'silently drop one.',
        );
      }
    }
    // Compute the new state into locals FIRST. If anything below
    // throws, both [data] and [parsedFields] stay at their previous
    // values — the config is never observed in a half-written state.
    final nextData = Map<dynamic, dynamic>.of(source);
    final resolved = recursiveReplace(source, settings: settings);
    final nextParsed = JsonUtility.i.expandJson(
      resolved.mapKeys((e) => e.toString()),
    );

    data
      ..clear()
      ..addAll(nextData);
    parsedFields
      ..clear()
      ..addAll(nextParsed);
  }

  //
  //
  //

  /// Maps [value] against this config's fields, returning the resolved
  /// value cast to [T] (or [fallback] / `null` if the resolution does
  /// not produce a value of that type).
  ///
  /// [args] supplies ad-hoc placeholder values that take precedence over
  /// [parsedFields]. [preferKey] forces a specific key, overriding any key
  /// implied by `default||key` syntax. [settings] overrides this config's
  /// default [PatternSettings] for this call only.
  T? map<T>(
    String value, {
    Map<dynamic, dynamic> args = const {},
    T? fallback,
    String? preferKey,
    PatternSettings? settings,
  }) {
    final effectiveSettings = settings ?? this.settings;
    final expandedArgs = JsonUtility.i.expandJson(
      args.mapKeys((e) => e.toString()),
    );
    final combined = <dynamic, dynamic>{...parsedFields, ...expandedArgs};
    final wrapped = _wrapIfNeeded(
      value,
      opening: effectiveSettings.opening,
      closing: effectiveSettings.closing,
      delimiter: effectiveSettings.delimiter,
    );
    final replaced = replacePatterns(
      wrapped,
      combined,
      preferKey: preferKey,
      settings: effectiveSettings,
    );
    return letOrNull<T>(replaced) ?? fallback;
  }

  //
  //
  //

  /// Identity comes from the [ref]; two configs with equal refs are
  /// considered equal even if their data diverges in flight.
  @override
  List<Object?> get props => [ref];
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

/// Wraps [input] with [opening]/[closing] so a bare key resolves as a
/// single placeholder, e.g. `Default||name` → `{{Default||name}}`.
///
/// Wrapping is **all-or-nothing** — it either brackets both sides or
/// leaves the input completely untouched. It never brackets one side
/// only, which would unbalance the delimiters (prepending a lone `{{`
/// to a string that already ends in `}}` yields `{{{…}}` — a corruption
/// the pattern engine then mangles and downstream consumers such as an
/// ICU `MessageFormat` build reject as mismatched braces).
///
/// The input is left untouched when it already carries pattern structure
/// of its own:
///  - It contains a full [opening] or [closing] token (already a
///    placeholder — do not nest it).
///  - It carries a *partial* delimiter (a lone `{`/`}` when the
///    delimiters are `{{`/`}}`) without the key [delimiter] (`||`). That
///    marks a template destined for the other resolution pass — `tr()`'s
///    single-brace secondary pass — or an inline ICU plural such as
///    `{count, plural, other{# items}}`. A `default||key` expression
///    like `{TEST}||country`, by contrast, *does* carry the key
///    delimiter and is wrapped so `country` resolves as the key.
String _wrapIfNeeded(
  String input, {
  required String opening,
  required String closing,
  required String delimiter,
}) {
  if (opening.isEmpty || closing.isEmpty) return input;
  if (input.contains(opening) || input.contains(closing)) return input;
  final delimiterChars = '$opening$closing'.split('').toSet();
  final hasPartialDelimiter = delimiterChars.any(input.contains);
  final hasKeyDelimiter = delimiter.isNotEmpty && input.contains(delimiter);
  if (hasPartialDelimiter && !hasKeyDelimiter) return input;
  return '$opening$input$closing';
}
