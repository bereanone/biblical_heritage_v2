enum ELibraryStoragePolicy { saveSpace, keepSourceFiles, askEachRun }

extension ELibraryStoragePolicyX on ELibraryStoragePolicy {
  String get label => switch (this) {
    ELibraryStoragePolicy.saveSpace => 'Save space',
    ELibraryStoragePolicy.keepSourceFiles => 'Keep source files',
    ELibraryStoragePolicy.askEachRun => 'Ask each time',
  };

  String get description => switch (this) {
    ELibraryStoragePolicy.saveSpace =>
      'Remove managed source files after verified import.',
    ELibraryStoragePolicy.keepSourceFiles =>
      'Keep downloaded source files for backup or re-import.',
    ELibraryStoragePolicy.askEachRun =>
      'Ask before removing source files after each import run.',
  };

  String get storedValue => name;

  bool get removesSourcesAfterVerifiedImport =>
      this == ELibraryStoragePolicy.saveSpace;

  static ELibraryStoragePolicy fromStoredValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'keepsourcefiles':
      case 'keep_source_files':
        return ELibraryStoragePolicy.keepSourceFiles;
      case 'askeachrun':
      case 'ask_each_run':
        return ELibraryStoragePolicy.askEachRun;
      case 'save_space':
      case 'save-space':
      case 'savespace':
      default:
        return ELibraryStoragePolicy.saveSpace;
    }
  }
}
