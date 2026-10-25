class MinistryCommunityLink {
  const MinistryCommunityLink({required this.label, required this.url});
  final String label;
  final String url;
}

/// Partner presentation and offer eligibility are independent of ownership.
class MinistryProfile {
  const MinistryProfile({
    required this.id,
    required this.name,
    required this.unlockPriceUsdCents,
    this.codes = const [],
    this.artworkAsset,
    this.websiteUrl,
    this.communityLinks = const [],
    this.accentColorArgb = 0xFF805817,
    this.folder,
    this.starterTags = const [],
    this.seedRevision = 1,
  });

  final String id;
  final String name;
  final int unlockPriceUsdCents;
  final List<String> codes;
  final String? artworkAsset;
  final String? websiteUrl;
  final List<MinistryCommunityLink> communityLinks;
  final int accentColorArgb;
  final String? folder;
  final List<String> starterTags;
  final int seedRevision;

  static const biblicalHeritage = MinistryProfile(
    id: 'biblical_heritage',
    name: 'Biblical Heritage',
    websiteUrl: 'https://biblicalheritage.net',
    unlockPriceUsdCents: 1999,
  );
  static const adventDefenseLeague = MinistryProfile(
    id: 'adl',
    name: 'The Advent Defense League',
    codes: ['ADL'],
    websiteUrl: 'https://adventdefenseleague.com',
    unlockPriceUsdCents: 999,
    artworkAsset: 'assets/partners/adl_welcome.png',
    folder: 'Advent Defense League',
    // Await the League's approved list; artwork examples are not seed data.
    starterTags: [],
  );
  static const heritageAndHope = MinistryProfile(
    id: 'heritage_and_hope',
    name: 'Heritage & Hope Ministries',
    codes: ['HH', 'HERITAGE AND HOPE', 'HERITAGE & HOPE', 'BIBLICAL HOPE'],
    unlockPriceUsdCents: 999, // HH offer approved during store setup.
    artworkAsset: 'assets/partners/heritage_hope_welcome.png',
    websiteUrl: 'https://heritageandhope.org',
    accentColorArgb: 0xFF142C58,
  );
  static const available = [
    biblicalHeritage,
    adventDefenseLeague,
    heritageAndHope,
  ];

  static MinistryProfile? forCode(String code) {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    for (final profile in available) {
      if (profile.codes.any((value) => value.toUpperCase() == normalized)) {
        return profile;
      }
    }
    return null;
  }

  static MinistryProfile? byId(String id) {
    for (final profile in available) {
      if (profile.id == id) return profile;
    }
    return null;
  }
}

class MinistryEnrollment {
  const MinistryEnrollment({
    required this.ministryId,
    required this.setupCompleted,
    required this.grandfathered,
    required this.firstSeenUtc,
  });
  final String ministryId;
  final bool setupCompleted;
  final bool grandfathered;
  final DateTime firstSeenUtc;

  MinistryProfile? get profile => MinistryProfile.byId(ministryId);

  /// ADL is a discount affiliation in the shared app, not a branded edition.
  /// Keep ministryId intact for offer eligibility and existing enrollments.
  MinistryProfile get displayProfile => ministryId == MinistryProfile.adventDefenseLeague.id
      ? MinistryProfile.biblicalHeritage
      : profile ?? MinistryProfile.biblicalHeritage;
  DateTime get trialEndsUtc => firstSeenUtc.add(const Duration(days: 14));

  MinistryEnrollment select(MinistryProfile profile) => MinistryEnrollment(
    ministryId: profile.id,
    setupCompleted: true,
    grandfathered: grandfathered,
    firstSeenUtc: firstSeenUtc,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'ministry_id': ministryId,
    'setup_completed': setupCompleted,
    'grandfathered': grandfathered,
    'first_seen_utc': firstSeenUtc.toUtc().toIso8601String(),
  };

  factory MinistryEnrollment.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['ministry_id'] is! String ||
        json['setup_completed'] is! bool ||
        json['grandfathered'] is! bool) {
      throw const FormatException('Cannot read saved ministry setup.');
    }
    return MinistryEnrollment(
      ministryId: json['ministry_id'] as String,
      setupCompleted: json['setup_completed'] as bool,
      grandfathered: json['grandfathered'] as bool,
      firstSeenUtc: DateTime.parse(json['first_seen_utc'] as String).toUtc(),
    );
  }
}
