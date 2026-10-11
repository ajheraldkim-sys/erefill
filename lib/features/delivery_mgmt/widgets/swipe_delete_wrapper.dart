import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';

class SwipeDeleteWrapper extends StatelessWidget {
  final Widget child;
  final VoidCallback onDeleted;
  final String undoLabel;

  const SwipeDeleteWrapper({
    super.key,
    required this.child,
    required this.onDeleted,
    this.undoLabel = 'Undo',
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: UniqueKey(),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: AppUi.radiusLg,
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_rounded, color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async => true,
      onDismissed: (_) => onDeleted(),
      child: child,
    );
  }
}
