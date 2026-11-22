import 'package:flutter/material.dart';

import '../version_checker.dart' show UpdateInfo, UpdateStrings;

/// Builds the whole update surface. When provided, it replaces the built-in
/// Material/Cupertino/Fluent/Adwaita dialogs.
typedef AppUpdaterDialogBuilder = Widget Function(
  BuildContext context,
  UpdateInfo info,
  AppUpdaterDialogActions actions,
  AppUpdaterTheme theme,
);

/// Callbacks handed to a custom [AppUpdaterDialogBuilder].
class AppUpdaterDialogActions {
  const AppUpdaterDialogActions({
    required this.onUpdate,
    required this.onLater,
    this.onSkipVersion,
    this.onDoNotAskAgain,
    this.isPersistent = false,
  });

  /// Accepts the update (opens the store or the download flow).
  final VoidCallback onUpdate;

  /// Dismisses the dialog without updating.
  final VoidCallback onLater;

  /// Remembers the version and closes the dialog.
  final VoidCallback? onSkipVersion;

  /// Stops showing update prompts.
  final VoidCallback? onDoNotAskAgain;

  /// Hides the "later" action.
  final bool isPersistent;
}

/// Visual identity of the update UI, per app.
///
/// Every app embedding `app_updater` can ship its own look without forking the
/// package:
///
/// ```dart
/// AppUpdater.configure(
///   theme: AppUpdaterTheme(
///     accentColor: const Color(0xFFFF6B35),
///     backgroundColor: const Color(0xFF0D1117),
///     surfaceColor: const Color(0xFF161B22),
///     foregroundColor: Colors.white,
///     borderRadius: BorderRadius.circular(24),
///     logo: Image.asset('assets/logo.png', height: 56),
///     strings: const UpdateStrings(updateButton: 'Installer'),
///   ),
/// );
/// ```
///
/// For total control, set [builder]: it receives the info, the actions and the
/// theme, and returns any widget.
class AppUpdaterTheme {
  const AppUpdaterTheme({
    this.accentColor,
    this.backgroundColor,
    this.surfaceColor,
    this.foregroundColor,
    this.mutedColor,
    this.borderColor,
    this.borderRadius,
    this.padding = const EdgeInsets.fromLTRB(24, 22, 24, 18),
    this.maxWidth = 420,
    this.fontFamily,
    this.titleStyle,
    this.bodyStyle,
    this.logo,
    this.icon,
    this.showVersionPills = true,
    this.showReleaseNotes = true,
    this.showSize = true,
    this.strings,
    this.builder,
  });

  final Color? accentColor;
  final Color? backgroundColor;
  final Color? surfaceColor;
  final Color? foregroundColor;
  final Color? mutedColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final EdgeInsets padding;
  final double maxWidth;
  final String? fontFamily;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;

  /// Replaces the default download icon.
  final Widget? logo;

  /// Icon used when [logo] is null.
  final IconData? icon;

  final bool showVersionPills;
  final bool showReleaseNotes;
  final bool showSize;

  /// Overrides the dialog copy (localization).
  final UpdateStrings? strings;

  /// Full control over the rendered widget.
  final AppUpdaterDialogBuilder? builder;

  /// Returns a copy with the missing colors resolved from [context].
  AppUpdaterTheme resolve(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppUpdaterTheme(
      accentColor: accentColor ?? scheme.primary,
      backgroundColor:
          backgroundColor ?? (dark ? const Color(0xFF15151C) : scheme.surface),
      surfaceColor: surfaceColor ??
          (dark ? const Color(0xFF1D1D26) : scheme.surfaceContainerHighest),
      foregroundColor: foregroundColor ?? scheme.onSurface,
      mutedColor: mutedColor ?? scheme.onSurface.withValues(alpha: 0.6),
      borderColor: borderColor ?? scheme.outline.withValues(alpha: 0.18),
      borderRadius: borderRadius ?? BorderRadius.circular(22),
      padding: padding,
      maxWidth: maxWidth,
      fontFamily: fontFamily,
      titleStyle: titleStyle,
      bodyStyle: bodyStyle,
      logo: logo,
      icon: icon,
      showVersionPills: showVersionPills,
      showReleaseNotes: showReleaseNotes,
      showSize: showSize,
      strings: strings,
      builder: builder,
    );
  }

  TextStyle titleTextStyle() =>
      titleStyle ??
      TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      );

  TextStyle bodyTextStyle() =>
      bodyStyle ??
      TextStyle(
        fontFamily: fontFamily,
        fontSize: 13.5,
        height: 1.45,
      );
}
