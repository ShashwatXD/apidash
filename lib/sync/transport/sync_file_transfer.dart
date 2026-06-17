import '../consts.dart';

/// Shared surface for LAN file exchange during apply (host or client).
abstract class SyncFileTransfer {
  Future<String?> fetchPeerFile(
    String path, {
    Duration timeout = kSyncFileRequestTimeout,
  });

  Future<void> sendLocalFile(String path, String content);
  Future<void> sendDeletedFile(String path);
  Future<void> sendApplyComplete(Map<String, String> manifest);
}
