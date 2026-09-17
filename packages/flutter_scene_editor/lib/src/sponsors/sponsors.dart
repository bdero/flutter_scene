/// Sponsors baked into an editor build.
///
/// The hosting app bundles a `sponsors.json` manifest and the editor reads it
/// once at startup. Each release therefore carries the sponsor list as of its
/// build, which is the placement the sponsorship program promises, "in every
/// editor release published during the term".
///
/// Manifest shape, dates as `YYYY-MM-DD`, logo paths as asset keys of the
/// hosting app:
///
/// ```json
/// {
///   "updated": "2026-09-17",
///   "sponsors": [
///     {"name": "Acme", "tier": "gold", "url": "https://acme.example",
///      "logo": "assets/sponsors/logos/acme.png",
///      "logoDark": "assets/sponsors/logos/acme_dark.png",
///      "since": "2026-09-01", "until": null}
///   ],
///   "backers": ["A. Person"]
/// }
/// ```
library;

import 'dart:convert';

import 'package:flutter/services.dart';

/// Company sponsorship tiers, lowest first. Placement rules derive from the
/// tier so the manifest never has to spell them out.
enum SponsorTier {
  bronze('Bronze'),
  silver('Silver'),
  gold('Gold'),
  platinum('Platinum'),
  patron('Patron');

  const SponsorTier(this.label);

  final String label;

  static SponsorTier? parse(String? value) {
    if (value == null) return null;
    final needle = value.trim().toLowerCase();
    for (final tier in values) {
      if (tier.name == needle) return tier;
    }
    return null;
  }

  bool atLeast(SponsorTier other) => index >= other.index;

  /// Named in the About dialog from Silver.
  bool get inAboutDialog => atLeast(silver);

  /// Logo on the start screen from Gold.
  bool get onStartScreen => atLeast(gold);

  /// Start-screen logo height relative to Gold.
  double get startScreenScale => switch (this) {
    patron => 1.7,
    platinum => 1.35,
    _ => 1.0,
  };
}

class Sponsor {
  const Sponsor({
    required this.name,
    required this.tier,
    this.url,
    this.logo,
    this.logoDark,
    this.since,
    this.until,
  });

  final String name;
  final SponsorTier tier;
  final String? url;

  /// Asset key of the logo for light backgrounds; null shows the name.
  final String? logo;

  /// Asset key of the logo for dark backgrounds; null falls back to [logo].
  final String? logoDark;
  final DateTime? since;
  final DateTime? until;

  bool isActiveOn(DateTime day) {
    final start = since;
    final end = until;
    if (start != null && day.isBefore(start)) return false;
    if (end != null && day.isAfter(end)) return false;
    return true;
  }

  String? logoFor(Brightness brightness) =>
      brightness == Brightness.dark ? (logoDark ?? logo) : logo;

  /// Null for an entry with no name or an unknown tier, so one bad entry
  /// never hides the rest of the manifest.
  static Sponsor? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final tier = SponsorTier.parse(json['tier'] as String?);
    if (name is! String || name.trim().isEmpty || tier == null) return null;
    String? text(String key) =>
        json[key] is String ? json[key] as String : null;
    DateTime? date(String key) {
      final value = text(key);
      return value == null ? null : DateTime.tryParse(value);
    }

    return Sponsor(
      name: name.trim(),
      tier: tier,
      url: text('url'),
      logo: text('logo'),
      logoDark: text('logoDark'),
      since: date('since'),
      until: date('until'),
    );
  }
}

class SponsorManifest {
  const SponsorManifest({this.sponsors = const [], this.backers = const []});

  static const empty = SponsorManifest();

  final List<Sponsor> sponsors;

  /// Individual backers, named in the About credits.
  final List<String> backers;

  bool get isEmpty => sponsors.isEmpty && backers.isEmpty;

  /// Parses a manifest, dropping entries it cannot read. Malformed input
  /// yields [empty] rather than throwing, since a broken manifest must never
  /// keep the editor from starting.
  static SponsorManifest parse(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return empty;
      final sponsors = <Sponsor>[];
      final rawSponsors = decoded['sponsors'];
      if (rawSponsors is List) {
        for (final entry in rawSponsors) {
          final sponsor = Sponsor.fromJson(entry);
          if (sponsor != null) sponsors.add(sponsor);
        }
      }
      final backers = <String>[];
      final rawBackers = decoded['backers'];
      if (rawBackers is List) {
        for (final entry in rawBackers) {
          if (entry is String && entry.trim().isNotEmpty) {
            backers.add(entry.trim());
          }
        }
      }
      return SponsorManifest(sponsors: sponsors, backers: backers);
    } catch (_) {
      return empty;
    }
  }

  /// Loads the hosting app's manifest asset; a missing asset yields [empty].
  static Future<SponsorManifest> load(String assetKey) async {
    try {
      return parse(await rootBundle.loadString(assetKey));
    } catch (_) {
      return empty;
    }
  }

  /// Sponsors active on [day], highest tier first, then by name.
  List<Sponsor> active(DateTime day) {
    final list = sponsors.where((s) => s.isActiveOn(day)).toList();
    list.sort((a, b) {
      final byTier = b.tier.index.compareTo(a.tier.index);
      return byTier != 0 ? byTier : a.name.compareTo(b.name);
    });
    return list;
  }

  List<Sponsor> forAboutDialog(DateTime day) =>
      active(day).where((s) => s.tier.inAboutDialog).toList();

  List<Sponsor> forStartScreen(DateTime day) =>
      active(day).where((s) => s.tier.onStartScreen).toList();
}
