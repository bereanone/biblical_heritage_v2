enum ViewerInterlinearDisplayStyle { englishPhrases, fullInterlinear }

class ViewerInterlinearSettings {
  const ViewerInterlinearSettings({
    this.displayStyle = ViewerInterlinearDisplayStyle.englishPhrases,
    this.englishOrder = false,
    this.showEnglishGloss = true,
    this.showOriginalText = true,
    this.showTransliteration = true,
    this.showPronunciation = true,
    this.showStrongsNumber = true,
    this.showMorphology = false,
  });

  final ViewerInterlinearDisplayStyle displayStyle;
  final bool englishOrder;
  final bool showEnglishGloss;
  final bool showOriginalText;
  final bool showTransliteration;
  final bool showPronunciation;
  final bool showStrongsNumber;
  final bool showMorphology;

  ViewerInterlinearSettings copyWith({
    ViewerInterlinearDisplayStyle? displayStyle,
    bool? englishOrder,
    bool? showEnglishGloss,
    bool? showOriginalText,
    bool? showTransliteration,
    bool? showPronunciation,
    bool? showStrongsNumber,
    bool? showMorphology,
  }) {
    return ViewerInterlinearSettings(
      displayStyle: displayStyle ?? this.displayStyle,
      englishOrder: englishOrder ?? this.englishOrder,
      showEnglishGloss: showEnglishGloss ?? this.showEnglishGloss,
      showOriginalText: showOriginalText ?? this.showOriginalText,
      showTransliteration: showTransliteration ?? this.showTransliteration,
      showPronunciation: showPronunciation ?? this.showPronunciation,
      showStrongsNumber: showStrongsNumber ?? this.showStrongsNumber,
      showMorphology: showMorphology ?? this.showMorphology,
    );
  }
}
