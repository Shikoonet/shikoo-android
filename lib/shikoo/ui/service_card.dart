import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/jalali.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

const _gib = 1024 * 1024 * 1024;

/// `.card.svc` with its servers, as in `tv.html`: name and status, volume and validity, the
/// panel's announcement, renew and support, then the server list.
class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    required this.state,
    required this.controller,
    this.selectedRowFocus,
  });

  final ShikooState state;
  final ShikooController controller;
  final FocusNode? selectedRowFocus;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final service = state.service;
    const inset = EdgeInsets.symmetric(horizontal: Space.s4);
    return Container(
      padding: const EdgeInsets.only(top: Space.s4, bottom: Space.s2),
      decoration: ShapeDecoration(
        color: t.c.surface,
        shadows: t.c.cardShadow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: service == null
            ? [
                Padding(
                  padding: inset.copyWith(bottom: Space.s2),
                  child: Text(
                    l.noService,
                    style: t.text(t.s.body, color: t.c.textMuted),
                  ),
                ),
              ]
            : [
                Padding(
                  padding: inset,
                  child: _Head(service: service),
                ),
                Padding(
                  padding: inset,
                  child: _Usage(service: service),
                ),
                if (service.announce != null)
                  Padding(
                    padding: inset,
                    child: _Notice(text: service.announce!),
                  ),
                Padding(
                  padding: inset.copyWith(top: Space.s3, bottom: Space.s2),
                  child: Row(
                    children: [
                      // The QR screens behind these two come in the next round.
                      Expanded(
                        child: ShikooButton(
                          label: l.renew,
                          icon: ShikooIcon.qr,
                          primary: true,
                          onPressed: () {},
                        ),
                      ),
                      const SizedBox(width: Space.s2),
                      Expanded(
                        child: ShikooButton(
                          label: l.support,
                          icon: ShikooIcon.qr,
                          onPressed: () {},
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.s2,
                    Space.s2,
                    Space.s2,
                    0,
                  ),
                  child: _Servers(
                    state: state,
                    controller: controller,
                    selectedRowFocus: selectedRowFocus,
                  ),
                ),
              ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.service});

  final ShikooService service;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: nameText(
            context,
            service.name,
            t.text(t.s.title, weight: FontWeight.w700, height: Leading.snug),
          ),
        ),
        const SizedBox(width: Space.s2),
        StatusChip(status: service.statusAt(DateTime.now())),
      ],
    );
  }
}

class _Usage extends StatelessWidget {
  const _Usage({required this.service});

  final ShikooService service;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final muted = t.text(t.s.bodySm, color: t.c.textMuted);
    final strong = TextStyle(color: t.c.text, fontWeight: FontWeight.w700);
    String gb(int bytes) => localNumber(context, bytes / _gib, '#,##0.#');
    final total = service.totalBytes;
    final used = service.usedBytes;
    final ratio = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final expire = service.expire;
    Widget row(List<Widget> children) => Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: Space.s1,
      children: children,
    );
    return Padding(
      padding: const EdgeInsets.only(top: Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row([
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${l.usedLabel} '),
                  TextSpan(text: gb(used), style: strong),
                  if (total > 0) TextSpan(text: ' ${l.ofTotalGb(gb(total))}'),
                ],
              ),
              style: muted,
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${l.remainingLabel} '),
                  TextSpan(
                    text: total > 0
                        ? l.gb(gb(math.max(total - used, 0)))
                        : l.unlimited,
                    style: strong,
                  ),
                ],
              ),
              style: muted,
            ),
          ]),
          if (total > 0) ...[
            const SizedBox(height: Space.s2),
            _Bar(ratio: ratio),
          ],
          if (expire != null) ...[
            const SizedBox(height: Space.s2),
            row([
              Text(l.validUntil(_date(context, l, expire)), style: muted),
              Text(
                l.daysLeft(
                  math.max(
                    0,
                    (expire.difference(DateTime.now()).inHours / 24).ceil(),
                  ),
                ),
                style: muted,
              ),
            ]),
          ],
        ],
      ),
    );
  }

  static String _date(BuildContext context, ShikooL10n l, DateTime date) {
    final j = toJalali(date);
    return l.jalaliDate(
      localNumber(context, j.day),
      l.jalaliMonths.split('|')[j.month - 1],
      localNumber(context, j.year),
    );
  }
}

/// `.bar`: fills from the start edge; amber from 90%, red when used up.
class _Bar extends StatelessWidget {
  const _Bar({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final fill = ratio >= 1
        ? t.c.danger
        : (ratio >= 0.9 ? t.c.warning : t.c.primary);
    return Container(
      height: t.s.bar,
      decoration: ShapeDecoration(
        color: t.c.surfaceSunken,
        shape: const StadiumBorder(),
      ),
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: ratio,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: fill,
            shape: const StadiumBorder(),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// `.notice`: the panel's announcement, on one line.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: Space.s3),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s3,
        vertical: Space.s2,
      ),
      decoration: ShapeDecoration(
        color: t.c.surfaceSunken,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
      ),
      child: Row(
        children: [
          SvgIcon(ShikooIcon.bell, size: t.s.iconSm, color: t.c.textMuted),
          const SizedBox(width: Space.s2),
          Expanded(
            child: nameText(
              context,
              text,
              t.text(t.s.bodySm, height: Leading.snug),
            ),
          ),
        ],
      ),
    );
  }
}

class _Servers extends StatelessWidget {
  const _Servers({
    required this.state,
    required this.controller,
    required this.selectedRowFocus,
  });

  final ShikooState state;
  final ShikooController controller;
  final FocusNode? selectedRowFocus;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    if (state.servers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Space.s2),
        child: Text(
          l.loadingServers,
          style: t.text(t.s.bodySm, color: t.c.textMuted),
        ),
      );
    }
    return Column(
      children: [
        for (final server in state.servers)
          ServerRow(
            server: server,
            selected: server.name == state.selected,
            focusNode: server.name == state.selected ? selectedRowFocus : null,
            onPressed: () => unawaited(controller.selectServer(server.name)),
          ),
      ],
    );
  }
}
