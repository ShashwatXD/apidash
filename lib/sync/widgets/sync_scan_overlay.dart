import 'package:flutter/material.dart';

class SyncScanOverlay extends StatelessWidget {
  const SyncScanOverlay({
    super.key,
    this.cutoutSize = 260,
    this.borderRadius = 20,
    this.bracketLength = 28,
    this.bracketStroke = 3.5,
  });

  final double cutoutSize;
  final double borderRadius;
  final double bracketLength;
  final double bracketStroke;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final cutoutRect = Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: cutoutSize,
          height: cutoutSize,
        );

        return CustomPaint(
          size: size,
          painter: _SyncScanOverlayPainter(
            cutoutRect: cutoutRect,
            borderRadius: borderRadius,
            bracketLength: bracketLength,
            bracketStroke: bracketStroke,
          ),
        );
      },
    );
  }
}

class _SyncScanOverlayPainter extends CustomPainter {
  _SyncScanOverlayPainter({
    required this.cutoutRect,
    required this.borderRadius,
    required this.bracketLength,
    required this.bracketStroke,
  });

  final Rect cutoutRect;
  final double borderRadius;
  final double bracketLength;
  final double bracketStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(cutoutRect, Radius.circular(borderRadius)),
      )
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    final bracketPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..strokeWidth = bracketStroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final r = borderRadius;
    final left = cutoutRect.left;
    final top = cutoutRect.top;
    final right = cutoutRect.right;
    final bottom = cutoutRect.bottom;
    final bl = bracketLength;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(left, top + bl)
        ..lineTo(left, top + r)
        ..quadraticBezierTo(left, top, left + r, top)
        ..lineTo(left + bl, top),
      bracketPaint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(right - bl, top)
        ..lineTo(right - r, top)
        ..quadraticBezierTo(right, top, right, top + r)
        ..lineTo(right, top + bl),
      bracketPaint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(left, bottom - bl)
        ..lineTo(left, bottom - r)
        ..quadraticBezierTo(left, bottom, left + r, bottom)
        ..lineTo(left + bl, bottom),
      bracketPaint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(right - bl, bottom)
        ..lineTo(right - r, bottom)
        ..quadraticBezierTo(right, bottom, right, bottom - r)
        ..lineTo(right, bottom - bl),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SyncScanOverlayPainter oldDelegate) {
    return cutoutRect != oldDelegate.cutoutRect ||
        borderRadius != oldDelegate.borderRadius ||
        bracketLength != oldDelegate.bracketLength ||
        bracketStroke != oldDelegate.bracketStroke;
  }
}
