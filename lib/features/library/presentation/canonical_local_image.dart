import 'dart:io';

import 'package:path/path.dart' as p;

enum CanonicalLocalImageStatus { resolved, missing, rejected }

class CanonicalLocalImageResolution {
  const CanonicalLocalImageResolution({required this.status, this.file});
  final CanonicalLocalImageStatus status;
  final File? file;
}

/// Resolves only an existing file lexically and physically contained by root.
/// URI schemes, absolute paths, traversal, and symlink escapes are rejected.
CanonicalLocalImageResolution resolveCanonicalLocalImage({
  required Directory sourceRoot,
  required String source,
}) {
  final value = source.trim();
  if (value.isEmpty ||
      p.isAbsolute(value) ||
      RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(value)) {
    return const CanonicalLocalImageResolution(
      status: CanonicalLocalImageStatus.rejected,
    );
  }
  final rootPath = p.canonicalize(sourceRoot.absolute.path);
  final candidatePath = p.canonicalize(p.join(rootPath, value));
  if (!p.isWithin(rootPath, candidatePath)) {
    return const CanonicalLocalImageResolution(
      status: CanonicalLocalImageStatus.rejected,
    );
  }
  final candidate = File(candidatePath);
  if (!candidate.existsSync()) {
    return const CanonicalLocalImageResolution(
      status: CanonicalLocalImageStatus.missing,
    );
  }
  try {
    final physicalRoot = sourceRoot.resolveSymbolicLinksSync();
    final physicalCandidate = candidate.resolveSymbolicLinksSync();
    if (!p.equals(physicalRoot, physicalCandidate) &&
        !p.isWithin(physicalRoot, physicalCandidate)) {
      return const CanonicalLocalImageResolution(
        status: CanonicalLocalImageStatus.rejected,
      );
    }
  } on FileSystemException {
    return const CanonicalLocalImageResolution(
      status: CanonicalLocalImageStatus.missing,
    );
  }
  return CanonicalLocalImageResolution(
    status: CanonicalLocalImageStatus.resolved,
    file: candidate,
  );
}
