/// Check for updates from stores, GitHub Releases, GitHub Actions artifacts and
/// a self-hosted CI feed, then show a native or fully custom update UI.
library;

export 'src/models/prepared_update.dart';
export 'src/models/update_candidate.dart';
export 'src/services/artifact_downloader.dart';
export 'src/sources/ci_feed_source.dart';
export 'src/sources/composite_update_source.dart';
export 'src/sources/github_artifacts_source.dart';
export 'src/sources/github_releases_source.dart';
export 'src/sources/update_source.dart';
export 'src/ui/app_updater_theme.dart';
export 'src/ui/update_dialog.dart';
export 'src/update_controller.dart';
export 'src/utils/version_utils.dart';
export 'src/version_checker.dart';
