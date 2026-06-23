const kLabelSyncToPhone = 'Sync to phone';
const kLabelSyncScanQr =
    'Open API Dash on your phone and scan this QR to connect.';
const kLabelSyncWaitingForPhone = 'Waiting for phone…';
const kLabelSyncConnectedTo = 'Connected';
const kLabelSyncUpdate = 'Update';
const kLabelSyncAlreadyInSync = 'Already in sync';
const kLabelSyncDiscardSession = 'Discard';
const kLabelSyncWaitingForChanges =
    'Changes will appear here after your phone connects';
const kLabelSyncSelectFile = 'Select a file to preview changes';
const kLabelSyncQrPlaceholder = 'QR code will appear here';
const kLabelSyncDiffLocal = 'Your edits';
const kLabelSyncDiffBaseline = 'Last synced';
const kLabelSyncDiffPeerPhone = 'From phone';
const kLabelSyncDiffPeerComputer = 'From computer';
const kLabelSyncNoChanges = 'No changes in this direction';
const kLabelSyncSend = 'Send';
const kLabelSyncReceive = 'Receive';
const kLabelSyncSendingToPhone = 'Sending to phone';
const kLabelSyncSendingToComputer = 'Sending to computer';
const kLabelSyncReceivingFromPhone = 'Receiving from phone';
const kLabelSyncReceivingFromComputer = 'Receiving from computer';
const kLabelSyncUpdatePhone = 'Update phone';
const kLabelSyncUpdateComputer = 'Update computer';
const kLabelSyncUpdateFromPhone = 'Update from phone';
const kLabelSyncUpdateFromComputer = 'Update from computer';
const kLabelSyncUpdating = 'Updating…';
const kLabelSyncSwitchAndSync = 'Switch & sync';
const kLabelSyncPairedBefore = 'Paired before - use Send or Receive to sync.';
const kLabelSyncFirstPair = 'First time pairing';
const kLabelSyncScanDesktop = 'Scan desktop QR';
const kLabelSyncConnecting = 'Connecting…';
const kLabelSyncScanHint = 'Point your camera at the QR on your computer';
const kLabelSyncSameWifi = 'Phone and computer must be on the same Wi-Fi';
const kLabelSyncLastSynced = 'Last synced';
const kLabelSyncUnsynced = 'changes waiting to sync';
const kLabelSyncAdoptWorkspaceTitle = 'Use this workspace?';
const kLabelSyncAdoptWorkspaceBody =
    'This looks like a new workspace from your computer. Use it for syncing to get a fresh copy on your phone. Anything here now will be replaced.';
const kLabelSyncAdoptWorkspaceConfirm = 'Use for syncing';
const kLabelSyncAdoptWorkspaceCancel = 'Not now';
const kLabelSyncClose = 'Close';
const kLabelSyncReceiveConfirmTitle = 'Update from peer?';
const kLabelSyncReceiveConfirmBody =
    'Files you also edited will be replaced with the peer version.';

// --- Messages ---

const kMsgSyncUpdateSuccess = 'Update complete';
const kMsgSyncWorkspaceUpdated = 'Workspace updated from peer';

// --- Errors ---

const kErrSyncNoWorkspace =
    'Select a workspace folder before syncing to your phone.';
const kErrSyncServerStart =
    'Could not start the sync server. Check your network and try again.';
const kErrSyncNoNetwork =
    'No local network connection found. Connect to Wi-Fi and retry.';
const kErrSyncUpdateFailed = 'Could not complete update';
const kErrSyncSessionExpired = 'Sync session expired. Open sync again.';
const kErrSyncInvalidQr = 'Not a valid API Dash sync QR code';
const kErrSyncConnectFailed = 'Could not connect to desktop';

// --- Display names ---

const kSyncFallbackDisplayNamePrefix = 'API Dash';
// --- Storage paths ---

const kSyncApidashDir = '.apidash';
const kWorkspaceIdentityRelativePath = '$kSyncApidashDir/workspace.json';
const kSyncStateRelativePath = '$kSyncApidashDir/sync.json';

// --- Wire protocol ---

const kSyncProtocolVersion = 1;
const kSyncDefaultPort = 4571;
const kSyncWebSocketPath = '/sync';
const kSyncTokenLength = 8;
const kSyncTokenAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

// --- Timeouts ---

const kSyncSessionTimeout = Duration(minutes: 5);
const kSyncFileRequestTimeout = Duration(seconds: 30);

