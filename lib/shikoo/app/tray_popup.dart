import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:win32/win32.dart';

/// A row of the menu beside the clock; null in [TrayMenu.rows] is a rule between rows.
typedef TrayRow = ({
  String label,
  ShikooIcon? icon,
  bool dot,
  bool enabled,
  VoidCallback run,
});

/// The status line, green with the time when connected, and the rows under its rule.
typedef TrayMenu = ({
  String head,
  bool on,
  bool muted,
  String? time,
  List<TrayRow?> rows,
});

typedef TrayView = ({
  TrayMenu menu,
  Brightness brightness,
  TextDirection direction,
});

typedef TrayStep = ({int? selected, bool pointed, bool close, TrayRow? chosen});

// win32 6.4 leaves these three out.
const _waInactive = 0;
const _defaultDpi = 96;
const _acSrcAlpha = 1;

/// What one Windows message does to the open menu. [at] is the row under the pointer, -1
/// when the pointer is off the card, null when it is on the card but on no row.
/// [pointed]: the pointer, not a key, chose [selected]; leaving the card drops only that row.
/// A move that is not [moved], as Windows sends after each redraw, changes nothing.
TrayStep trayStep(
  List<TrayRow?> rows,
  int? selected,
  int message,
  int wParam, {
  int? at,
  bool pointed = false,
  bool moved = true,
}) {
  TrayStep stay(int? row, {bool by = false}) =>
      (selected: row, pointed: by, close: false, chosen: null);
  TrayStep keep() => stay(selected, by: pointed);
  const shut = (selected: null, pointed: false, close: true, chosen: null);
  TrayStep choose(int? row) => switch (row == null ? null : rows[row]) {
    final picked? when picked.enabled => (
      selected: row,
      pointed: pointed,
      close: true,
      chosen: picked,
    ),
    _ => keep(),
  };
  int? next(int from, int by) {
    for (var k = 1; k <= rows.length; k++) {
      final row = (from + by * k) % rows.length;
      if (rows[row]?.enabled ?? false) return row;
    }
    return null;
  }

  final onRow = at != null && at >= 0 && (rows[at]?.enabled ?? false);
  return switch (message) {
    WM_ACTIVATE when wParam & 0xFFFF == _waInactive => shut,
    WM_KEYDOWN => switch (wParam) {
      VK_ESCAPE => shut,
      VK_DOWN => stay(next(selected ?? -1, 1)),
      VK_UP => stay(next(selected ?? rows.length, -1)),
      VK_HOME => stay(next(-1, 1)),
      VK_END => stay(next(rows.length, -1)),
      VK_RETURN || VK_SPACE => choose(selected),
      _ => keep(),
    },
    WM_MOUSEMOVE when !moved => keep(),
    WM_MOUSEMOVE when onRow => stay(at, by: true),
    WM_MOUSEMOVE || wmMouseLeave => pointed ? stay(null) : keep(),
    WM_LBUTTONUP || WM_RBUTTONUP => at == -1 ? shut : choose(at),
    _ => keep(),
  };
}

/// Where the card's corner goes, in screen pixels: at the pointer, and [gap] inside the work
/// area, so it stands clear of the taskbar on whichever edge that is.
Offset trayCardAt(
  Offset pointer,
  Size card,
  Rect work, {
  required bool rtl,
  required double gap,
}) {
  double fit(double at, double start, double end, double size) =>
      at.clamp(start + gap, math.max(start + gap, end - gap - size));
  return Offset(
    fit(
      rtl ? pointer.dx - card.width : pointer.dx,
      work.left,
      work.right,
      card.width,
    ),
    fit(pointer.dy - card.height, work.top, work.bottom, card.height),
  );
}

/// win-modes.html, frame `win-t-c`: `.ctx`, its `.ctx-head`, `.ctx-item` and `.ctx-sep`.
class TrayMenuView extends StatelessWidget {
  const TrayMenuView(
    this.menu, {
    super.key,
    this.selected,
    this.icons = const {},
  });

  final TrayMenu menu;
  final int? selected;
  final Map<ShikooIcon, PictureInfo> icons;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final c = t.c;
    final s = t.s;
    final time = menu.time;
    final rule = Container(
      height: 1,
      margin: const EdgeInsets.symmetric(
        vertical: Space.s1,
        horizontal: Space.s2,
      ),
      color: c.border,
    );
    Widget row(int i, TrayRow row) {
      final fg = row.enabled ? c.text : c.iconDisabled;
      return MetaData(
        metaData: i,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: ShikooSizes.trayRow),
          padding: const EdgeInsets.symmetric(horizontal: Space.s3),
          decoration: BoxDecoration(
            color: i == selected ? c.selectedBg : null,
            borderRadius: BorderRadius.circular(Radii.trayRow),
          ),
          child: Row(
            spacing: Space.s2,
            children: [
              SizedBox.square(
                dimension: ShikooSizes.trayIcon,
                child: row.dot
                    ? Center(
                        child: Container(
                          width: ShikooSizes.trayDot,
                          height: ShikooSizes.trayDot,
                          decoration: BoxDecoration(
                            color: fg,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : CustomPaint(painter: _Glyph(icons[row.icon], fg)),
              ),
              Expanded(
                child: Text(
                  row.label,
                  style: t.text(
                    s.bodySm,
                    color: row.enabled ? c.text : c.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: ShikooSizes.trayMenu,
      padding: const EdgeInsets.all(Space.s1),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: c.border,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
        boxShadow: c.raisedShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Space.s2,
              horizontal: Space.s3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: ShikooSizes.trayHeadGap,
              children: [
                Text(
                  menu.head,
                  style: t.text(
                    s.body,
                    weight: FontWeight.w700,
                    color: menu.on
                        ? c.positive
                        : (menu.muted ? c.textMuted : c.text),
                  ),
                ),
                if (time != null)
                  Text(
                    time,
                    textDirection: TextDirection.ltr,
                    style: t.text(s.bodySm, color: c.textMuted, tabular: true),
                  ),
              ],
            ),
          ),
          rule,
          for (final (i, item) in menu.rows.indexed)
            item == null ? rule : row(i, item),
        ],
      ),
    );
  }
}

/// A [ShikooIcon] loaded ahead: the menu is drawn once per change, never waiting on a load.
class _Glyph extends CustomPainter {
  _Glyph(this.icon, this.color);

  final PictureInfo? icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final icon = this.icon;
    if (icon == null) return;
    canvas
      ..saveLayer(
        Offset.zero & size,
        Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
      )
      ..scale(size.width / icon.size.width)
      ..drawPicture(icon.picture)
      ..restore();
  }

  @override
  bool shouldRepaint(_Glyph old) => old.icon != icon || old.color != color;
}

/// The menu as Windows shows it: a borderless see-through window of its own, filled with a
/// picture Flutter draws apart from the app's window. FlClash stops the app's frames once
/// the window hides, so nothing here waits on one.
class TrayPopup {
  /// Room around the card for its raised shadow; see-through, so clicks there pass under.
  static const _margin = Space.s10;

  static TrayPopup? _shown;
  static NativeCallable<WNDPROC>? _proc;
  static final _class = 'ShikooTrayMenu'.toNativeUtf16();

  int _hwnd = 0;
  late TrayView _view;
  int? _selected;
  bool _pointed = false;
  Offset? _lastMove;
  Offset _origin = Offset.zero;
  Offset _pointer = Offset.zero;
  Rect _work = Rect.zero;
  double _scale = 1;
  final _icons = <ShikooIcon, PictureInfo>{};
  final _messages = <(int, int, int)>[];
  _Offscreen? _tree;
  bool _painting = false;
  bool _dirty = false;

  /// Called once the menu has closed, whatever closed it.
  VoidCallback? onClose;

  bool get isOpen => _hwnd != 0;

  HWND get _handle => HWND(Pointer.fromAddress(_hwnd));

  /// Opens the menu at the pointer, or draws [view] into it when it is open already.
  Future<void> show(TrayView view) async {
    _view = view;
    if (isOpen) return _paint();
    _measure();
    final instance = HINSTANCE(GetModuleHandle(null).value);
    _register(instance);
    _hwnd = CreateWindowEx(
      WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
      PCWSTR(_class),
      null,
      WS_POPUP,
      0,
      0,
      0,
      0,
      null,
      null,
      instance,
      null,
    ).value.address;
    _selected = null;
    _pointed = false;
    _lastMove = null;
    _shown = this;
    for (final icon in {for (final row in view.menu.rows) row?.icon}.nonNulls) {
      _icons[icon] ??= await vg.loadPicture(
        SvgStringLoader(svgOf(icon, ShikooSizes.iconStroke)),
        null,
      );
    }
    await _paint();
    if (!isOpen) return;
    ShowWindow(_handle, SW_SHOW);
    SetForegroundWindow(_handle);
  }

  /// Redraws an open menu; a closed one reads the state afresh when it opens.
  void update(TrayView view) {
    if (!isOpen) return;
    _view = view;
    unawaited(_paint());
  }

  void close() {
    if (!isOpen) return;
    final hwnd = _handle;
    _hwnd = 0;
    _shown = null;
    _messages.clear();
    DestroyWindow(hwnd);
    onClose?.call();
  }

  /// The pointer, and the work area and scale of the screen it is on.
  void _measure() {
    final at = calloc<POINT>();
    final dpi = calloc<Uint32>(2);
    final info = calloc<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
    try {
      GetCursorPos(at);
      final monitor = MonitorFromPoint(at.ref, MONITOR_DEFAULTTONEAREST);
      GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, dpi, dpi + 1);
      GetMonitorInfo(monitor, info);
      final work = info.ref.rcWork;
      _pointer = Offset(at.ref.x.toDouble(), at.ref.y.toDouble());
      _work = Rect.fromLTRB(
        work.left.toDouble(),
        work.top.toDouble(),
        work.right.toDouble(),
        work.bottom.toDouble(),
      );
      _scale = dpi.value / _defaultDpi;
    } finally {
      calloc
        ..free(at)
        ..free(dpi)
        ..free(info);
    }
  }

  static void _register(HINSTANCE instance) {
    if (_proc != null) return;
    final proc = _proc = NativeCallable<WNDPROC>.isolateLocal(
      _windowProc,
      exceptionalReturn: 0,
    );
    final wc = calloc<WNDCLASSEX>();
    wc.ref
      ..cbSize = sizeOf<WNDCLASSEX>()
      ..lpfnWndProc = proc.nativeFunction
      ..hInstance = instance
      ..hCursor = LoadCursor(null, IDC_ARROW).value
      ..lpszClassName = PWSTR(_class);
    RegisterClassEx(wc);
    calloc.free(wc);
  }

  static const _input = {
    WM_ACTIVATE,
    WM_KEYDOWN,
    WM_MOUSEMOVE,
    wmMouseLeave,
    WM_LBUTTONUP,
    WM_RBUTTONUP,
  };

  /// Windows calls this from its own message loop, between Flutter's tasks. Drawing the menu
  /// from here crashed flutter_windows.dll, so the input waits for a task of its own.
  static int _windowProc(Pointer hwnd, int message, int wParam, int lParam) {
    final popup = _shown;
    if (popup != null &&
        hwnd.address == popup._hwnd &&
        _input.contains(message)) {
      if (popup._messages.isEmpty) Timer.run(popup._drain);
      popup._messages.add((message, wParam, lParam));
    }
    return DefWindowProc(HWND(hwnd), message, WPARAM(wParam), LPARAM(lParam));
  }

  void _drain() {
    final messages = [..._messages];
    _messages.clear();
    for (final (message, wParam, lParam) in messages) {
      if (!isOpen) return;
      final pointer =
          message == WM_MOUSEMOVE ||
          message == WM_LBUTTONUP ||
          message == WM_RBUTTONUP;
      var moved = true;
      if (message == WM_MOUSEMOVE) {
        final at = _origin + _client(lParam);
        moved = at != _lastMove;
        _lastMove = at;
        _trackLeave();
      }
      final step = trayStep(
        _view.menu.rows,
        _selected,
        message,
        wParam,
        at: pointer ? _rowAt(lParam) : null,
        pointed: _pointed,
        moved: moved,
      );
      _pointed = step.pointed;
      if (step.close) {
        close();
        step.chosen?.run();
        return;
      }
      if (step.selected != _selected) {
        _selected = step.selected;
        unawaited(_paint());
      }
    }
  }

  /// Windows sends WM_MOUSELEAVE only when asked, once per ask.
  void _trackLeave() {
    final track = calloc<_TrackMouse>();
    track.ref
      ..cbSize = sizeOf<_TrackMouse>()
      ..dwFlags = _tmeLeave
      ..hwndTrack = Pointer.fromAddress(_hwnd);
    _trackMouseEvent(track);
    calloc.free(track);
  }

  static Offset _client(int lParam) => Offset(
    (lParam & 0xFFFF).toSigned(16).toDouble(),
    (lParam >> 16 & 0xFFFF).toSigned(16).toDouble(),
  );

  int? _rowAt(int lParam) {
    final tree = _tree;
    if (tree == null) return null;
    final at = _client(lParam) / _scale;
    if (!(Offset.zero & tree.boundary.size).deflate(_margin).contains(at)) {
      return -1;
    }
    final hits = BoxHitTestResult();
    tree.boundary.hitTest(hits, position: at);
    for (final hit in hits.path) {
      if (hit.target case RenderMetaData(metaData: final int row)) return row;
    }
    return null;
  }

  Future<void> _paint() async {
    if (_painting) {
      _dirty = true;
      return;
    }
    _painting = true;
    try {
      do {
        _dirty = false;
        final tree = _tree ??= _Offscreen();
        final image = await tree.render(_content(), _scale);
        try {
          if (isOpen) await _blit(image);
        } finally {
          image.dispose();
        }
      } while (_dirty && isOpen);
    } finally {
      _painting = false;
    }
  }

  Widget _content() => MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(
        WidgetsBinding.instance.platformDispatcher.textScaleFactor,
      ),
    ),
    child: Theme(
      data: shikooThemeData(_view.brightness, tv: false),
      child: Directionality(
        textDirection: _view.direction,
        child: Padding(
          padding: const EdgeInsets.all(_margin),
          child: TrayMenuView(_view.menu, selected: _selected, icons: _icons),
        ),
      ),
    ),
  );

  /// Puts [image] on screen, premultiplied as Windows wants it, with the card at the pointer.
  Future<void> _blit(ui.Image image) async {
    final rgba = (await image.toByteData())!.buffer.asUint8List();
    if (!isOpen) return;
    final w = image.width;
    final h = image.height;
    final margin = _margin * _scale;
    final card = trayCardAt(
      _pointer,
      Size(w - 2 * margin, h - 2 * margin),
      _work,
      rtl: _view.direction == TextDirection.rtl,
      gap: Space.s2 * _scale,
    );
    final info = calloc<BITMAPINFO>();
    info.ref.bmiHeader
      ..biSize = sizeOf<BITMAPINFOHEADER>()
      ..biWidth = w
      ..biHeight = -h
      ..biPlanes = 1
      ..biBitCount = 32;
    final bits = calloc<Pointer>();
    final screen = GetDC(null);
    final memory = CreateCompatibleDC(screen);
    final bitmap = CreateDIBSection(
      memory,
      info,
      DIB_RGB_COLORS,
      bits,
      null,
      0,
    ).value;
    final pixels = bits.value.cast<Uint8>().asTypedList(w * h * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      pixels[i] = rgba[i + 2];
      pixels[i + 1] = rgba[i + 1];
      pixels[i + 2] = rgba[i];
      pixels[i + 3] = rgba[i + 3];
    }
    final old = SelectObject(memory, HGDIOBJ(bitmap));
    _origin = Offset(
      (card.dx - margin).roundToDouble(),
      (card.dy - margin).roundToDouble(),
    );
    final to = calloc<POINT>()
      ..ref.x = _origin.dx.toInt()
      ..ref.y = _origin.dy.toInt();
    final from = calloc<POINT>();
    final size = calloc<SIZE>()
      ..ref.cx = w
      ..ref.cy = h;
    final blend = calloc<BLENDFUNCTION>()
      ..ref.SourceConstantAlpha = 255
      ..ref.AlphaFormat = _acSrcAlpha;
    final layered = calloc<UPDATELAYEREDWINDOWINFO>();
    layered.ref
      ..cbSize = sizeOf<UPDATELAYEREDWINDOWINFO>()
      ..hdcDst = screen
      ..pptDst = to
      ..psize = size
      ..hdcSrc = memory
      ..pptSrc = from
      ..pblend = blend
      ..dwFlags = ULW_ALPHA;
    UpdateLayeredWindowIndirect(_handle, layered);
    SelectObject(memory, old);
    DeleteObject(HGDIOBJ(bitmap));
    DeleteDC(memory);
    ReleaseDC(null, screen);
    for (final p in <Pointer>[info, bits, to, from, size, blend, layered]) {
      calloc.free(p);
    }
  }
}

const wmMouseLeave = 0x02A3;
const _tmeLeave = 2;

final class _TrackMouse extends Struct {
  @Uint32()
  external int cbSize;

  @Uint32()
  external int dwFlags;

  external Pointer hwndTrack;

  @Uint32()
  external int dwHoverTime;
}

final _trackMouseEvent = DynamicLibrary.open('user32.dll')
    .lookupFunction<
      Int32 Function(Pointer<_TrackMouse>),
      int Function(Pointer<_TrackMouse>)
    >('TrackMouseEvent');

/// A widget tree of its own, laid out and painted by hand.
class _Offscreen {
  final boundary = RenderRepaintBoundary();
  final _pipeline = PipelineOwner();
  final _build = BuildOwner(focusManager: FocusManager());
  late final _view = RenderView(
    view: WidgetsBinding.instance.platformDispatcher.implicitView!,
    child: boundary,
  );
  RenderObjectToWidgetElement<RenderBox>? _root;

  Future<ui.Image> render(Widget widget, double scale) {
    _view.configuration = ViewConfiguration(
      logicalConstraints: const BoxConstraints(),
      physicalConstraints: const BoxConstraints(),
      devicePixelRatio: scale,
    );
    if (_pipeline.rootNode == null) {
      _pipeline.rootNode = _view;
      _view.prepareInitialFrame();
    }
    final root = _root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: widget,
    ).attachToRenderTree(_build, _root);
    _build
      ..buildScope(root)
      ..finalizeTree();
    _pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    return boundary.toImage(pixelRatio: scale);
  }
}
