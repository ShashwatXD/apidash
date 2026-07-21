import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:apidash/services/storage/disk_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('apidash_disk_change_');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  String path(List<String> parts) => p.joinAll([root.path, ...parts]);

  test('classifies request folder delete', () {
    final change = classifyWorkspaceDiskEvent(
      event: FileSystemDeleteEvent(
        path([
          kWorkspaceCollectionsDir,
          'API',
          'get-users_abcd1234',
        ]),
        false,
      ),
      workspaceRoot: root.path,
    );

    expect(
      change,
      const RequestRemovedFromDisk(
        collectionId: 'API',
        requestId: 'get-users_abcd1234',
      ),
    );
  });

  test('classifies collection folder delete', () {
    final change = classifyWorkspaceDiskEvent(
      event: FileSystemDeleteEvent(
        path([kWorkspaceCollectionsDir, 'API']),
        false,
      ),
      workspaceRoot: root.path,
    );

    expect(change, const CollectionRemovedFromDisk('API'));
  });

  test('classifies Finder move-to-trash as request removal', () {
    final change = classifyWorkspaceDiskEvent(
      event: FileSystemMoveEvent(
        path([
          kWorkspaceCollectionsDir,
          'API',
          'get-users_abcd1234',
        ]),
        false,
        p.join(root.parent.path, '.Trash', 'get-users_abcd1234'),
      ),
      workspaceRoot: root.path,
    );

    expect(
      change,
      const RequestRemovedFromDisk(
        collectionId: 'API',
        requestId: 'get-users_abcd1234',
      ),
    );
  });

  test('ignores history and env paths', () {
    final change = classifyWorkspaceDiskEvent(
      event: FileSystemDeleteEvent(
        path([kWorkspaceHistoryDir, 'abc.json']),
        true,
      ),
      workspaceRoot: root.path,
    );
    expect(change, isNull);
  });

  test('classifies collection folder create as add', () {
    final change = classifyWorkspaceDiskEvent(
      event: FileSystemCreateEvent(
        path([kWorkspaceCollectionsDir, 'Imported']),
        false,
      ),
      workspaceRoot: root.path,
    );

    expect(change, const CollectionAddedFromDisk('Imported'));
  });

  test('classifies request folder create as add', () {
    final change = classifyWorkspaceDiskEvent(
      event: FileSystemCreateEvent(
        path([
          kWorkspaceCollectionsDir,
          'API',
          'get-users_abcd1234',
        ]),
        false,
      ),
      workspaceRoot: root.path,
    );

    expect(
      change,
      const RequestAddedFromDisk(
        collectionId: 'API',
        requestId: 'get-users_abcd1234',
      ),
    );
  });

  test('classifies request.json create as add', () {
    final change = classifyWorkspaceDiskEvent(
      event: FileSystemCreateEvent(
        path([
          kWorkspaceCollectionsDir,
          'API',
          'get-users_abcd1234',
          kWorkspaceRequestFile,
        ]),
        true,
      ),
      workspaceRoot: root.path,
    );

    expect(
      change,
      const RequestAddedFromDisk(
        collectionId: 'API',
        requestId: 'get-users_abcd1234',
      ),
    );
  });

  test('classifies request.json modify as content change', () {
    final change = classifyWorkspaceDiskEvent(
      event: FileSystemModifyEvent(
        path([
          kWorkspaceCollectionsDir,
          'API',
          'get-users_abcd1234',
          kWorkspaceRequestFile,
        ]),
        true,
        false,
      ),
      workspaceRoot: root.path,
    );

    expect(
      change,
      const RequestContentChangedOnDisk(
        collectionId: 'API',
        requestId: 'get-users_abcd1234',
      ),
    );
  });

  test('ignores tmp write noise', () {
    final change = classifyWorkspaceDiskEvent(
      event: FileSystemModifyEvent(
        path([
          kWorkspaceCollectionsDir,
          'API',
          'get-users_abcd1234',
          '${kWorkspaceRequestFile}.tmp',
        ]),
        true,
        false,
      ),
      workspaceRoot: root.path,
    );
    expect(change, isNull);
  });
}
