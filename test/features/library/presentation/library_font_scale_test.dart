import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_book_reader_screen.dart';
import 'package:studybible2/features/library/presentation/library_font_scale.dart';

void main() {
  test('contents popup TOC text scale stays compact and clamped', () {
    expect(libraryContentsPopupTocTextScale(0.2), closeTo(0.9, 0.0001));
    expect(libraryContentsPopupTocTextScale(1.0), closeTo(0.92, 0.0001));
    expect(libraryContentsPopupTocTextScale(3.0), closeTo(1.22, 0.0001));
  });

  test('contents popup TOC row padding stays compact and clamped', () {
    expect(
      libraryContentsPopupTocRowVerticalPadding(0.2, isHeading: false),
      closeTo(6.0, 0.0001),
    );
    expect(
      libraryContentsPopupTocRowVerticalPadding(3.0, isHeading: false),
      closeTo(9.5, 0.0001),
    );
    expect(
      libraryContentsPopupTocRowVerticalPadding(0.2, isHeading: true),
      closeTo(6.0, 0.0001),
    );
    expect(
      libraryContentsPopupTocRowVerticalPadding(3.0, isHeading: true),
      closeTo(10.5, 0.0001),
    );
  });

  test('contents popup TOC text style uses clamped reader font scale', () {
    final normal = libraryContentsPopupTocRowTextStyle(
      const TextStyle(fontSize: 16),
      1.0,
      isHeading: false,
      isSelected: false,
    );

    expect(normal.fontSize, closeTo(14.72, 0.0001));
    expect(normal.fontWeight, FontWeight.w500);

    final selected = libraryContentsPopupTocRowTextStyle(
      const TextStyle(fontSize: 16),
      1.0,
      isHeading: false,
      isSelected: true,
    );

    expect(selected.fontSize, closeTo(14.72, 0.0001));
    expect(selected.fontWeight, FontWeight.w600);

    final heading = libraryContentsPopupTocRowTextStyle(
      const TextStyle(fontSize: 16),
      1.0,
      isHeading: true,
      isSelected: false,
    );

    expect(heading.fontWeight, FontWeight.w600);

    final tiny = libraryContentsPopupTocRowTextStyle(
      const TextStyle(fontSize: 8),
      0.2,
      isHeading: false,
      isSelected: false,
    );

    expect(tiny.fontSize, closeTo(14.0, 0.0001));

    final huge = libraryContentsPopupTocRowTextStyle(
      const TextStyle(fontSize: 40),
      3.0,
      isHeading: false,
      isSelected: false,
    );

    expect(huge.fontSize, closeTo(22.0, 0.0001));
  });

  test('selected highlight color stays visible', () {
    final theme = ThemeData.from(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
    );

    final selected = libraryReaderSelectedColor(theme, false);

    expect(selected, isNot(equals(Colors.transparent)));
    expect(selected, isNot(equals(theme.colorScheme.surfaceContainerHigh)));
  });
}
