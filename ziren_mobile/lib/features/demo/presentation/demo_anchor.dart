import 'package:flutter/widgets.dart';

/// Marks a part of a screen that a demo can point at.
///
/// Costs nothing when no demo is running: it registers a key under [id] and
/// builds its child unchanged. Ids are per screen ("home.report",
/// "nav.map"), so two tabs kept alive by the shell never claim the same one.
class DemoAnchor extends StatefulWidget {
  const DemoAnchor({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<DemoAnchor> createState() => _DemoAnchorState();
}

class _DemoAnchorState extends State<DemoAnchor> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    DemoAnchors._add(widget.id, _key);
  }

  @override
  void didUpdateWidget(DemoAnchor old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      DemoAnchors._remove(old.id, _key);
      DemoAnchors._add(widget.id, _key);
    }
  }

  @override
  void dispose() {
    DemoAnchors._remove(widget.id, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}

/// Where the anchors on screen are.
abstract final class DemoAnchors {
  static final Map<String, List<GlobalKey>> _byId = {};

  static void _add(String id, GlobalKey key) => (_byId[id] ??= []).add(key);

  static void _remove(String id, GlobalKey key) {
    final keys = _byId[id];
    keys?.remove(key);
    if (keys != null && keys.isEmpty) _byId.remove(id);
  }

  /// The newest mounted widget under [id] that is actually painted (a tab the
  /// shell keeps offstage is not).
  static BuildContext? contextOf(String id) {
    final keys = _byId[id];
    if (keys == null) return null;
    for (final key in keys.reversed) {
      final ctx = key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize && _visible(ctx)) {
        return ctx;
      }
    }
    return null;
  }

  static bool _visible(BuildContext ctx) {
    var onstage = true;
    ctx.visitAncestorElements((e) {
      final w = e.widget;
      if (w is Offstage && w.offstage) onstage = false;
      if (w is TickerMode && !w.enabled) onstage = false;
      if (w is Visibility && !w.visible) onstage = false;
      return onstage;
    });
    return onstage;
  }

  /// Every marked part on screen now, newest first.
  static Iterable<BuildContext> mountedContexts() sync* {
    for (final id in _byId.keys.toList()) {
      final ctx = contextOf(id);
      if (ctx != null) yield ctx;
    }
  }

  /// Ids currently registered (mounted), for tests and for waiting on a
  /// screen to finish building.
  static bool isMounted(String id) => contextOf(id) != null;

  @visibleForTesting
  static Iterable<String> get ids => _byId.keys;
}
