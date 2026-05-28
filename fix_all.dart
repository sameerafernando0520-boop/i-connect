import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  int count = 0;
  for (final file in files) {
    String content = file.readAsStringSync();
    final regex = RegExp(r'\.withOpacity\(([^)]+)\)');
    if (regex.hasMatch(content)) {
      content = content.replaceAllMapped(regex, (match) => '.withAlpha(((${match.group(1)}) * 255).toInt())');
      file.writeAsStringSync(content);
      count++;
    }
  }
  print('Fixed: $count');
}
