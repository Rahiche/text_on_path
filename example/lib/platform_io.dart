import 'dart:io';
import 'dart:typed_data';

/// Saves [bytes] as [name] in the app's temporary folder, and says where.
Future<String> saveFile(String name, Uint8List bytes, String mimeType) async {
  final dir = Directory('${Directory.systemTemp.path}/text_on_path_export')..createSync(recursive: true);
  final file = File('${dir.path}/$name')..writeAsBytesSync(bytes);
  return 'Saved ${file.path}';
}

/// Where captures go, for `--dart-define=CAPTURE=true`.
String captureFolder() =>
    (Directory('${Directory.systemTemp.path}/text_on_path_capture')..createSync(recursive: true)).path;

void writeCapture(String path, Uint8List bytes) {
  File(path).writeAsBytesSync(bytes);
  stdout.writeln('CAPTURED $path');
}

void quit() => exit(0);
