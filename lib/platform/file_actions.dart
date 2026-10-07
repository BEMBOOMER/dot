import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

Future<void> openDotFile(String path) async {
  final result = await OpenFilex.open(path);
  if (result.type != ResultType.done) {
    throw StateError(result.message);
  }
}

Future<void> revealDotFile(String path) async {
  if (Platform.isMacOS) {
    final result = await Process.run('open', ['-R', path]);
    if (result.exitCode != 0) {
      throw ProcessException('open', ['-R', path], result.stderr, result.exitCode);
    }
    return;
  }
  await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
}

Future<void> shareDotFile(String path) async {
  await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
}
