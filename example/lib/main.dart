import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:text_on_path/text_on_path.dart';

import 'compare.dart';
import 'panel.dart';
import 'seal.dart';
import 'zoom.dart';

/// With `--dart-define=CAPTURE=true`, the app saves each tab as a PNG in its temporary directory and quits.
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
  late final _tabs = TabController(length: 3, vsync: this);
  final _boundary = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (capture) WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  Future<void> _capture() async {
    final dir = Directory('${Directory.systemTemp.path}/text_on_path_capture')..createSync(recursive: true);
    Future<void> save(String name) async {
      await Future<void>.delayed(const Duration(seconds: 3));
      final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: ui.PlatformDispatcher.instance.views.first.devicePixelRatio);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${dir.path}/$name.png')..writeAsBytesSync(png!.buffer.asUint8List());
      stdout.writeln('CAPTURED ${file.path}');
    }

    await save('compare');
    compareScroll.jumpTo(compareScroll.position.maxScrollExtent);
    await save('compare_end');
    for (final (i, name) in [(1, 'seals'), (2, 'zoom')]) {
      _tabs.index = i;
      await save(name);
    }
    // Zoomed in 8 times: one atlas, then the atlas drawn again for the zoom, then outlines.
    zoomInOnText(8);
    for (final rendering in [TextOnPathRendering.raster, TextOnPathRendering.auto, TextOnPathRendering.vector]) {
      zoomRendering.value = rendering;
      await save('zoom8_${rendering.name}');
    }
    exit(0);
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
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Text on a curve, joins kept',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ink),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Rigid per-glyph placement turns each letter whole, so joins open on the outside of a bend and '
                      'overlap on the inside. Joined placement keeps letters rigid but lets the rows they join on '
                      'follow the curve. Joins: area of gaps and overlaps. Distortion: how far ink moved from a rigid '
                      'letter (RMS). Both measured on the drawn mesh.',
                      style: TextStyle(fontSize: 13, color: muted, height: 1.4),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: 'Compare'),
                  Tab(text: 'Seals'),
                  Tab(text: 'Zoom'),
                ],
              ),
              Expanded(
                child: TabBarView(controller: _tabs, children: const [ComparePage(), SealPage(), ZoomPage()]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
