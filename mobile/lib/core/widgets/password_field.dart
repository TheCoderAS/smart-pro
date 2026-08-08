import 'package:flutter/material.dart';

/// A password [TextField] with a built-in show/hide toggle. Starts
/// obscured; the eye icon reveals the text. Keeps the reveal state local
/// so callers just supply the controller and decoration bits.
class PasswordField extends StatefulWidget {
  const PasswordField({
    required this.controller,
    this.label,
    this.helper,
    this.helperMaxLines,
    this.errorText,
    this.textInputAction,
    this.autofocus = false,
    this.enabled = true,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String? label;
  final String? helper;
  final int? helperMaxLines;
  final String? errorText;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        helperMaxLines: widget.helperMaxLines,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
          tooltip: _hidden ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}
