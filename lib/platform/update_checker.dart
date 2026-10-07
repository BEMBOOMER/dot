import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class DotUpdate {
  final String version;
  final Uri url;
  final String notes;
  const DotUpdate({
    required this.version,
    required this.url,
    required this.notes,
  });
}

Future<DotUpdate?> checkForDotUpdate() async {
  final response = await http.get(
    Uri.parse('https://api.github.com/repos/BEMBOOMER/dot/releases/latest'),
    headers: const {'Accept': 'application/vnd.github+json'},
  );
  if (response.statusCode != 200) {
    throw StateError('GitHub Releases gaf status ${response.statusCode}.');
  }
  final json = jsonDecode(response.body);
  if (json is! Map<String, dynamic>) throw const FormatException('Ongeldige release.');
  final tag = (json['tag_name'] as String?)?.replaceFirst(RegExp(r'^v'), '');
  final url = Uri.tryParse(json['html_url'] as String? ?? '');
  if (tag == null || url == null) throw const FormatException('Onvolledige release.');
  final current = (await PackageInfo.fromPlatform()).version;
  if (!_isNewer(tag, current)) return null;
  return DotUpdate(
    version: tag,
    url: url,
    notes: json['body'] as String? ?? '',
  );
}

bool _isNewer(String candidate, String current) {
  List<int> parse(String value) => value
      .split('+')
      .first
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList(growable: false);
  final a = parse(candidate);
  final b = parse(current);
  for (var i = 0; i < 3; i++) {
    final av = i < a.length ? a[i] : 0;
    final bv = i < b.length ? b[i] : 0;
    if (av != bv) return av > bv;
  }
  return false;
}
