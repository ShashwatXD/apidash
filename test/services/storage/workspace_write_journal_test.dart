import 'package:apidash/services/storage/disk_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records path and matches recent writes', () {
    final journal = WorkspaceWriteJournal(
      ttl: const Duration(seconds: 2),
    );
    journal.record('/workspace/collections/A/req/request.json');

    expect(
      journal.wasRecent('/workspace/collections/A/req/request.json'),
      isTrue,
    );
    expect(
      journal.wasRecent('/workspace/collections/A/req/request.json.tmp'),
      isFalse,
    );
    expect(
      journal.wasRecent('/workspace/collections/B/other'),
      isFalse,
    );
  });

  test('journaled folder covers descendant events', () {
    final journal = WorkspaceWriteJournal();
    journal.record('/workspace/collections/A/req');

    expect(journal.wasRecent('/workspace/collections/A/req'), isTrue);
    expect(
      journal.wasRecent('/workspace/collections/A/req/request.json'),
      isTrue,
    );
    expect(journal.wasRecent('/workspace/collections/A'), isFalse);
    expect(journal.wasRecent('/workspace'), isFalse);
  });
}
