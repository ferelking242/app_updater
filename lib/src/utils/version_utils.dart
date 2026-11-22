/// Version comparison helpers shared by every update source.
///
/// Versions may be plain (`1.2.3`), prefixed (`v1.2.3`) or suffixed
/// (`1.2.3+42`, `1.2.3-beta.1`). Only the numeric core is compared; build
/// metadata and pre-release suffixes never make a version newer.
class VersionUtils {
  VersionUtils._();

  /// A dotted version (`8.1.573`) is always preferred over a lone number, so
  /// `app-arm64-v8a-1.4.2` resolves to `1.4.2` and not to `8`.
  static final RegExp _dottedPattern = RegExp(r'\d+\.\d+(?:\.\d+)*');
  static final RegExp _integerPattern = RegExp(r'\d+');

  /// Extracts the numeric core of [value] (`v1.2.3+4` -> `1.2.3`).
  static String? normalize(String? value) {
    if (value == null) return null;
    final dotted = _dottedPattern.firstMatch(value);
    if (dotted != null) return dotted.group(0);
    return _integerPattern.firstMatch(value)?.group(0);
  }

  /// Returns the build number of `1.2.3+42`, or null when absent.
  static int? buildNumber(String? value) {
    if (value == null) return null;
    final match = RegExp(r'\+(\d+)').firstMatch(value);
    return int.tryParse(match?.group(1) ?? '');
  }

  /// Compares two versions: negative when [a] is older, positive when newer.
  static int compare(String a, String b) {
    final left = _parts(a);
    final right = _parts(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  /// True when [candidate] is strictly newer than [current].
  static bool isNewer(String current, String candidate) =>
      compare(current, candidate) < 0;

  static List<int> _parts(String value) {
    final core = normalize(value) ?? '0';
    return core
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }
}
