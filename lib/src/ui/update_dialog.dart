import 'package:flutter/material.dart';

import '../version_checker.dart' show UpdateInfo;
import 'app_updater_theme.dart';

/// The themed update dialog used when [AppUpdaterTheme] is configured.
///
/// It stays a plain [Dialog] so it can be shown with `showDialog` and works on
/// every platform without a `Scaffold` ancestor requirement.
class AppUpdaterUpdateDialog extends StatelessWidget {
  const AppUpdaterUpdateDialog({
    super.key,
    required this.theme,
    required this.info,
    required this.title,
    required this.message,
    required this.updateText,
    required this.laterText,
    this.skipVersionText,
    this.doNotAskAgainText,
    this.releaseNotesTitle,
    this.onUpdate,
    this.onLater,
    this.onSkipVersion,
    this.onDoNotAskAgain,
    this.isPersistent = false,
  });

  final AppUpdaterTheme theme;
  final UpdateInfo info;
  final String title;
  final String message;
  final String updateText;
  final String laterText;
  final String? skipVersionText;
  final String? doNotAskAgainText;
  final String? releaseNotesTitle;
  final VoidCallback? onUpdate;
  final VoidCallback? onLater;
  final VoidCallback? onSkipVersion;
  final VoidCallback? onDoNotAskAgain;
  final bool isPersistent;

  @override
  Widget build(BuildContext context) {
    final resolved = theme.resolve(context);
    final actions = AppUpdaterDialogActions(
      onUpdate: onUpdate ?? () {},
      onLater: onLater ?? () {},
      onSkipVersion: onSkipVersion,
      onDoNotAskAgain: onDoNotAskAgain,
      isPersistent: isPersistent,
    );

    final builder = resolved.builder;
    if (builder != null) {
      return builder(context, info, actions, resolved);
    }

    final textColor = resolved.foregroundColor!;
    final muted = resolved.mutedColor!;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: resolved.maxWidth),
        child: Container(
          padding: resolved.padding,
          decoration: BoxDecoration(
            color: resolved.backgroundColor,
            borderRadius: resolved.borderRadius,
            border: Border.all(color: resolved.borderColor!, width: 0.8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 32,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _badge(resolved),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style:
                          resolved.titleTextStyle().copyWith(color: textColor),
                    ),
                  ),
                  if (!isPersistent)
                    IconButton(
                      tooltip: laterText,
                      onPressed: () {
                        Navigator.of(context).pop();
                        actions.onLater();
                      },
                      icon: Icon(Icons.close_rounded, size: 18, color: muted),
                    ),
                ],
              ),
              if (resolved.showVersionPills) ...[
                const SizedBox(height: 14),
                _VersionRow(
                  current: info.currentVersion,
                  latest: info.latestVersion ?? '',
                  accent: resolved.accentColor!,
                  muted: muted,
                  radius: resolved.borderRadius!,
                ),
              ],
              const SizedBox(height: 14),
              Text(
                message,
                style: resolved.bodyTextStyle().copyWith(color: muted),
              ),
              if (resolved.showReleaseNotes &&
                  info.releaseNotes != null &&
                  info.releaseNotes!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: resolved.surfaceColor,
                    borderRadius: resolved.borderRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        releaseNotesTitle ?? 'Nouveautés',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: resolved.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: SingleChildScrollView(
                          child: Text(
                            info.releaseNotes!,
                            style: resolved
                                .bodyTextStyle()
                                .copyWith(color: muted, fontSize: 12.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (resolved.showSize && info.formattedUpdateSize != null) ...[
                const SizedBox(height: 10),
                Text(
                  info.formattedUpdateSize!,
                  style: TextStyle(color: muted, fontSize: 11.5),
                ),
              ],
              if (onSkipVersion != null || onDoNotAskAgain != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: [
                    if (onSkipVersion != null)
                      TextButton(
                        onPressed: actions.onSkipVersion,
                        child: Text(
                          skipVersionText ?? 'Ignorer cette version',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                    if (onDoNotAskAgain != null)
                      TextButton(
                        onPressed: actions.onDoNotAskAgain,
                        child: Text(
                          doNotAskAgainText ?? 'Ne plus demander',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  if (!isPersistent)
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          actions.onLater();
                        },
                        child: Text(
                          laterText,
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                      ),
                    ),
                  Expanded(
                    flex: isPersistent ? 1 : 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: resolved.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: resolved.borderRadius!,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        actions.onUpdate();
                      },
                      child: Text(
                        updateText,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(AppUpdaterTheme resolved) {
    final child = resolved.logo ??
        Icon(
          resolved.icon ?? Icons.system_update_alt_rounded,
          color: resolved.accentColor,
          size: 26,
        );
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: resolved.accentColor!.withValues(alpha: 0.14),
        borderRadius: resolved.borderRadius,
      ),
      child: child,
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.current,
    required this.latest,
    required this.accent,
    required this.muted,
    required this.radius,
  });

  final String current;
  final String latest;
  final Color accent;
  final Color muted;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _pill(current, muted, radius),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward_rounded, size: 14, color: muted),
        ),
        _pill(latest, accent, radius, filled: true),
      ],
    );
  }

  Widget _pill(String text, Color color, BorderRadius radius,
      {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.16) : Colors.transparent,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
        borderRadius: radius,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
