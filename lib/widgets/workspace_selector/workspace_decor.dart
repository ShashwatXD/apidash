import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

class WorkspaceMorphTransition extends StatelessWidget {
  const WorkspaceMorphTransition({
    super.key,
    required this.transitionKey,
    required this.child,
  });

  final Object transitionKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          );
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(transitionKey),
          child: child,
        ),
      ),
    );
  }
}

class WorkspaceActionCard extends StatelessWidget {
  const WorkspaceActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.enabled = true,
    this.isPrimary = false,
    this.filledIcon = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool enabled;
  final bool isPrimary;
  final bool filledIcon;

  static final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 20,
          fill: filledIcon ? 1.0 : 0.0,
        ),
        kHSpacer12,
        Text(
          title,
          style: kTextStyleLarge.copyWith(
            fontWeight: FontWeight.w600,
            color: isPrimary ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ],
    );

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        label,
        Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: isPrimary ? scheme.onPrimary : scheme.outline,
        ),
      ],
    );

    if (isPrimary) {
      return FilledButton(
        onPressed: enabled ? onTap : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimary,
          shape: _buttonShape,
        ),
        child: content,
      );
    }

    return OutlinedButton(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        foregroundColor: scheme.onSurface,
        backgroundColor: scheme.surfaceContainerLowest,
        side: BorderSide(color: scheme.outlineVariant),
        shape: _buttonShape,
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return scheme.primary.withValues(alpha: 0.04);
          }
          return null;
        }),
      ),
      child: content,
    );
  }
}

class WorkspaceFlowHeader extends StatelessWidget {
  const WorkspaceFlowHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.headlineLarge),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: kTextStyleMedium.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
