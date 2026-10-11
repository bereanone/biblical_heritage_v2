import 'package:flutter/material.dart';

class ViewerInlineNumberGrid extends StatefulWidget {
  const ViewerInlineNumberGrid({
    super.key,
    required this.values,
    required this.color,
    required this.onSelect,
    this.selectedValue,
    this.scrollToSelected = false,
    this.fontSize = 14,
    this.minimumItemExtent = 44,
  });

  final List<int> values;
  final Color color;
  final int? selectedValue;
  final ValueChanged<int> onSelect;
  final bool scrollToSelected;
  final double fontSize;
  final double minimumItemExtent;

  @override
  State<ViewerInlineNumberGrid> createState() => _ViewerInlineNumberGridState();
}

class _ViewerInlineNumberGridState extends State<ViewerInlineNumberGrid> {
  final Map<int, GlobalKey> _itemKeys = <int, GlobalKey>{};
  int? _lastScrolledValue;

  @override
  void didUpdateWidget(covariant ViewerInlineNumberGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedValue != widget.selectedValue) {
      _lastScrolledValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = ThemeData.estimateBrightnessForColor(widget.color);
    final textColor = brightness == Brightness.light
        ? Colors.black
        : Colors.white;

    if (widget.scrollToSelected &&
        widget.selectedValue != null &&
        _lastScrolledValue != widget.selectedValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final selectedKey = _itemKeys[widget.selectedValue!];
        final selectedContext = selectedKey?.currentContext;
        if (selectedContext == null) return;
        Scrollable.ensureVisible(
          selectedContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: 0.3,
        );
        _lastScrolledValue = widget.selectedValue;
      });
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final value in widget.values)
            GestureDetector(
              key: _itemKeys.putIfAbsent(value, () => GlobalKey()),
              onTap: () => widget.onSelect(value),
              child: Container(
                constraints: BoxConstraints(
                  minWidth: widget.minimumItemExtent,
                  minHeight: widget.minimumItemExtent,
                ),
                padding: widget.minimumItemExtent > 44
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
                    : EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(
                    '$value',
                    style: TextStyle(
                      fontSize: widget.fontSize,
                      fontWeight: widget.selectedValue == value
                          ? FontWeight.bold
                          : FontWeight.normal,
                      decoration: widget.selectedValue == value
                          ? TextDecoration.underline
                          : TextDecoration.none,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
