import 'package:flutter/material.dart';

import '../../../theme/hardwood_command_theme.dart';

/// House pressable control replacing Material ink ripples with subtle scale/focus.
class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.onPressed,
    this.enabled = true,
    this.semanticLabel,
    this.borderRadius,
    this.minWidth,
    this.minHeight,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool enabled;
  final String? semanticLabel;
  final BorderRadius? borderRadius;
  final double? minWidth;
  final double? minHeight;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final interactive = widget.enabled && widget.onPressed != null;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 90);
    final pressed = _pressed && interactive;
    final radius = widget.borderRadius ?? BorderRadius.circular(t.radiusMd);

    Widget content = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      transformAlignment: Alignment.center,
      transform: Matrix4.diagonal3Values(
        pressed ? 0.975 : 1.0,
        pressed ? 0.975 : 1.0,
        1.0,
      ),
      decoration: _focused
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: t.accentSecondary, width: 2),
            )
          : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minWidth ?? t.touchMin,
          minHeight: widget.minHeight ?? t.touchMin,
        ),
        child: Opacity(opacity: interactive ? 1.0 : 0.5, child: widget.child),
      ),
    );

    if (widget.semanticLabel != null) {
      content = Semantics(
        button: true,
        enabled: interactive,
        label: widget.semanticLabel,
        child: content,
      );
    }

    return FocusableActionDetector(
      enabled: interactive,
      onShowFocusHighlight: (focused) {
        if (mounted) setState(() => _focused = focused);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            if (interactive) widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: interactive ? (_) => setState(() => _pressed = true) : null,
        onTapUp: interactive ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: interactive
            ? () => setState(() => _pressed = false)
            : null,
        onTap: interactive ? widget.onPressed : null,
        child: content,
      ),
    );
  }
}

/// Original procedural geometric franchise shield crest.
class FranchiseCrestBadge extends StatelessWidget {
  const FranchiseCrestBadge({
    super.key,
    required this.abbreviation,
    this.size = 38,
    this.primaryColor,
    this.accentColor,
  });

  final String abbreviation;
  final double size;
  final Color? primaryColor;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fill = primaryColor ?? t.teamPrimary;
    final border = accentColor ?? t.teamSecondary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ShieldCrestPainter(
          fillColor: fill,
          borderColor: border,
          goldAccent: t.accentPrimary,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              abbreviation,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: size * 0.27,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShieldCrestPainter extends CustomPainter {
  const _ShieldCrestPainter({
    required this.fillColor,
    required this.borderColor,
    required this.goldAccent,
  });

  final Color fillColor;
  final Color borderColor;
  final Color goldAccent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, h * 0.06)
      ..lineTo(w * 0.9, h * 0.22)
      ..lineTo(w * 0.9, h * 0.5)
      ..quadraticBezierTo(w * 0.88, h * 0.8, w * 0.5, h * 0.94)
      ..quadraticBezierTo(w * 0.12, h * 0.8, w * 0.1, h * 0.5)
      ..lineTo(w * 0.1, h * 0.22)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = fillColor.withValues(alpha: 0.38)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      Offset(w * 0.26, h * 0.24),
      Offset(w * 0.74, h * 0.24),
      Paint()
        ..color = goldAccent
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ShieldCrestPainter oldDelegate) =>
      oldDelegate.fillColor != fillColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.goldAccent != goldAccent;
}

/// Subtle geometric court-key & arc watermark for basketball identity.
class CourtWatermarkPainter extends CustomPainter {
  const CourtWatermarkPainter({required this.lineColor});

  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    canvas.drawRect(Rect.fromLTWH(w * 0.3, h * 0.05, w * 0.4, h * 0.9), paint);
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), h * 0.24, paint);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.05),
        width: w * 0.75,
        height: h * 1.5,
      ),
      0.15,
      2.84,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CourtWatermarkPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor;
}

/// Primary Hardwood Gold progression CTA button (>= 50dp height).
class HardwoodPrimaryCta extends StatelessWidget {
  const HardwoodPrimaryCta({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isBusy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppPressable(
      onPressed: isBusy ? null : onPressed,
      enabled: onPressed != null && !isBusy,
      semanticLabel: label,
      minHeight: 50,
      borderRadius: BorderRadius.circular(t.radiusMd),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 50),
        padding: EdgeInsets.symmetric(
          horizontal: t.space400,
          vertical: t.space300,
        ),
        decoration: BoxDecoration(
          color: t.accentPrimary,
          borderRadius: BorderRadius.circular(t.radiusMd),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isBusy) ...[
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: t.accentPrimaryFg,
                ),
              ),
              SizedBox(width: t.space200),
            ] else if (icon != null) ...[
              Icon(icon, size: 18, color: t.accentPrimaryFg),
              SizedBox(width: t.space200),
            ],
            Flexible(
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.accentPrimaryFg,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact original player monogram badge derived strictly from actual name initials.
class PlayerMonogramBadge extends StatelessWidget {
  const PlayerMonogramBadge({
    super.key,
    required this.fullName,
    this.size = 34,
  });

  final String fullName;
  final double size;

  String get _initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'PL';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.teamPrimary.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(t.radiusSm),
        border: Border.all(
          color: t.teamSecondary.withValues(alpha: 0.65),
          width: 1.2,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          _initials,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// Consistent D02 rating badge with color + non-color tier symbol distinctions.
class OverallRatingBadge extends StatelessWidget {
  const OverallRatingBadge({
    super.key,
    required this.overall,
    this.subLabel = 'OVR',
    this.compact = false,
  });

  final int overall;
  final String subLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (Color fg, Color border, String tierGlyph) = overall >= 75
        ? (t.accentPrimary, t.borderActive, '★')
        : overall >= 65
        ? (t.accentSecondaryFg, t.accentSecondary, '▲')
        : overall >= 55
        ? (t.textPrimary, t.borderSubtle, '')
        : (t.textSecondary, t.borderSubtle, '');

    return Container(
      constraints: BoxConstraints(
        minWidth: compact ? 44 : 50,
        minHeight: compact ? 42 : 50,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        borderRadius: BorderRadius.circular(t.radiusMd),
        border: Border.all(color: border, width: overall >= 65 ? 1.5 : 1.0),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$tierGlyph$overall',
              style: TextStyle(
                color: fg,
                fontSize: compact ? 14.5 : 17.5,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            Text(
              subLabel,
              style: TextStyle(
                color: t.textMuted,
                fontSize: compact ? 9.5 : 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Secondary inspection button (>= 48dp height).
class HardwoodSecondaryButton extends StatelessWidget {
  const HardwoodSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppPressable(
      onPressed: onPressed,
      enabled: onPressed != null,
      semanticLabel: label,
      minHeight: t.touchMin,
      borderRadius: BorderRadius.circular(t.radiusMd),
      child: Container(
        constraints: BoxConstraints(minHeight: t.touchMin),
        padding: EdgeInsets.symmetric(
          horizontal: t.space300,
          vertical: t.space200,
        ),
        decoration: BoxDecoration(
          color: t.bgElevated,
          borderRadius: BorderRadius.circular(t.radiusMd),
          border: Border.all(color: t.borderSubtle),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: t.accentSecondary),
              SizedBox(width: t.space100),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.accentSecondaryFg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
