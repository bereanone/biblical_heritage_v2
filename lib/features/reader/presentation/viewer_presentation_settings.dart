enum PresentationAspectRatioPreset {
  auto('Auto', null),
  fourByThree('4:3', 4 / 3),
  sixteenByTen('16:10', 16 / 10),
  sixteenByNine('16:9', 16 / 9),
  twentyOneByNine('21:9', 21 / 9);

  const PresentationAspectRatioPreset(this.label, this.aspectRatio);

  final String label;
  final double? aspectRatio;

  static PresentationAspectRatioPreset fromStorage(String? value) {
    for (final preset in PresentationAspectRatioPreset.values) {
      if (preset.name == value) return preset;
    }
    return PresentationAspectRatioPreset.auto;
  }
}
