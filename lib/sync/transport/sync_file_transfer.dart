import '../consts.dart';

/// Shared surface for LAN file exchange during apply (host or client).
abstract class SyncFileTransfer {
  Future<String?> fetchPeerFile(
    String path, {
    Duration timeout = kSyncFileRequestTimeout,
  });

  Future<void> sendApplyComplete(
    Map<String, String> manifest, {
    Map<String, String> writes = const {},
    List<String> deletes = const [],
  });
}
