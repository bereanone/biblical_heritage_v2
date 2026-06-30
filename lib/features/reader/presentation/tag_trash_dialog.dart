import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'tag_quick_apply_helper.dart';

class HashTagTrashDialog extends StatefulWidget {
  const HashTagTrashDialog({
    super.key,
    required this.repository,
    required this.onRestored,
    this.tag,
    this.category,
    this.scopeLabel,
    this.entryPoint = 'unknown',
    this.onOpenGlobalTrash,
  });

  final HashTagRepository repository;
  final String? tag;
  final String? category;
  final String? scopeLabel;
  final String entryPoint;
  final Future<void> Function() onRestored;
  final Future<void> Function()? onOpenGlobalTrash;

  static String titleForScope({
    String? tag,
    String? category,
    String? scopeLabel,
  }) {
    final label = scopeLabel?.trim() ?? '';
    if (label.isNotEmpty) return 'Trash — $label';
    final tagLabel = tag?.trim() ?? '';
    if (tagLabel.isNotEmpty) return 'Trash — $tagLabel';
    final categoryLabel = category?.trim() ?? '';
    if (categoryLabel.isNotEmpty) return 'Trash — $categoryLabel';
    return 'Trash';
  }

  @override
  State<HashTagTrashDialog> createState() => _HashTagTrashDialogState();
}

enum _TrashItemAction { restoreOriginal, moveElsewhere, deletePermanently }

class _TrashMoveDestination {
  const _TrashMoveDestination({required this.tag, this.category});

  final String tag;
  final String? category;
}

class _DestinationTagOption {
  const _DestinationTagOption({
    required this.tag,
    required this.count,
    required this.categories,
  });

  final String tag;
  final int count;
  final List<String> categories;

  String? get primaryCategory => categories.isEmpty ? null : categories.first;

  bool matchesCategory(String? category) {
    final normalized = category?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return categories.isEmpty;
    return categories.any((value) => value.toLowerCase() == normalized);
  }
}

class _DestinationChoice<T> {
  const _DestinationChoice({
    required this.value,
    required this.label,
    required this.searchText,
    this.subtitle,
  });

  final T value;
  final String label;
  final String searchText;
  final String? subtitle;
}

class _SelectionPick<T> {
  const _SelectionPick(this.value);

  final T value;
}

class _HashTagTrashDialogState extends State<HashTagTrashDialog> {
  late final String? _scopeTag;
  late final String? _scopeCategory;
  late final String? _scopeLabel;
  List<HashTagTrashedEntry> _entries = const [];
  bool _loading = true;
  String? _loadErrorMessage;
  final Set<int> _restoringIds = {};
  final Set<int> _deletingIds = {};
  int _reloadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scopeTag = _normalizedScopeValue(widget.tag);
    _scopeCategory = _normalizedScopeValue(widget.category);
    _scopeLabel = _normalizedScopeValue(widget.scopeLabel);
    if (kDebugMode) {
      debugPrint(
        '[TrashDialog] open entryPoint=${widget.entryPoint} '
        'scopeKind=$_scopeKind tag=${_scopeTag ?? "<none>"} '
        'category=${_scopeCategory ?? "<none>"}',
      );
    }
    _load(operation: 'initial');
  }

  String? _normalizedScopeValue(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  String get _scopeKind {
    if (_scopeTag != null) return 'tag';
    if (_scopeCategory != null) return 'category';
    return 'global';
  }

  String get _scopeDescriptor {
    final tag = _scopeTag;
    if (tag != null) return 'tag=$tag';
    final category = _scopeCategory;
    if (category != null) return 'category=$category';
    return 'global';
  }

  String get _scopeHelperText {
    if (_scopeKind == 'tag') return 'Showing trashed cards for this tag only.';
    if (_scopeKind == 'category') {
      return 'Showing trashed cards in this category.';
    }
    return 'Showing trashed cards from all tags.';
  }

  String get _emptyScopeMessage {
    if (_scopeKind == 'tag') return 'No trashed cards for this tag.';
    if (_scopeKind == 'category') return 'No trashed cards in this category.';
    return 'No trashed cards.';
  }

  Future<void> _load({required String operation}) async {
    final requestId = ++_reloadGeneration;
    final tag = _scopeTag;
    final category = _scopeCategory;

    if (kDebugMode) {
      debugPrint(
        '[TrashDialog] reload start op=$operation '
        'entryPoint=${widget.entryPoint} scopeKind=$_scopeKind '
        'scope=$_scopeDescriptor',
      );
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _loadErrorMessage = null;
      });
    }
    try {
      if (kDebugMode) {
        debugPrint(
          '[TrashDialog] scope values op=$operation '
          'entryPoint=${widget.entryPoint} '
          'tag=${tag ?? "<none>"} category=${category ?? "<none>"}',
        );
      }
      final entries = await widget.repository.loadAllTrashedEntries(
        tag: tag,
        category: category,
      );
      if (!mounted || requestId != _reloadGeneration) return;
      if (kDebugMode) {
        debugPrint(
          '[TrashDialog] reload complete op=$operation '
          'entryPoint=${widget.entryPoint} '
          'scopeKind=$_scopeKind count=${entries.length}',
        );
      }
      setState(() {
        _entries = entries;
        _loadErrorMessage = null;
      });
    } catch (error, stackTrace) {
      debugPrint('[TrashDialog] reload failed op=$operation: $error');
      debugPrint(stackTrace.toString());
      if (!mounted || requestId != _reloadGeneration) return;
      setState(() {
        _entries = const [];
        _loadErrorMessage = 'Could not load trash.';
      });
    } finally {
      if (mounted && requestId == _reloadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _restore(HashTagTrashedEntry entry) async {
    if (mounted) {
      setState(() => _restoringIds.add(entry.numericId));
    }
    try {
      if (kDebugMode) {
        debugPrint(
          '[TrashDialog] restore started tag=${entry.tagName} '
          'category=${entry.category ?? "<none>"}',
        );
      }
      await widget.repository.restoreEntry(
        entry.numericId,
        normalized: entry.isNormalized,
      );
      if (!mounted) return;
      await _load(operation: 'restore');
      if (!mounted) return;
      _refreshParentAfterMutation('restore');
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint(
          '[TrashDialog] restore completed tag=${entry.tagName} '
          'category=${entry.category ?? "<none>"}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _restoringIds.remove(entry.numericId));
      }
    }
  }

  Future<void> _restoreToDestination(
    HashTagTrashedEntry entry,
    _TrashMoveDestination destination,
  ) async {
    if (mounted) {
      setState(() => _restoringIds.add(entry.numericId));
    }
    try {
      final rawCategory = destination.category?.trim();
      final normalizedCategory = rawCategory == null || rawCategory.isEmpty
          ? null
          : rawCategory;
      if (kDebugMode) {
        debugPrint(
          '[TrashDialog] move started tag=${entry.tagName} '
          'requestedTag=${destination.tag} '
          'rawCategory=${destination.category ?? "<none>"} '
          'normalizedCategory=${normalizedCategory ?? "<none>"}',
        );
      }
      final restored = await widget.repository.restoreTrashedEntryToDestination(
        entry.numericId,
        normalized: entry.isNormalized,
        tag: destination.tag,
        category: destination.category,
      );
      if (!restored) {
        _showSnack('Could not restore ${entry.tagName}.');
        return;
      }
      if (!mounted) return;
      await _load(operation: 'move');
      if (!mounted) return;
      _refreshParentAfterMutation('move');
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint(
          '[TrashDialog] move completed tag=${entry.tagName} '
          'requestedTag=${destination.tag} '
          'rawCategory=${destination.category ?? "<none>"} '
          'normalizedCategory=${normalizedCategory ?? "<none>"}',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[TrashDialog] move/restore failed: $error');
      debugPrint(stackTrace.toString());
      _showSnack('Could not restore ${entry.tagName}.');
    } finally {
      if (mounted) {
        setState(() => _restoringIds.remove(entry.numericId));
      }
    }
  }

  Future<void> _deletePermanently(HashTagTrashedEntry entry) async {
    if (mounted) {
      setState(() => _deletingIds.add(entry.numericId));
    }
    try {
      if (kDebugMode) {
        debugPrint(
          '[TrashDialog] permanent delete started tag=${entry.tagName}',
        );
      }
      final deleted = await widget.repository.permanentlyDeleteTrashedEntry(
        entry.numericId,
        normalized: entry.isNormalized,
      );
      if (deleted <= 0) {
        _showSnack('Could not delete ${entry.tagName} permanently.');
        return;
      }
      if (!mounted) return;
      await _load(operation: 'permanent_delete');
      if (!mounted) return;
      _refreshParentAfterMutation('permanent_delete');
      if (!mounted) return;
    } catch (error, stackTrace) {
      debugPrint('[TrashDialog] permanent delete failed: $error');
      debugPrint(stackTrace.toString());
      _showSnack('Could not delete ${entry.tagName} permanently.');
    } finally {
      if (mounted) {
        setState(() => _deletingIds.remove(entry.numericId));
      }
    }
  }

  Future<void> _emptyTrash() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadErrorMessage = null;
      });
    }
    try {
      if (kDebugMode) {
        debugPrint(
          '[TrashDialog] empty trash started scopeKind=$_scopeKind '
          'scope=$_scopeDescriptor',
        );
      }
      final deleted = await widget.repository.emptyTrash(
        tag: _scopeTag,
        category: _scopeCategory,
      );
      if (kDebugMode) {
        debugPrint('[TrashDialog] empty trash deleted=$deleted');
      }
      if (!mounted) return;
      await _load(operation: 'empty_trash');
      if (!mounted) return;
      _refreshParentAfterMutation('empty_trash');
      if (!mounted) return;
    } catch (error, stackTrace) {
      debugPrint('[TrashDialog] empty trash failed: $error');
      debugPrint(stackTrace.toString());
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _loadErrorMessage = 'Could not load trash.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _scopeDescriptionMessage() {
    final tag = _scopeTag;
    if (tag != null) return 'in tag $tag';
    final category = _scopeCategory;
    if (category != null) return 'in category $category';
    final scopeLabel = _scopeLabel;
    if (scopeLabel != null) return 'in $scopeLabel';
    return 'in this view';
  }

  String _emptyTrashMessage() {
    final scope = _scopeDescriptionMessage();
    return 'This will permanently delete all trashed cards $scope. '
        'This cannot be undone.';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _refreshParentAfterMutation(String operation) {
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint('[TrashDialog] parent refresh started after $operation');
    }
    unawaited(() async {
      try {
        await widget.onRestored();
        if (kDebugMode) {
          debugPrint('[TrashDialog] parent refresh completed after $operation');
        }
      } catch (error, stackTrace) {
        debugPrint(
          '[TrashDialog] parent refresh failed after $operation: $error',
        );
        debugPrint(stackTrace.toString());
      }
    }());
  }

  Future<List<String>> _loadDestinationCategoryChoices({
    String? currentCategory,
  }) async {
    final categories = <String>[];
    final seen = <String>{};

    void addCategory(String? value) {
      final normalized = value?.trim() ?? '';
      if (normalized.isEmpty) return;
      final key = normalized.toLowerCase();
      if (seen.add(key)) {
        categories.add(normalized);
      }
    }

    addCategory(currentCategory);

    try {
      final categoryOptions = await widget.repository.loadCategoryOptions();
      for (final value in categoryOptions) {
        addCategory(value);
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[TrashDialog] destination category loadCategoryOptions failed: $error',
        );
        debugPrint(stackTrace.toString());
      }
    }

    try {
      final summaries = await widget.repository.loadSummaries();
      for (final summary in summaries) {
        addCategory(summary.category);
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[TrashDialog] destination category loadSummaries failed: $error',
        );
        debugPrint(stackTrace.toString());
      }
    }

    categories.sort(
      (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
    );
    return categories;
  }

  Future<List<_DestinationTagOption>> _loadDestinationTagChoices({
    String? preferredCategory,
  }) async {
    try {
      final summaries = await widget.repository.loadSummaries();
      final optionsByKey = <String, _DestinationTagOption>{};
      for (final summary in summaries) {
        final tag = summary.tag.trim();
        if (tag.isEmpty) continue;
        final category = summary.category?.trim();
        final categories = <String>[];
        if (category != null && category.isNotEmpty) {
          categories.add(category);
        }
        final key = summary.identityKey;
        final existing = optionsByKey[key];
        if (existing == null) {
          optionsByKey[key] = _DestinationTagOption(
            tag: summary.tag,
            count: summary.count,
            categories: categories,
          );
          continue;
        }
        final mergedCategories = <String>[
          ...existing.categories,
          ...categories,
        ];
        final dedupedCategories = <String>[];
        final categorySeen = <String>{};
        for (final value in mergedCategories) {
          final normalized = value.trim();
          if (normalized.isEmpty) continue;
          if (categorySeen.add(normalized.toLowerCase())) {
            dedupedCategories.add(normalized);
          }
        }
        optionsByKey[key] = _DestinationTagOption(
          tag: existing.tag,
          count: existing.count + summary.count,
          categories: dedupedCategories,
        );
      }

      final options = optionsByKey.values.toList(growable: false);
      final hasPreferredCategory =
          (preferredCategory?.trim().isNotEmpty ?? false);
      options.sort((left, right) {
        final leftPreferred =
            hasPreferredCategory && left.matchesCategory(preferredCategory)
            ? 0
            : 1;
        final rightPreferred =
            hasPreferredCategory && right.matchesCategory(preferredCategory)
            ? 0
            : 1;
        if (leftPreferred != rightPreferred) {
          return leftPreferred.compareTo(rightPreferred);
        }
        final tagComparison = left.tag.toLowerCase().compareTo(
          right.tag.toLowerCase(),
        );
        if (tagComparison != 0) return tagComparison;
        final leftCategory = left.primaryCategory?.toLowerCase() ?? '';
        final rightCategory = right.primaryCategory?.toLowerCase() ?? '';
        return leftCategory.compareTo(rightCategory);
      });
      return options;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[TrashDialog] destination tag loadSummaries failed: $error',
        );
        debugPrint(stackTrace.toString());
      }
      return const [];
    }
  }

  Future<_SelectionPick<T>?> _showSelectionDialog<T>({
    required String title,
    required String currentSelectionLabel,
    required String searchLabel,
    required String typedActionLabel,
    required List<_DestinationChoice<T>> choices,
    required bool Function(T value) isSelected,
    required T Function(String value) buildTypedValue,
    required String emptyMessage,
  }) async {
    final searchController = TextEditingController();
    final result = await showDialog<_SelectionPick<T>>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final query = searchController.text.trim().toLowerCase();
            final filteredChoices = query.isEmpty
                ? choices
                : choices
                      .where((choice) {
                        final searchable = choice.searchText.toLowerCase();
                        final label = choice.label.toLowerCase();
                        final subtitle = choice.subtitle?.toLowerCase() ?? '';
                        return searchable.contains(query) ||
                            label.contains(query) ||
                            subtitle.contains(query);
                      })
                      .toList(growable: false);
            final typedValue = searchController.text.trim();
            final canUseTypedValue = typedValue.isNotEmpty;

            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 560,
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      currentSelectionLabel,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      onChanged: (_) => setDialogState(() {}),
                      onSubmitted: (value) {
                        final typed = value.trim();
                        if (typed.isEmpty) return;
                        Navigator.of(
                          dialogContext,
                        ).pop(_SelectionPick<T>(buildTypedValue(typed)));
                      },
                      decoration: InputDecoration(
                        labelText: searchLabel,
                        hintText: 'Search or type a new value',
                        border: const OutlineInputBorder(),
                        suffixIcon: searchController.text.trim().isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                onPressed: () {
                                  searchController.clear();
                                  setDialogState(() {});
                                },
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredChoices.isEmpty
                          ? Center(
                              child: Text(
                                emptyMessage,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              itemCount: filteredChoices.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final choice = filteredChoices[index];
                                final selected = isSelected(choice.value);
                                return ListTile(
                                  title: Text(choice.label),
                                  subtitle: choice.subtitle == null
                                      ? null
                                      : Text(choice.subtitle!),
                                  trailing: selected
                                      ? Icon(
                                          Icons.check,
                                          color: theme.colorScheme.primary,
                                        )
                                      : null,
                                  onTap: () => Navigator.of(
                                    dialogContext,
                                  ).pop(_SelectionPick<T>(choice.value)),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: canUseTypedValue
                      ? () => Navigator.of(
                          dialogContext,
                        ).pop(_SelectionPick<T>(buildTypedValue(typedValue)))
                      : null,
                  child: Text(typedActionLabel),
                ),
              ],
            );
          },
        );
      },
    );
    searchController.dispose();
    return result;
  }

  Future<_SelectionPick<String?>?> _showCategoryPicker({
    required String? currentCategory,
  }) async {
    final categoryChoices = await _loadDestinationCategoryChoices(
      currentCategory: currentCategory,
    );
    final choices = <_DestinationChoice<String?>>[
      const _DestinationChoice<String?>(
        value: null,
        label: 'None',
        searchText: 'none uncategorized',
        subtitle: 'Uncategorized',
      ),
      ...categoryChoices.map(
        (category) => _DestinationChoice<String?>(
          value: category,
          label: category,
          searchText: '$category category',
          subtitle: 'Category',
        ),
      ),
    ];
    final normalizedCurrent = currentCategory?.trim().toLowerCase() ?? '';
    final currentLabel = normalizedCurrent.isEmpty
        ? 'Current selection: None'
        : 'Current selection: $currentCategory';
    return _showSelectionDialog<String?>(
      title: 'Destination category',
      currentSelectionLabel: currentLabel,
      searchLabel: 'Search categories',
      typedActionLabel: 'Use typed category',
      choices: choices,
      isSelected: (value) {
        final normalizedValue = value?.trim().toLowerCase() ?? '';
        if (normalizedCurrent.isEmpty) return normalizedValue.isEmpty;
        return normalizedValue == normalizedCurrent;
      },
      buildTypedValue: (value) => value.trim(),
      emptyMessage: 'No categories match this search.',
    );
  }

  Future<String?> _showTagPicker({
    required String currentTag,
    required String? preferredCategory,
  }) async {
    final tagChoices = await _loadDestinationTagChoices(
      preferredCategory: preferredCategory,
    );
    final choices = tagChoices
        .map(
          (option) => _DestinationChoice<String>(
            value: option.tag,
            label: option.tag,
            searchText: [
              option.tag,
              option.primaryCategory ?? '',
              option.categories.join(' '),
              option.count.toString(),
            ].join(' '),
            subtitle: option.primaryCategory == null
                ? 'Category: None'
                : 'Category: ${option.primaryCategory} - Active: ${option.count}',
          ),
        )
        .toList(growable: false);
    final normalizedCurrent = currentTag.trim().toLowerCase();
    final preferredLabel = preferredCategory?.trim() ?? '';
    final currentLabel = preferredLabel.isEmpty
        ? 'Current tag: ${currentTag.trim().isEmpty ? 'None' : currentTag}'
        : 'Current tag: ${currentTag.trim().isEmpty ? 'None' : currentTag} - Preferred category: $preferredLabel';
    final result = await _showSelectionDialog<String>(
      title: 'Destination tag',
      currentSelectionLabel: currentLabel,
      searchLabel: 'Search tags',
      typedActionLabel: 'Use typed tag',
      choices: choices,
      isSelected: (value) => value.trim().toLowerCase() == normalizedCurrent,
      buildTypedValue: (value) => value.trim(),
      emptyMessage: 'No tags match this search.',
    );
    return result?.value;
  }

  Future<_TrashItemAction?> _showEntryActions(HashTagTrashedEntry entry) async {
    return showDialog<_TrashItemAction>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('Trash actions'),
          content: Text(
            '${entry.tagContext}\n${entry.reference}',
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_TrashItemAction.restoreOriginal),
              child: const Text('Restore to original tag'),
            ),
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_TrashItemAction.moveElsewhere),
              child: const Text('Restore/Move to another tag...'),
            ),
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_TrashItemAction.deletePermanently),
              child: const Text('Delete permanently'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<_TrashMoveDestination?> _showMoveDestinationDialog(
    HashTagTrashedEntry entry,
  ) async {
    final tagController = TextEditingController(text: entry.tagName);
    String? destinationCategoryValue = _normalizedScopeValue(entry.category);
    final categoryController = TextEditingController(
      text: destinationCategoryValue ?? 'None',
    );
    void setDestinationCategoryValue(String? value) {
      destinationCategoryValue = _normalizedScopeValue(value);
      categoryController.text = destinationCategoryValue ?? 'None';
    }

    final result = await showDialog<_TrashMoveDestination>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Restore/Move to another tag'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Current: ${entry.tagContext}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.reference,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: tagController,
                      readOnly: true,
                      enableInteractiveSelection: false,
                      onTap: () async {
                        final chosen = await _showTagPicker(
                          currentTag: tagController.text,
                          preferredCategory: destinationCategoryValue,
                        );
                        if (!mounted || chosen == null) return;
                        tagController.text = chosen;
                        setDialogState(() {
                          errorText = null;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Destination tag',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: 'Choose existing tag',
                          onPressed: () async {
                            final chosen = await _showTagPicker(
                              currentTag: tagController.text,
                              preferredCategory: destinationCategoryValue,
                            );
                            if (!mounted || chosen == null) return;
                            tagController.text = chosen;
                            setDialogState(() {
                              errorText = null;
                            });
                          },
                          icon: const Icon(Icons.arrow_drop_down),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: categoryController,
                      readOnly: true,
                      enableInteractiveSelection: false,
                      onTap: () async {
                        final chosen = await _showCategoryPicker(
                          currentCategory: destinationCategoryValue,
                        );
                        if (!mounted || chosen == null) return;
                        setDestinationCategoryValue(chosen.value);
                        setDialogState(() {
                          errorText = null;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Destination category',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: 'Choose existing category',
                          onPressed: () async {
                            final chosen = await _showCategoryPicker(
                              currentCategory: destinationCategoryValue,
                            );
                            if (!mounted || chosen == null) return;
                            setDestinationCategoryValue(chosen.value);
                            setDialogState(() {
                              errorText = null;
                            });
                          },
                          icon: const Icon(Icons.arrow_drop_down),
                        ),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final tag = tagController.text.trim();
                    final category = destinationCategoryValue?.trim() ?? '';
                    if (tag.isEmpty) {
                      setDialogState(() {
                        errorText = 'Enter a destination tag.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _TrashMoveDestination(
                        tag: tag,
                        category: category.isEmpty ? null : category,
                      ),
                    );
                  },
                  child: const Text('Move'),
                ),
              ],
            );
          },
        );
      },
    );
    tagController.dispose();
    categoryController.dispose();
    return result;
  }

  Future<void> _handleEntryAction(HashTagTrashedEntry entry) async {
    final action = await _showEntryActions(entry);
    if (!mounted || action == null) return;
    switch (action) {
      case _TrashItemAction.restoreOriginal:
        await _restore(entry);
        return;
      case _TrashItemAction.moveElsewhere:
        final destination = await _showMoveDestinationDialog(entry);
        if (!mounted || destination == null) return;
        await _restoreToDestination(entry, destination);
        return;
      case _TrashItemAction.deletePermanently:
        await _confirmAndDeletePermanently(entry);
        return;
    }
  }

  Future<void> _confirmAndDeletePermanently(HashTagTrashedEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete permanently?'),
          content: const Text(
            'This will permanently remove this trashed card. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _deletePermanently(entry);
  }

  Future<void> _confirmAndEmptyTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('Empty trash?'),
          content: Text(
            _emptyTrashMessage(),
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Empty Trash'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _emptyTrash();
  }

  String _formatTrashedAt(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final y = dt.year;
      final mo = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final mi = dt.minute.toString().padLeft(2, '0');
      return '$y-$mo-$d $h:$mi';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = HashTagTrashDialog.titleForScope(
      tag: widget.tag,
      category: widget.category,
      scopeLabel: widget.scopeLabel,
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.restore_from_trash_outlined,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _loading || _loadErrorMessage != null
                        ? null
                        : _confirmAndEmptyTrash,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: const Text('Empty Trash'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _scopeHelperText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _loadErrorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: colorScheme.error,
                              size: 28,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _loadErrorMessage!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () => _load(operation: 'retry'),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _emptyScopeMessage,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (_scopeKind != 'global' &&
                                widget.onOpenGlobalTrash != null) ...[
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  unawaited(widget.onOpenGlobalTrash!());
                                },
                                child: const Text('Open Global Trash'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _entries.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          final restoring = _restoringIds.contains(
                            entry.numericId,
                          );
                          final dateLabel = _formatTrashedAt(entry.trashedAt);
                          final categoryLabel = entry.category?.trim() ?? '';
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 4,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _handleEntryAction(entry),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        right: 4,
                                        top: 2,
                                        bottom: 2,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Tag: ${entry.tagContext}',
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (entry.reference.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              entry.reference,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          if (entry.previewText.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              entry.previewText,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          if (dateLabel.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Trashed $dateLabel',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                          if (categoryLabel.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Category: $categoryLabel',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          if ((entry.trashedReason ?? '')
                                              .trim()
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Reason: ${entry.trashedReason!.trim()}',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                restoring
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          TextButton.icon(
                                            onPressed: () => _restore(entry),
                                            icon: const Icon(
                                              Icons.restore,
                                              size: 16,
                                            ),
                                            label: const Text('Restore'),
                                            style: TextButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          TextButton.icon(
                                            onPressed:
                                                _deletingIds.contains(
                                                  entry.numericId,
                                                )
                                                ? null
                                                : () =>
                                                      _confirmAndDeletePermanently(
                                                        entry,
                                                      ),
                                            icon: const Icon(
                                              Icons.delete_forever_outlined,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              'Delete permanently',
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor:
                                                  colorScheme.error,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
