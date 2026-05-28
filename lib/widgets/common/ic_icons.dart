// lib/widgets/common/ic_icons.dart
// Custom icon painters — filled lineal color style
// Gear (settings), TwinGear (machines), Ticket stub, Headset

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════
//  GEAR ICON  (Settings)
// ══════════════════════════════════════════════════════════════
class IcGearIcon extends StatelessWidget {
  final Color color;
  final double size;
  const IcGearIcon({super.key, required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _GearPainter(color: color)),
      );
}

class _GearPainter extends CustomPainter {
  final Color color;
  const _GearPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final outerR = size.width * 0.44;
    final innerR = size.width * 0.29;
    final holeR = size.width * 0.13;
    const teeth = 8;
    const step = 2 * math.pi / teeth;

    final path = Path();
    for (int i = 0; i < teeth; i++) {
      final a1 = step * i - math.pi / 2;
      final a2 = a1 + step * 0.40;
      final a3 = a2 + step * 0.20;
      final a4 = a3 + step * 0.40;

      if (i == 0) {
        path.moveTo(cx + outerR * math.cos(a1), cy + outerR * math.sin(a1));
      } else {
        path.lineTo(cx + outerR * math.cos(a1), cy + outerR * math.sin(a1));
      }
      path
        ..lineTo(cx + outerR * math.cos(a2), cy + outerR * math.sin(a2))
        ..lineTo(cx + innerR * math.cos(a3), cy + innerR * math.sin(a3))
        ..lineTo(cx + innerR * math.cos(a4), cy + innerR * math.sin(a4));
    }
    path.close();

    final hole = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: holeR));

    canvas.drawPath(
      Path.combine(PathOperation.difference, path, hole),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    // Accent centre dot
    canvas.drawCircle(
      Offset(cx, cy),
      holeR * 0.4,
      Paint()
        ..color = color.withAlpha(160)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_GearPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════
//  TWIN GEAR ICON  (Machines)
// ══════════════════════════════════════════════════════════════
class IcTwinGearIcon extends StatelessWidget {
  final Color primaryColor;
  final Color secondaryColor;
  final double size;
  const IcTwinGearIcon({
    super.key,
    required this.primaryColor,
    required this.secondaryColor,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
            painter: _TwinGearPainter(
                primary: primaryColor, secondary: secondaryColor)),
      );
}

class _TwinGearPainter extends CustomPainter {
  final Color primary;
  final Color secondary;
  const _TwinGearPainter({required this.primary, required this.secondary});

  Path _gear(double cx, double cy, double outerR, double innerR, double holeR,
      int teeth) {
    const pi2 = 2 * math.pi;
    final step = pi2 / teeth;
    final path = Path();
    for (int i = 0; i < teeth; i++) {
      final a1 = step * i - math.pi / 2;
      final a2 = a1 + step * 0.38;
      final a3 = a2 + step * 0.24;
      final a4 = a3 + step * 0.38;
      if (i == 0) {
        path.moveTo(cx + outerR * math.cos(a1), cy + outerR * math.sin(a1));
      } else {
        path.lineTo(cx + outerR * math.cos(a1), cy + outerR * math.sin(a1));
      }
      path
        ..lineTo(cx + outerR * math.cos(a2), cy + outerR * math.sin(a2))
        ..lineTo(cx + innerR * math.cos(a3), cy + innerR * math.sin(a3))
        ..lineTo(cx + innerR * math.cos(a4), cy + innerR * math.sin(a4));
    }
    path.close();
    final hole = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: holeR));
    return Path.combine(PathOperation.difference, path, hole);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Large gear (bottom-left)
    canvas.drawPath(
      _gear(w * 0.36, h * 0.58, w * 0.33, w * 0.21, w * 0.10, 7),
      Paint()
        ..color = primary
        ..style = PaintingStyle.fill,
    );
    // Small gear (top-right)
    canvas.drawPath(
      _gear(w * 0.66, h * 0.36, w * 0.24, w * 0.15, w * 0.07, 6),
      Paint()
        ..color = secondary
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_TwinGearPainter old) =>
      old.primary != primary || old.secondary != secondary;
}

// ══════════════════════════════════════════════════════════════
//  TICKET STUB ICON  (Tickets)
// ══════════════════════════════════════════════════════════════
class IcTicketIcon extends StatelessWidget {
  final Color color;
  final double size;
  const IcTicketIcon({super.key, required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _TicketPainter(color: color)),
      );
}

class _TicketPainter extends CustomPainter {
  final Color color;
  const _TicketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rr = w * 0.12;

    // Body
    final body = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.06, h * 0.22, w * 0.88, h * 0.56),
          Radius.circular(rr)));

    // Notch top and bottom at 62% from left
    final nTop = Path()
      ..addOval(Rect.fromCircle(
          center: Offset(w * 0.62, h * 0.22), radius: w * 0.085));
    final nBot = Path()
      ..addOval(Rect.fromCircle(
          center: Offset(w * 0.62, h * 0.78), radius: w * 0.085));

    var stub = Path.combine(PathOperation.difference, body, nTop);
    stub = Path.combine(PathOperation.difference, stub, nBot);

    canvas.drawPath(stub, Paint()..color = color..style = PaintingStyle.fill);

    // Dotted divider
    final dash = Paint()
      ..color = Colors.white.withAlpha(140)
      ..strokeWidth = w * 0.035
      ..style = PaintingStyle.stroke;
    double y = h * 0.30;
    final end = h * 0.70;
    while (y < end) {
      final seg = math.min(y + h * 0.07, end);
      canvas.drawLine(Offset(w * 0.62, y), Offset(w * 0.62, seg), dash);
      y += h * 0.115;
    }

    // Star mark on main area
    final star = Paint()..color = Colors.white.withAlpha(210)..style = PaintingStyle.fill;
    final scx = w * 0.34, scy = h * 0.50, sr = w * 0.13;
    final sp = Path();
    for (int i = 0; i < 8; i++) {
      final a = math.pi / 4 * i - math.pi / 2;
      final r = (i % 2 == 0) ? sr : sr * 0.48;
      final px = scx + r * math.cos(a), py = scy + r * math.sin(a);
      i == 0 ? sp.moveTo(px, py) : sp.lineTo(px, py);
    }
    sp.close();
    canvas.drawPath(sp, star);
  }

  @override
  bool shouldRepaint(_TicketPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════
//  CHAT-GEAR ICON  (Open Tickets / Support)
// ══════════════════════════════════════════════════════════════
class IcChatGearIcon extends StatelessWidget {
  final Color color;
  final double size;
  const IcChatGearIcon({super.key, required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _ChatGearPainter(color: color)),
      );
}

class _ChatGearPainter extends CustomPainter {
  final Color color;
  const _ChatGearPainter({required this.color});

  Path _gearPath(double cx, double cy, double outerR, double innerR,
      double holeR, int teeth) {
    const pi2 = 2 * math.pi;
    final step = pi2 / teeth;
    final path = Path();
    for (int i = 0; i < teeth; i++) {
      final a1 = step * i - math.pi / 2;
      final a2 = a1 + step * 0.38;
      final a3 = a2 + step * 0.24;
      final a4 = a3 + step * 0.38;
      if (i == 0) {
        path.moveTo(cx + outerR * math.cos(a1), cy + outerR * math.sin(a1));
      } else {
        path.lineTo(cx + outerR * math.cos(a1), cy + outerR * math.sin(a1));
      }
      path
        ..lineTo(cx + outerR * math.cos(a2), cy + outerR * math.sin(a2))
        ..lineTo(cx + innerR * math.cos(a3), cy + innerR * math.sin(a3))
        ..lineTo(cx + innerR * math.cos(a4), cy + innerR * math.sin(a4));
    }
    path.close();
    final hole = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: holeR));
    return Path.combine(PathOperation.difference, path, hole);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rr = Radius.circular(w * 0.18);

    // ── Back bubble (smaller, semi-transparent) ──
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.02, h * 0.04, w * 0.56, h * 0.50), rr),
      Paint()..color = color.withAlpha(85)..style = PaintingStyle.fill,
    );

    // ── Front bubble body ──
    final bubblePath = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.24, h * 0.16, w * 0.74, h * 0.60), rr));

    // ── Tail pointing bottom-left ──
    final tail = Path()
      ..moveTo(w * 0.30, h * 0.76)
      ..lineTo(w * 0.14, h * 0.94)
      ..lineTo(w * 0.46, h * 0.76)
      ..close();

    final front = Path.combine(PathOperation.union, bubblePath, tail);
    canvas.drawPath(
        front, Paint()..color = color..style = PaintingStyle.fill);

    // ── Gear centred in front bubble ──
    final gcx = w * 0.61, gcy = h * 0.45;
    final gr = w * 0.165;
    canvas.drawPath(
      _gearPath(gcx, gcy, gr, gr * 0.62, gr * 0.27, 7),
      Paint()
        ..color = Colors.white.withAlpha(225)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_ChatGearPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════
//  HEADSET ICON  (Support)
// ══════════════════════════════════════════════════════════════
class IcHeadsetIcon extends StatelessWidget {
  final Color color;
  final double size;
  const IcHeadsetIcon({super.key, required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _HeadsetPainter(color: color)),
      );
}

class _HeadsetPainter extends CustomPainter {
  final Color color;
  const _HeadsetPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.115
      ..strokeCap = StrokeCap.round;

    // Headband arc
    canvas.drawArc(
      Rect.fromLTWH(w * 0.10, h * 0.08, w * 0.80, h * 0.60),
      math.pi,
      math.pi,
      false,
      paint,
    );

    // Left ear cup
    final fillPaint = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.04, h * 0.42, w * 0.20, h * 0.30),
          Radius.circular(w * 0.08)),
      fillPaint,
    );
    // Right ear cup
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.76, h * 0.42, w * 0.20, h * 0.30),
          Radius.circular(w * 0.08)),
      fillPaint,
    );

    // Mic arm + capsule
    final micPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromLTWH(w * 0.04, h * 0.52, w * 0.34, h * 0.38),
      math.pi * 1.0,
      math.pi * 0.5,
      false,
      micPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.34, h * 0.76, w * 0.18, h * 0.16),
          Radius.circular(w * 0.06)),
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_HeadsetPainter old) => old.color != color;
}
