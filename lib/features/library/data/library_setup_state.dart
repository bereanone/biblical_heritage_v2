/// Durable, resettable record of whether the user has already been through
/// (or explicitly dismissed) the "Set Up My Library" first-run flow.
/// Persisted via [LocalSettingsStore], not the canonical database — this is
/// a device-local UI preference, not library content.
enum LibrarySetupState {
  /// Never completed and never explicitly skipped.
  notStarted,

  /// The user finished a setup flow, or at least one readable book already
  /// exists, so the invitation should not reappear.
  completed,

  /// The user explicitly chose "Skip for Now".
  skipped,
}

extension LibrarySetupStateStorage on LibrarySetupState {
  String get storedValue => switch (this) {
    LibrarySetupState.notStarted => 'not_started',
    LibrarySetupState.completed => 'completed',
    LibrarySetupState.skipped => 'skipped',
  };
}

LibrarySetupState librarySetupStateFromStoredValue(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'completed':
      return LibrarySetupState.completed;
    case 'skipped':
      return LibrarySetupState.skipped;
    default:
      return LibrarySetupState.notStarted;
  }
}
