import 'package:flutter/cupertino.dart';

/// Simplified styling utilities for the dictation module.
/// Provides theme-aware colors and text styles.
class DictationStyles {
  // --- Colors (Context-dependent) ---
  static Color secondaryTextColor(BuildContext context) =>
      CupertinoColors.secondaryLabel.resolveFrom(context);

  static Color primaryTextColor(BuildContext context) =>
      CupertinoTheme.of(context).textTheme.textStyle.color ??
      CupertinoColors.label.resolveFrom(context);

  // --- Text Styles ---
  static TextStyle inputTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: 16.0,
      fontWeight: FontWeight.w400,
      color: primaryTextColor(context),
    );
  }
}

