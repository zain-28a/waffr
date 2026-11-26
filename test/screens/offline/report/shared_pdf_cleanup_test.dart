// cleanUpSharedPdfs: shared PDFs older than a day are deleted at start-up;
// newer ones and other files stay.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/screens/offline/report/expense_history_share.dart';

void main() {
  late Directory folder;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('shared_pdfs');
  });

  tearDown(() async {
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  test('old PDFs go, recent PDFs and other files stay', () async {
    final now = DateTime(2026, 11, 26, 12);
    final old = File('${folder.path}/waffr-expenses-1.pdf')
      ..writeAsStringSync('x');
    old.setLastModifiedSync(now.subtract(const Duration(days: 2)));
    final recent = File('${folder.path}/waffr-expenses-2.pdf')
      ..writeAsStringSync('x');
    recent.setLastModifiedSync(now.subtract(const Duration(hours: 2)));
    final other = File('${folder.path}/note.txt')..writeAsStringSync('x');
    other.setLastModifiedSync(now.subtract(const Duration(days: 9)));

    await cleanUpSharedPdfs(now: now, folder: folder);

    expect(old.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
  });

  test('a missing folder is fine', () async {
    await folder.delete();
    await cleanUpSharedPdfs(folder: folder);
  });
}
