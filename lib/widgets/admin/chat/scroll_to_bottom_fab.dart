import 'package:flutter/material.dart';
import '../../../config/admin_theme.dart';
import '../../../config/brand_colors.dart';

class ScrollToBottomFab extends StatelessWidget {
  final VoidCallback onTap;

  const ScrollToBottomFab({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 12,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AdminColors.card(context),
            shape: BoxShape.circle,
            boxShadow: Theme.of(context).brightness == Brightness.dark ? null : [
              BoxShadow(
                color: Brand.royalBlue.withAlpha(25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(color: AdminColors.border(context)),
          ),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 22,
            color: AdminColors.primary,
          ),
        ),
      ),
    );
  }
}
