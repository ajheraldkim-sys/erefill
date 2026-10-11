import 'package:flutter/material.dart';
import 'erefill_header.dart';
import '../constants.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;
  final bool automaticallyImplyLeading;
  final double? toolbarHeight;

  const AppTopBar({
    super.key,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.subtitleWidget,
    this.leading,
    this.actions,
    this.bottom,
    this.centerTitle = false,
    this.automaticallyImplyLeading = true,
    this.toolbarHeight,
  });

  @override
  Size get preferredSize => Size.fromHeight(
    ((subtitle == null && subtitleWidget == null)
            ? AppUi.headerHeight
            : AppUi.headerHeightWithSubtitle) +
        (bottom?.preferredSize.height ?? 0.0),
  );

  @override
  Widget build(BuildContext context) {
    return ERefillHeader(
      title: title,
      titleWidget: titleWidget,
      subtitle: subtitle,
      subtitleWidget: subtitleWidget,
      leading: leading,
      actions: actions,
      bottom: bottom,
      centerTitle: centerTitle,
      automaticallyImplyLeading: automaticallyImplyLeading,
    );
  }
}

class AppHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottom;
  final EdgeInsetsGeometry padding;
  final bool addTopInset;

  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.padding = AppUi.headerPadding,
    this.addTopInset = false,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = addTopInset ? MediaQuery.of(context).padding.top : 0.0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        border: Border(bottom: BorderSide(color: AppUi.borderOf(context))),
      ),
      child: Padding(
        padding: padding.add(EdgeInsets.only(top: topInset)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (leading != null) ...[leading!, AppUi.hGapMd],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppUi.headerTitleStyle.copyWith(
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(subtitle!, style: AppUi.headerSubtitleStyle),
                      ],
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
            if (bottom != null) ...[AppUi.vGapMd, bottom!],
          ],
        ),
      ),
    );
  }
}
