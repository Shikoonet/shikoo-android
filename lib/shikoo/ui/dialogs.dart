import 'dart:async';

import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr/qr.dart';
import 'package:url_launcher/url_launcher.dart';

/// `.scrim` and `.dialog`: a card over the dimmed screen; Back closes it.
Future<T?> showShikooDialog<T>(
  BuildContext context, {
  required List<Widget> children,
  bool centered = false,
}) {
  final t = ShikooTheme.of(context);
  return showDialog<T>(
    context: context,
    barrierColor: t.c.scrim,
    builder: (context) => Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.s6),
        child: SizedBox(
          width: t.s.dialog,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: t.c.surface,
              shadows: t.c.raisedShadow,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              // Large text or a long help line must not push the close button off a 540dp TV.
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.s6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: centered
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.stretch,
                  spacing: Space.s3,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// On the TV, `.qr-sheet` (frames `tv-renew-qr`, `tv-support-qr`): the phone scans what the TV
/// cannot open. A phone opens the link in Telegram at once. [strong], all of [below] unless
/// given, is bold.
void openLink(
  BuildContext context, {
  required bool isTV,
  required String link,
  required String title,
  required String help,
  String? below,
  String? strong,
}) {
  if (!isTV) {
    unawaited(launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication));
    return;
  }
  final t = ShikooTheme.of(context);
  final paragraph = t.text(
    t.s.dialogText,
    color: t.c.textMuted,
    height: Leading.body,
  );
  unawaited(
    showShikooDialog<void>(
      context,
      centered: true,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: t.text(t.s.title, weight: FontWeight.w700),
        ),
        Text(help, textAlign: TextAlign.center, style: paragraph),
        QrTile(data: link),
        if (below != null)
          Text.rich(
            TextSpan(
              children: [
                for (final (i, part)
                    in below.split(strong ?? below).indexed) ...[
                  if (i > 0)
                    TextSpan(
                      text: strong ?? below,
                      style: TextStyle(
                        color: t.c.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  TextSpan(text: part),
                ],
              ],
            ),
            textAlign: TextAlign.center,
            style: paragraph,
          ),
        Builder(
          builder: (context) => ShikooButton(
            label: ShikooL10n.of(context).close,
            autofocus: true,
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    ),
  );
}

/// `.qr-tile.sm`.
class QrTile extends StatelessWidget {
  const QrTile({super.key, required this.data, this.large = false, this.over});

  /// Null before there is a code: `.qr-tile.is-empty`, with only [over].
  final String? data;
  final bool large;
  final Widget? over;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final over = this.over;
    final data = this.data;
    final side = large ? t.s.qr : ShikooSizes.qrSm;
    final code = data == null
        ? SizedBox.square(dimension: side)
        : CustomPaint(
            size: Size.square(side),
            painter: _QrPainter(
              QrImage(QrCode(payload: QrPayload.fromString(data))),
            ),
          );
    return Container(
      padding: EdgeInsets.all(large ? Space.s8 : Space.s4),
      decoration: ShapeDecoration(
        color: data == null ? t.c.surface : ShikooColors.qrBg,
        shadows: t.c.cardShadow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      child: over == null
          ? code
          : Stack(
              alignment: Alignment.center,
              children: [
                Opacity(opacity: 0.1, child: code),
                over,
              ],
            ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final cell = size.width / count;
    final modules = Path();
    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (image.isDark(row, col)) {
          modules.addRect(Rect.fromLTWH(col * cell, row * cell, cell, cell));
        }
      }
    }
    // Without anti-aliasing, neighbouring modules meet with no hairline between them.
    canvas.drawPath(
      modules,
      Paint()
        ..color = ShikooColors.qrModule
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}
