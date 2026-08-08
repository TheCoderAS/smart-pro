import 'package:flutter/material.dart';

/// Consistent Cancel / Save action row for dialogs and sheets: two
/// equal-width buttons side by side. Save is disabled until [canSave],
/// so every form across the app behaves the same (submit only when the
/// input is valid). Drop it at the bottom of a dialog's `content`
/// column instead of using `actions:`.
class FormActions extends StatelessWidget {
  const FormActions({
    required this.onCancel,
    required this.onSave,
    this.saveLabel = 'Save',
    this.cancelLabel = 'Cancel',
    this.canSave = true,
    this.destructive = false,
    super.key,
  });

  final VoidCallback onCancel;

  /// Called when Save is pressed. When null (or [canSave] is false) the
  /// Save button is disabled.
  final VoidCallback? onSave;
  final String saveLabel;
  final String cancelLabel;
  final bool canSave;

  /// Paints Save in the error colour (for destructive confirmations).
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onCancel,
            child: Text(cancelLabel),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: scheme.error)
                : null,
            onPressed: (canSave && onSave != null) ? onSave : null,
            child: Text(saveLabel),
          ),
        ),
      ],
    );
  }
}
