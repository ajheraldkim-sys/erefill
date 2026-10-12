import 'package:flutter/material.dart';

import '../../constants.dart';

/// Section label above grouped account rows (iOS Settings style).
class AccountSectionLabel extends StatelessWidget {
  final String label;
  final TextAlign textAlign;
  final AlignmentGeometry? alignment;

  const AccountSectionLabel(
    this.label, {
    super.key,
    this.textAlign = TextAlign.start,
    this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAlignment = alignment ??
        (textAlign == TextAlign.right
            ? Alignment.centerRight
            : textAlign == TextAlign.center
                ? Alignment.center
                : Alignment.centerLeft);

    return Container(
      width: double.infinity,
      alignment: effectiveAlignment,
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        label.toUpperCase(),
        textAlign: textAlign,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: AppUi.textSecondaryOf(context),
        ),
      ),
    );
  }
}

/// Rounded grouped list container.
class AccountGroup extends StatelessWidget {
  final List<Widget> children;

  const AccountGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      tiles.add(children[i]);
      if (i < children.length - 1) {
        tiles.add(
          Divider(height: 1, indent: 52, color: AppUi.dividerOf(context)),
        );
      }
    }

    return Container(
      decoration: AppUi.cardDecorationOf(context),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: tiles),
    );
  }
}

/// Tappable account row with optional subtitle and chevron.
class AccountNavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  const AccountNavTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = iconColor ?? AppUi.bluePrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: titleColor ?? AppUi.textPrimaryOf(context),
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppUi.textSecondaryOf(context),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppUi.textMuted.withValues(alpha: 0.7),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Toggle row inside an account group.
class AccountToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const AccountToggleTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppUi.textSecondaryOf(context)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppUi.textSecondaryOf(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppUi.bluePrimary;
              }
              return null;
            }),
          ),
        ],
      ),
    );
  }
}

/// Top identity block: avatar, name, email, optional stats.
class AccountIdentityBlock extends StatelessWidget {
  final String name;
  final String email;
  final String? avatarUrl;
  final VoidCallback? onAvatarTap;
  final String? statLeftLabel;
  final String? statLeftValue;
  final String? statRightLabel;
  final String? statRightValue;

  const AccountIdentityBlock({
    super.key,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.onAvatarTap,
    this.statLeftLabel,
    this.statLeftValue,
    this.statRightLabel,
    this.statRightValue,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    Widget avatar = CircleAvatar(
      radius: 32,
      backgroundColor: AppUi.blueSoft,
      backgroundImage: hasAvatar
          ? ResizeImage(NetworkImage(avatarUrl!), width: 128, height: 128)
          : null,
      child: hasAvatar
          ? null
          : Text(
              initial,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: AppUi.bluePrimary,
              ),
            ),
    );

    if (onAvatarTap != null) {
      avatar = GestureDetector(
        onTap: onAvatarTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: AppUi.bluePrimary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppUi.cardDecorationOf(context),
      child: Column(
        children: [
          Row(
            children: [
              avatar,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty ? name : 'Customer',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppUi.textSecondaryOf(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (statLeftValue != null && statRightValue != null) ...[
            const SizedBox(height: 20),
            Divider(height: 1, color: AppUi.dividerOf(context)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatCell(
                    label: statLeftLabel ?? '',
                    value: statLeftValue!,
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: AppUi.dividerOf(context),
                ),
                Expanded(
                  child: _StatCell(
                    label: statRightLabel ?? '',
                    value: statRightValue!,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;

  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: AppUi.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppUi.textSecondaryOf(context),
          ),
        ),
      ],
    );
  }
}

/// Slim hint when profile is incomplete.
class AccountCompletenessHint extends StatelessWidget {
  final String message;
  final VoidCallback onTap;

  const AccountCompletenessHint({
    super.key,
    required this.message,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: AppUi.blueSoft,
        borderRadius: AppUi.cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppUi.cardRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppUi.bluePrimary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppUi.bluePrimary,
                      height: 1.35,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppUi.bluePrimary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
