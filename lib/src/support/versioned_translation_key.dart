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

import 'dart:convert' show utf8;

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

/// Separates a translation key from the source-text version hash in a
/// versioned storage key, e.g. `welcome_key@@a1b2c3d4e5f60718`.
///
/// Chosen to be extremely unlikely to appear inside a real translation key,
/// so [versionedTranslationKey] round-trips cleanly and legacy plain keys can
/// be told apart from versioned ones during migration.
const String kTranslationVersionSeparator = '@@';

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

/// Builds a content-addressed storage key for a translation entry: the plain
/// [key] suffixed with a short, stable hash of its English [source] text.
///
/// Because the hash is derived from the source copy itself, changing a string
/// yields a new key and therefore a new stored entry, while every unchanged
/// string keeps the same key and shares its existing entry. That is what lets
/// an already-deployed build keep reading the exact translation it shipped
/// against even after newer builds edit the copy — with no full-database
/// snapshot, just one new entry per string that actually changed.
///
/// This helper lives in `df_config` (pure Dart) rather than `df_localization`
/// (Flutter) deliberately: a Dart backend that produces translation maps
/// server-side can depend on this package alone to key its maps with the
/// exact same convention the client resolves against.
String versionedTranslationKey(String key, String source) {
  return '$key$kTranslationVersionSeparator${translationSourceHash(source)}';
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

/// A short, stable, platform-independent hash of [source], rendered as 16 hex
/// characters.
///
/// Determinism is the whole point — the value must be identical across app
/// launches, Dart/SDK versions, and platforms (native **and** web), otherwise
/// the same copy would resolve to different storage keys on different devices.
/// It is therefore computed with plain integer arithmetic kept below 2^53 so
/// it is exact on the web (where `int` is a JS double) rather than relying on
/// `String.hashCode` (per-run/unstable) or 64-bit bitwise ops (lossy on web).
///
/// Two 31-bit polynomial hashes evaluated at *different multipliers* are
/// combined for ~62 bits of space. The multipliers must differ — with a
/// shared multiplier and only different seeds, `h2 - h1` collapses to a
/// length-only constant, so equal-length strings that collide in one half
/// collide in both and the effective strength drops to ~31 bits. Collisions
/// only matter between differing source strings under the *same* key, so this
/// is comfortably collision-resistant for the purpose.
///
/// **Do not change this algorithm.** Stored `<key>@@<hash>` entries in every
/// consumer database are addressed by it; changing it orphans them all. It is
/// pinned by a golden test.
String translationSourceHash(String source) {
  final bytes = utf8.encode(source);
  final h1 = _polyHash(bytes, 5381, 1000003);
  final h2 = _polyHash(bytes, 52711, 1000033);
  final s1 = h1.toRadixString(16).padLeft(8, '0');
  final s2 = h2.toRadixString(16).padLeft(8, '0');
  return '$s1$s2';
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

/// Web-safe polynomial rolling hash over [bytes], evaluated at multiplier [m]
/// (a prime ~2^20, e.g. 1000003 or 1000033).
///
/// With `p < 2^31` and `m ~ 2^20`, every intermediate `h * m + b` stays below
/// ~2^51 and the `% p` result below 2^31 — all well within the 2^53 exact-
/// integer range of a JS double, so the result is identical on every backend.
int _polyHash(List<int> bytes, int seed, int m) {
  const p = 2147483647; // 2^31 - 1 (a Mersenne prime).
  var h = seed % p;
  for (final b in bytes) {
    h = (h * m + b) % p;
  }
  return h;
}
