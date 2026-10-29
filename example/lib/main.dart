import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:text_on_path/text_on_path.dart';

import 'bend.dart';
import 'compare.dart';
import 'draw.dart';
import 'panel.dart';
import 'platform_io.dart' if (dart.library.js_interop) 'platform_web.dart' as platform;
import 'seal.dart';
import 'zoom.dart';

/// With `--dart-define=CAPTURE=true` (not on the web), the app saves each tab as a PNG in its temporary directory and
/// quits.
const capture = bool.fromEnvironment('CAPTURE');

void main() => runApp(const TextOnPathDemo());

class TextOnPathDemo extends StatelessWidget {
  const TextOnPathDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'text_on_path',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: joinedColor, surface: paper),
        scaffoldBackgroundColor: paper,
        sliderTheme: const SliderThemeData(trackHeight: 2.5),
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> with SingleTickerProviderStateMixin {
  static const _pages = ['Bend', 'Compare', 'Draw', 'Seals', 'Zoom'];
  late final _tabs = TabController(length: _pages.length, vsync: this);
  final _boundary = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (capture && !kIsWeb) WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  Future<void> _capture() async {
    final dir = platform.captureFolder();
    Future<void> save(String name) async {
      await Future<void>.delayed(const Duration(seconds: 3));
      final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: ui.PlatformDispatcher.instance.views.first.devicePixelRatio);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      platform.writeCapture('$dir/$name.png', png!.buffer.asUint8List());
    }

    await save('bend');
    _tabs.index = 1;
    await save('compare');
    compareScroll.jumpTo(compareScroll.position.maxScrollExtent);
    await save('compare_end');
    for (final (i, name) in [(2, 'draw'), (3, 'seals'), (4, 'zoom')]) {
      _tabs.index = i;
      await save(name);
    }
    // Zoomed in 8 times: one atlas, then the atlas drawn again for the zoom, then outlines.
    zoomInOnText(8);
    for (final rendering in [TextOnPathRendering.raster, TextOnPathRendering.auto, TextOnPathRendering.vector]) {
      zoomRendering.value = rendering;
      await save('zoom8_${rendering.name}');
    }
    platform.quit();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundary,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'text_on_path',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ink),
                    ),
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: const Text(
                        'Text along any curve, cursive joins kept closed. Turning each letter whole, as text-on-path '
                        'packages do, opens joins on the outside of a bend and overlaps them on the inside; bending '
                        'the whole line stretches the letters. text_on_path keeps letters rigid and bends only the '
                        'rows they join on.',
                        style: TextStyle(fontSize: 13, color: muted, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final p in _pages) Tab(text: p)],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  physics: const NeverScrollableScrollPhysics(),
                  children: const [BendPage(), ComparePage(), DrawPage(), SealPage(), ZoomPage()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
