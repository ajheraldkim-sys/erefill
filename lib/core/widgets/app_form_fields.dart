import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:erefill/core/constants.dart';

/// Reusable decoration factory providing the signature eRefill sign-up form
/// layout, borders, floating labels, and typography across all application forms.
class AppFormDecoration {
  AppFormDecoration._();

  static InputDecoration inputDecoration(
    BuildContext context, {
    required String label,
    String? hint,
    String? hintText,
    dynamic prefixIcon,
    Widget? prefixWidget,
    IconData? icon,
    Widget? suffixIcon,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    bool compact = false,
    bool alignLabelWithHint = false,
  }) {
    final mutedTextColor = AppUi.textSecondaryOf(context);
    final border = OutlineInputBorder(
      borderRadius: AppUi.cardRadius,
      borderSide: BorderSide(color: AppUi.borderOf(context)),
    );

    final focusedBorder = OutlineInputBorder(
      borderRadius: AppUi.cardRadius,
      borderSide: BorderSide(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppUi.accentCyan
            : AppUi.bluePrimary,
        width: 2,
      ),
    );

    final errorBorder = OutlineInputBorder(
      borderRadius: AppUi.cardRadius,
      borderSide: const BorderSide(color: AppUi.error),
    );

    final focusedErrorBorder = OutlineInputBorder(
      borderRadius: AppUi.cardRadius,
      borderSide: const BorderSide(color: AppUi.error, width: 2),
    );

    Widget? leading;
    if (prefixWidget != null) {
      leading = prefixWidget;
    } else if (prefixIcon is Widget) {
      leading = prefixIcon;
    } else if (prefixIcon is IconData) {
      leading = Icon(prefixIcon, size: 20, color: mutedTextColor);
    } else if (icon != null) {
      leading = Icon(icon, size: 20, color: mutedTextColor);
    }

    Widget? trailing = suffixIcon;
    if (trailing == null && isPassword && onToggleObscure != null) {
      trailing = IconButton(
        onPressed: onToggleObscure,
        icon: Icon(
          obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          size: 20,
          color: mutedTextColor,
        ),
        tooltip: obscure ? 'Show password' : 'Hide password',
      );
    }

    final effectiveHint = hint ?? hintText;

    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      hintText: effectiveHint,
      alignLabelWithHint: alignLabelWithHint,
      labelStyle: TextStyle(
        color: mutedTextColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      floatingLabelStyle: const TextStyle(
        color: AppUi.bluePrimary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      hintStyle: TextStyle(
        color: mutedTextColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: leading,
      suffixIcon: trailing,
      filled: true,
      fillColor: AppUi.surfaceOf(context),
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 20,
        vertical: compact ? 15 : 18,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: focusedBorder,
      errorBorder: errorBorder,
      focusedErrorBorder: focusedErrorBorder,
    );
  }
}

/// Standard text input field matching the sign-up form design.
class AppFormField extends StatefulWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? hintText;
  final IconData? icon;
  final dynamic prefixIcon;
  final Widget? prefixWidget;
  final Widget? suffixIcon;
  final bool isPassword;
  final bool? obscureText;
  final VoidCallback? onToggleObscure;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final bool readOnly;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool compact;
  final String? initialValue;
  final FocusNode? focusNode;

  const AppFormField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.hintText,
    this.icon,
    this.prefixIcon,
    this.prefixWidget,
    this.suffixIcon,
    this.isPassword = false,
    this.obscureText,
    this.onToggleObscure,
    this.validator,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.readOnly = false,
    this.enabled = true,
    this.onChanged,
    this.onFieldSubmitted,
    this.textInputAction,
    this.inputFormatters,
    this.compact = false,
    this.initialValue,
    this.focusNode,
  });

  @override
  State<AppFormField> createState() => _AppFormFieldState();
}

class _AppFormFieldState extends State<AppFormField> {
  late bool _obscure;

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscureText ?? widget.isPassword;
  }

  @override
  void didUpdateWidget(covariant AppFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.obscureText != null &&
        widget.obscureText != oldWidget.obscureText) {
      _obscure = widget.obscureText!;
    }
  }

  void _toggleObscure() {
    if (widget.onToggleObscure != null) {
      widget.onToggleObscure!();
    } else {
      setState(() => _obscure = !_obscure);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller != null &&
        !widget.isPassword &&
        widget.suffixIcon == null &&
        widget.validator != null) {
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller!,
        builder: (context, value, _) {
          final text = value.text;
          final isValid = text.isNotEmpty && widget.validator!(text) == null;
          Widget? validationSuffix;
          if (isValid) {
            validationSuffix = const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Icon(
                Icons.check_circle_rounded,
                color: AppUi.accentGreen,
                size: 20,
              ),
            );
          }

          return _buildTextFormField(context, validationSuffix);
        },
      );
    }
    return _buildTextFormField(context, widget.suffixIcon);
  }

  Widget _buildTextFormField(BuildContext context, Widget? effectiveSuffixIcon) {
    return TextFormField(
      controller: widget.controller,
      initialValue: widget.initialValue,
      focusNode: widget.focusNode,
      obscureText: widget.isPassword ? _obscure : false,
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization,
      maxLines: widget.isPassword ? 1 : widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      readOnly: widget.readOnly,
      enabled: widget.enabled,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: widget.enabled ? AppUi.textPrimaryOf(context) : AppUi.textMuted,
      ),
      decoration: AppFormDecoration.inputDecoration(
        context,
        label: widget.label,
        hint: widget.hint,
        hintText: widget.hintText,
        icon: widget.icon,
        prefixIcon: widget.prefixIcon,
        prefixWidget: widget.prefixWidget,
        suffixIcon: effectiveSuffixIcon,
        isPassword: widget.isPassword,
        obscure: _obscure,
        onToggleObscure: _toggleObscure,
        compact: widget.compact,
        alignLabelWithHint: widget.maxLines > 1,
      ),
    );
  }
}

/// Standard dropdown field matching the sign-up form design.
class AppDropdownField<T> extends StatelessWidget {
  final String label;
  final String? hint;
  final String? hintText;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final IconData? icon;
  final dynamic prefixIcon;
  final Widget? prefixWidget;
  final bool compact;

  const AppDropdownField({
    super.key,
    required this.label,
    required this.items,
    this.value,
    this.onChanged,
    this.validator,
    this.hint,
    this.hintText,
    this.icon,
    this.prefixIcon,
    this.prefixWidget,
    this.compact = false,
  });

  /// Factory helper for simple string items
  factory AppDropdownField.fromStrings({
    Key? key,
    required String label,
    required List<String> items,
    String? value,
    ValueChanged<String?>? onChanged,
    String? Function(String?)? validator,
    String? hint,
    String? hintText,
    IconData? icon,
    dynamic prefixIcon,
    Widget? prefixWidget,
    bool compact = false,
  }) {
    return AppDropdownField<T>(
      key: key,
      label: label,
      hint: hint,
      hintText: hintText,
      value: value as T?,
      items: items
          .map(
            (item) => DropdownMenuItem<T>(
              value: item as T,
              child: Text(
                item,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged == null
          ? null
          : (value) => onChanged(value as String?),
      validator: validator == null
          ? null
          : (value) => validator(value as String?),
      icon: icon,
      prefixIcon: prefixIcon,
      prefixWidget: prefixWidget,
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMatchingItem =
        value != null && items.any((item) => item.value == value);
    final effectiveValue = hasMatchingItem ? value : null;

    return DropdownButtonFormField<T>(
      initialValue: effectiveValue,
      items: items,
      onChanged: onChanged,
      validator: validator,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: AppUi.textPrimaryOf(context),
      ),
      decoration: AppFormDecoration.inputDecoration(
        context,
        label: label,
        hint: hint,
        hintText: hintText,
        icon: icon,
        prefixIcon: prefixIcon,
        prefixWidget: prefixWidget,
        compact: compact,
      ),
    );
  }
}

/// Section header matching the sign-up form design.
class AppFormSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double topPadding;
  final double bottomPadding;

  const AppFormSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.topPadding = 16,
    this.bottomPadding = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: AppUi.textSecondaryOf(context),
              letterSpacing: 0.6,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13,
                color: AppUi.textSecondaryOf(context),
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Prominent primary action button matching the sign-up button design.
class AppFormSubmitButton extends StatelessWidget {
  final String? label;
  final String? text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double height;

  const AppFormSubmitButton({
    super.key,
    this.label,
    this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.height = 56,
  }) : assert(
         label != null || text != null,
         'Either label or text must be provided',
       );

  String get effectiveLabel => label ?? text ?? '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ?? (isDark ? AppUi.accentCyan : AppUi.bluePrimary);
    final fg = foregroundColor ?? (isDark ? AppUi.darkPageBg : Colors.white);

    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUi.radiusControl),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    effectiveLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: fg,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
