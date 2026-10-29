import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Hands [bytes] to the browser as a download called [name].
Future<String> saveFile(String name, Uint8List bytes, String mimeType) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..click();
  web.URL.revokeObjectURL(url);
  return 'Downloaded $name';
}

String captureFolder() => '';

void writeCapture(String path, Uint8List bytes) {}

void quit() {}
