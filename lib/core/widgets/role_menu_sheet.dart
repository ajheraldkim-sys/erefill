import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants.dart';
import '../routing/app_navigation.dart';
import '../providers/theme_provider.dart';

import 'package:erefill/core/utils/friendly_errors.dart';
class RoleMenuAction {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const RoleMenuAction({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
}

void showRoleMenuSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? avatarUrl,
  required List<RoleMenuAction> actions,
}) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.85;
      return SafeArea(
        top: true,
        left: true,
        right: true,
        bottom: true,
        maintainBottomViewPadding: true,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 560),
            child: Material(
              color: AppUi.surfaceOf(sheetContext),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppUi.radiusPill),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 38,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppUi.textMuted.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(AppUi.radiusFull),
                        ),
                      ),
                      Row(
                        children: [
                          if (avatarUrl != null && avatarUrl.isNotEmpty) ...[
                            CircleAvatar(
                              radius: 23,
                              backgroundColor: AppUi.bluePrimary.withValues(
                                alpha: 0.12,
                              ),
                              backgroundImage: NetworkImage(avatarUrl),
                            ),
                            const SizedBox(width: 12),
                          ] else ...[
                            CircleAvatar(
                              radius: 23,
                              backgroundColor: AppUi.bluePrimary.withValues(
                                alpha: 0.12,
                              ),
                              child: Icon(
                                Icons.person_rounded,
                                color: AppUi.brandOf(context),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppUi.textPrimaryOf(sheetContext),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (subtitle != null && subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppUi.textSecondaryOf(
                                        sheetContext,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close menu',
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      for (final action in actions)
                        ListTile(
                          leading: Icon(action.icon),
                          title: Text(action.title),
                          subtitle: action.subtitle == null
                              ? null
                              : Text(action.subtitle!),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            action.onTap();
                          },
                        ),
                      Consumer<ThemeProvider>(
                        builder: (context, themeProvider, _) =>
                            SwitchListTile.adaptive(
                              secondary:
                                  const Icon(Icons.dark_mode_outlined),
                              title: const Text('Dark mode'),
                              value: themeProvider.isDarkMode,
                              onChanged: themeProvider.setDarkMode,
                            ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.logout_rounded,
                          color: AppUi.error,
                        ),
                        title: const Text(
                          'Sign out',
                          style: TextStyle(color: AppUi.error),
                        ),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _confirmSignOut(context);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<void> _confirmSignOut(BuildContext context) async {
  final shouldSignOut = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text('You can sign back in anytime.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (shouldSignOut != true || !context.mounted) return;

  try {
    await Supabase.instance.client.auth.signOut();
    if (context.mounted) context.resetToAuth();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not sign out: ${FriendlyErrors.message(error)}')));
  }
}
