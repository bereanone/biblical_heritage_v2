import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/bootstrap/development_runtime_overrides.dart';

void main() {
  test('database overrides default inactive', () {
    expect(developmentELibraryDatabaseOverride(), isNull);
    expect(developmentUserDatabaseOverride(), isNull);
  });

  test('debug override accepts an existing absolute path', () {
    expect(
      resolveDevelopmentDatabaseOverride(
        suppliedPath: '/private/tmp/disposable.db',
        label: 'test.db',
        releaseMode: false,
        fileExists: (_) => true,
      ),
      '/private/tmp/disposable.db',
    );
  });

  test('release ignores a supplied override', () {
    expect(
      resolveDevelopmentDatabaseOverride(
        suppliedPath: '/private/tmp/disposable.db',
        label: 'test.db',
        releaseMode: true,
        fileExists: (_) => true,
      ),
      isNull,
    );
  });

  test('relative and missing override paths fail without fallback', () {
    expect(
      () => resolveDevelopmentDatabaseOverride(
        suppliedPath: 'disposable.db',
        label: 'test.db',
        releaseMode: false,
        fileExists: (_) => true,
      ),
      throwsStateError,
    );
    expect(
      () => resolveDevelopmentDatabaseOverride(
        suppliedPath: '/private/tmp/missing.db',
        label: 'test.db',
        releaseMode: false,
        fileExists: (_) => false,
      ),
      throwsStateError,
    );
  });

  test('database override inputs are independent', () {
    expect(
      resolveDevelopmentDatabaseOverride(
        suppliedPath: '/private/tmp/elibrary.db',
        label: 'eLibrary.db',
        releaseMode: false,
        fileExists: (_) => true,
      ),
      isNot(
        resolveDevelopmentDatabaseOverride(
          suppliedPath: '/private/tmp/user.db',
          label: 'user.db',
          releaseMode: false,
          fileExists: (_) => true,
        ),
      ),
    );
  });

  test('scan suppression defaults false and is disabled in release', () {
    expect(shouldSkipCaptureClipperStartupScan(), isFalse);
    expect(
      shouldSkipCaptureClipperStartupScan(
        releaseMode: false,
        suppliedValue: true,
      ),
      isTrue,
    );
    expect(
      shouldSkipCaptureClipperStartupScan(
        releaseMode: true,
        suppliedValue: true,
      ),
      isFalse,
    );
  });
}
