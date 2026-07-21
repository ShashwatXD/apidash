import 'package:apidash/services/storage/disk_sync.dart';
import 'package:apidash/utils/file_utils.dart';
import 'package:test/test.dart';

void main() {
  test('macOS Finder copy folder gets distinct display name', () {
    final name = displayNameForRequestFolder(
      folderId: 'get-users_abcd1234 copy',
      jsonName: 'Get users',
      takenDisplayNamesLowercase: {'get users'},
    );
    expect(name, 'Get users copy');
  });

  test('Windows Explorer copy folder gets distinct display name', () {
    final name = displayNameForRequestFolder(
      folderId: 'get-users_abcd1234 - Copy',
      jsonName: 'Get users',
      takenDisplayNamesLowercase: {'get users'},
    );
    expect(name, 'Get users copy');
  });

  test('Windows numbered copy folder is numbered', () {
    final name = displayNameForRequestFolder(
      folderId: 'get-users_abcd1234 - Copy (2)',
      jsonName: 'Get users',
      takenDisplayNamesLowercase: {'get users'},
    );
    expect(name, 'Get users copy 2');
  });

  test('Linux Nautilus copy folder gets distinct display name', () {
    final name = displayNameForRequestFolder(
      folderId: 'get-users_abcd1234 (copy)',
      jsonName: 'Get users',
      takenDisplayNamesLowercase: {'get users'},
    );
    expect(name, 'Get users copy');
  });

  test('Linux numbered copy folder is numbered', () {
    final name = displayNameForRequestFolder(
      folderId: 'get-users_abcd1234 (copy 2)',
      jsonName: 'Get users',
      takenDisplayNamesLowercase: {'get users'},
    );
    expect(name, 'Get users copy 2');
  });

  test('display name stays unique against taken names', () {
    final name = displayNameForRequestFolder(
      folderId: 'get-users_abcd1234 copy',
      jsonName: 'Get users',
      takenDisplayNamesLowercase: {'get users', 'get users copy'},
    );
    expect(name, 'Get users copy 2');
  });

  test('requestFolderNeedsNormalize detects OS copies', () {
    expect(requestFolderNeedsNormalize('get-users_abcd1234 copy'), isTrue);
    expect(requestFolderNeedsNormalize('get-users_abcd1234 - Copy'), isTrue);
    expect(requestFolderNeedsNormalize('get-users_abcd1234 (copy)'), isTrue);
    expect(requestFolderNeedsNormalize('get-users_abcd1234'), isFalse);
  });

  test('allocateUniqueStorageId avoids taken ids', () {
    final taken = {'get-users-copy_aaaaaaaa'};
    final id = allocateUniqueStorageId(
      'Get users copy',
      taken.contains,
    );
    expect(id, isNot('get-users-copy_aaaaaaaa'));
    expect(id, startsWith('get-users-copy_'));
  });
}
