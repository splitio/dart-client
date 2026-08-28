final class Semver {
  final int major;
  final int minor;
  final int patch;
  final List<String> prerelease;
  final String? metadata;

  Semver._({
    required this.major,
    required this.minor,
    required this.patch,
    required this.prerelease,
    this.metadata,
  });

  static Semver? build(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    String rest = trimmed;
    String? metadata;
    final plusIdx = rest.indexOf('+');
    if (plusIdx != -1) {
      metadata = rest.substring(plusIdx + 1);
      rest = rest.substring(0, plusIdx);
    }

    List<String> prerelease = [];
    final dashIdx = rest.indexOf('-');
    if (dashIdx != -1) {
      final prePart = rest.substring(dashIdx + 1);
      if (prePart.isEmpty) return null;
      prerelease = prePart.split('.');
      for (final id in prerelease) {
        if (id.isEmpty) return null;
      }
      rest = rest.substring(0, dashIdx);
    }

    final parts = rest.split('.');
    if (parts.length != 3) return null;

    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);
    if (major == null || minor == null || patch == null) return null;
    if (major < 0 || minor < 0 || patch < 0) return null;

    return Semver._(
      major: major,
      minor: minor,
      patch: patch,
      prerelease: prerelease,
      metadata: metadata,
    );
  }

  String version() {
    final buf = StringBuffer('$major.$minor.$patch');
    if (prerelease.isNotEmpty) {
      buf.write('-');
      buf.write(prerelease.join('.'));
    }
    if (metadata != null) {
      buf.write('+');
      buf.write(metadata);
    }
    return buf.toString();
  }

  int comparePrecedence(Semver other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    if (prerelease.isEmpty && other.prerelease.isEmpty) return 0;
    if (prerelease.isEmpty) return 1;
    if (other.prerelease.isEmpty) return -1;

    final len = prerelease.length < other.prerelease.length
        ? prerelease.length
        : other.prerelease.length;

    for (int i = 0; i < len; i++) {
      final a = prerelease[i];
      final b = other.prerelease[i];
      final aNum = int.tryParse(a);
      final bNum = int.tryParse(b);

      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else if (aNum != null) {
        return -1;
      } else if (bNum != null) {
        return 1;
      } else {
        final cmp = a.compareTo(b);
        if (cmp != 0) return cmp;
      }
    }

    return prerelease.length.compareTo(other.prerelease.length);
  }
}
