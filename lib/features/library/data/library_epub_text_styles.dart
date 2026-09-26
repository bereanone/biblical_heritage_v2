import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Resolves the text emphasis used by EPUB exporters without applying their
/// fixed page sizes, colors or fonts to the accessible reader.
///
/// Simple tag, ID and compound class selectors are supported. Complex layout
/// selectors and at-rules are deliberately not broadened into global rules.
class EpubTextStyles {
  const EpubTextStyles.empty() : _rules = const [];
  EpubTextStyles._(this._rules);
  final List<_TextRule> _rules;

  factory EpubTextStyles.read(String html, String href, Archive? archive) {
    final rules = <_TextRule>[];
    final visited = <String>{};
    void addCss(String css) {
      final clean = css.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
      // Consume whole at-rules (including nested media rules). Their contents
      // must not accidentally become unconditional formatting.
      var depth = 0;
      var start = 0;
      for (var i = 0; i < clean.length; i++) {
        if (clean[i] == '{') {
          if (depth == 0) start = start.clamp(0, i);
          depth++;
        } else if (clean[i] == '}' && depth > 0) {
          depth--;
          if (depth != 0) continue;
          final chunk = clean.substring(start, i + 1).trim();
          start = i + 1;
          if (chunk.startsWith('@')) continue;
          final open = chunk.indexOf('{');
          if (open < 0) continue;
          final declarations = _declarations(
            chunk.substring(open + 1, chunk.length - 1),
          );
          if (declarations.isEmpty) continue;
          for (final selector in chunk.substring(0, open).split(',')) {
            final rule = _TextRule.parse(selector.trim(), declarations);
            if (rule != null) rules.add(rule);
          }
        } else if (clean[i] == ';' && depth == 0) {
          start = i + 1;
        }
      }
    }

    for (final match in RegExp(
      r'<(?:link\b[^>]*>|style\b[^>]*>.*?</style\s*>)',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html)) {
      final element = match.group(0)!;
      if (element.toLowerCase().startsWith('<style')) {
        addCss(
          element.substring(element.indexOf('>') + 1, element.lastIndexOf('<')),
        );
        continue;
      }
      if (archive == null ||
          !(_attribute(element, 'rel') ?? '')
              .toLowerCase()
              .split(RegExp(r'\s+'))
              .contains('stylesheet')) {
        continue;
      }
      final link = _attribute(element, 'href');
      if (link == null) continue;
      final uri = Uri.tryParse(link);
      if (uri == null || uri.hasScheme || uri.hasAuthority) continue;
      String decoded;
      try {
        decoded = Uri.decodeComponent(uri.path);
      } on FormatException {
        continue;
      }
      final path = p.posix.normalize(
        p.posix.join(p.posix.dirname(href), decoded),
      );
      if (!visited.add(path)) continue;
      for (final entry in archive.files) {
        if (entry.name == path && entry.isFile) {
          addCss(utf8.decode(entry.content as List<int>, allowMalformed: true));
          break;
        }
      }
    }
    return EpubTextStyles._(rules);
  }

  Map<String, bool> resolve(
    String tag,
    String attributes, {
    Map<String, bool> inherited = const {},
  }) => _resolve(tag, attributes, inherited: inherited)
    ..removeWhere(
          (key, _) => key.startsWith('align:') || key.startsWith('font-size:') || key.startsWith('margin:'),
    );

  /// Relative block sizes remain tied to the reader's chosen body size.
  /// Fixed print sizes and inherited/container-dependent units are not applied.
  double? resolveFontScale(String tag, String attributes) {
    String? winner;
    var priority = -1;
    void apply(
      Map<String, ({bool value, bool important})> declarations,
      int specificity,
    ) {
      for (final entry in declarations.entries.where(
        (e) => e.key.startsWith('font-size:'),
      )) {
        final score = specificity + (entry.value.important ? 100000 : 0);
        if (score >= priority) {
          priority = score;
          winner = entry.key.substring('font-size:'.length);
        }
      }
    }

    for (final rule in _rules) {
      if (rule.matches(tag, attributes))
        apply(rule.declarations, rule.specificity);
    }
    apply(_declarations(_attribute(attributes, 'style') ?? ''), 10000);
    final match = RegExp(
      r'^([0-9]*\.?[0-9]+)\s*(em|%)$',
    ).firstMatch(winner ?? '');
    if (match == null) return null;
    final value = double.parse(match[1]!);
    return (match[2] == '%' ? value / 100 : value).clamp(0.7, 2.0).toDouble();
  }

  String? resolveAlignment(String tag, String attributes) {
    final values = _resolve(tag, attributes);
    for (final alignment in const [
      'left',
      'right',
      'center',
      'justify',
      'start',
      'end',
    ]) {
      if (values['align:$alignment'] == true) return alignment;
    }
    return null;
  }

  // Tiny percentage gaps from print exporters are normalized to line spacing,
  // not expanded into the reader's ordinary paragraph separation.
  bool hasCompactVerticalMargins(String tag, String attributes) {
    final values = _resolve(tag, attributes);
    return values['margin:top'] == true && values['margin:bottom'] == true;
  }

  Map<String, bool> _resolve(
    String tag,
    String attributes, {
    Map<String, bool> inherited = const {},
  }) {
    final result = Map<String, bool>.of(inherited);
    switch (tag) {
      case 'em' || 'i':
        result['italic'] = true;
      case 'strong' || 'b':
        result['bold'] = true;
      case 'u':
        result['underline'] = true;
      case 'sup':
        result['superscript'] = true;
      case 'sub':
        result['subscript'] = true;
    }
    final winners = <String, ({int priority, bool value})>{};
    void apply(
      Map<String, ({bool value, bool important})> declarations,
      int specificity,
    ) {
      for (final entry in declarations.entries) {
        final priority = specificity + (entry.value.important ? 100000 : 0);
        if ((winners[entry.key]?.priority ?? -1) <= priority) {
          winners[entry.key] = (priority: priority, value: entry.value.value);
        }
      }
    }

    for (final rule in _rules) {
      if (rule.matches(tag, attributes)) {
        apply(rule.declarations, rule.specificity);
      }
    }
    apply(_declarations(_attribute(attributes, 'style') ?? ''), 10000);
    for (final entry in winners.entries) {
      result[entry.key] = entry.value.value;
    }
    return result;
  }
}

class _TextRule {
  _TextRule(this.tag, this.id, this.classes, this.declarations);
  final String? tag;
  final String? id;
  final List<String> classes;
  final Map<String, ({bool value, bool important})> declarations;
  int get specificity =>
      (id == null ? 0 : 100) + classes.length * 10 + (tag == null ? 0 : 1);
  static _TextRule? parse(
    String selector,
    Map<String, ({bool value, bool important})> declarations,
  ) {
    if (!RegExp(
          r'^(?:[a-zA-Z][\w-]*|\*)?(?:[.#][\w-]+)*$',
        ).hasMatch(selector) ||
        selector.isEmpty) {
      return null;
    }
    final tag = RegExp(
      r'^[a-zA-Z][\w-]*',
    ).firstMatch(selector)?.group(0)?.toLowerCase();
    final ids = RegExp(r'#([\w-]+)').allMatches(selector).toList();
    if (ids.length > 1) return null;
    return _TextRule(
      tag,
      ids.isEmpty ? null : ids.single.group(1),
      RegExp(
        r'\.([\w-]+)',
      ).allMatches(selector).map((m) => m.group(1)!).toList(),
      declarations,
    );
  }

  bool matches(String elementTag, String attrs) {
    if (tag != null && tag != elementTag) return false;
    if (id != null && id != _attribute(attrs, 'id')) return false;
    final elementClasses = (_attribute(attrs, 'class') ?? '')
        .split(RegExp(r'\s+'))
        .toSet();
    return classes.every(elementClasses.contains);
  }
}

String? _attribute(String attrs, String name) => RegExp(
  '\\b$name\\s*=\\s*["\']([^"\']*)["\']',
  caseSensitive: false,
).firstMatch(attrs)?.group(1);

Map<String, ({bool value, bool important})> _declarations(String css) {
  final result = <String, ({bool value, bool important})>{};
  for (final declaration in css.split(';')) {
    final colon = declaration.indexOf(':');
    if (colon < 0) continue;
    final property = declaration.substring(0, colon).trim().toLowerCase();
    final raw = declaration.substring(colon + 1).trim().toLowerCase();
    final important = raw.contains('!important');
    final value = raw.replaceAll('!important', '').trim();
    if (property == 'margin' || property == 'margin-top' || property == 'margin-bottom') {
      final parts = value.split(RegExp(r'\s+'));
      if (parts.isEmpty || parts.length > (property == 'margin' ? 4 : 1) ||
          parts.any((v) => !RegExp(r'^-?(?:\d*\.)?\d+(?:em|rem|px|pt|%)?$').hasMatch(v))) continue;
      final sides = <String, String>{
        if (property == 'margin' || property == 'margin-top') 'top': parts.first,
        if (property == 'margin' || property == 'margin-bottom') 'bottom': parts.length >= 3 ? parts[2] : parts.first,
      };
      for (final side in sides.entries) {
        final key = 'margin:${side.key}';
        if (result[key]?.important == true && !important) continue;
        final percentage = side.value.endsWith('%') ? double.tryParse(side.value.substring(0, side.value.length - 1)) : null;
        result[key] = (value: RegExp(r'^0(?:\.0+)?(?:em|rem|px|pt|%)?$').hasMatch(side.value) || (percentage != null && percentage >= 0 && percentage <= 1), important: important);
      }
      continue;
    }
    if (property == 'font-size') {
      final prior = result.entries
          .where((e) => e.key.startsWith('font-size:'))
          .firstOrNull;
      if (prior?.value.important == true && !important) continue;
      result.removeWhere((key, _) => key.startsWith('font-size:'));
      result['font-size:$value'] = (value: true, important: important);
      continue;
    }
    if (property == 'text-align' &&
        const [
          'left',
          'right',
          'center',
          'justify',
          'start',
          'end',
        ].contains(value)) {
      for (final alignment in const [
        'left',
        'right',
        'center',
        'justify',
        'start',
        'end',
      ]) {
        final key = 'align:$alignment';
        if (result[key]?.important == true && !important) continue;
        result[key] = (value: alignment == value, important: important);
      }
      continue;
    }
    String? mark;
    bool? enabled;
    if (property == 'font-style') {
      mark = 'italic';
      enabled = switch (value) {
        'italic' || 'oblique' => true,
        'normal' => false,
        _ => null,
      };
    } else if (property == 'font-weight') {
      mark = 'bold';
      final weight = int.tryParse(value);
      enabled = switch (value) {
        'bold' || 'bolder' => true,
        'normal' => false,
        _ => weight == null ? null : weight >= 600,
      };
    } else if (property == 'text-decoration' ||
        property == 'text-decoration-line') {
      mark = 'underline';
      enabled = value.contains('underline')
          ? true
          : value == 'none'
          ? false
          : null;
    }
    if (mark == null || enabled == null) continue;
    if (result[mark]?.important == true && !important) continue;
    result[mark] = (value: enabled, important: important);
  }
  return result;
}
