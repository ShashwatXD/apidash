const kLabelSyncToPhone = 'Sync to phone';
const kLabelSyncScanQr =
    'Open API Dash on your phone and scan this QR to connect.';
const kLabelSyncWaitingForPhone = 'Waiting for phone…';
const kLabelSyncConnectedTo = 'Connected';
const kLabelSyncApplyChanges = 'Apply changes';
const kLabelSyncApplyAndSync = 'Apply & sync';
const kLabelSyncAlreadyInSync = 'Already in sync';
const kLabelSyncDiscardSession = 'Discard';
const kLabelSyncWaitingForChanges =
    'Changes will appear here after your phone connects';
const kLabelSyncSelectFile = 'Select a file to preview changes';
const kLabelSyncQrPlaceholder = 'QR code will appear here';
const kLabelSyncDiffLocal = 'Your edits';
const kLabelSyncDiffPeerPhone = 'From phone';
const kLabelSyncDiffPeerComputer = 'From computer';
const kLabelSyncNoChanges = 'No changes to review';
const kLabelSyncIncomingFromPhone = 'From phone';
const kLabelSyncFromDesktop = 'From computer';
const kLabelSyncConflicts = 'Conflicts';
const kLabelSyncSwitchAndSync = 'Switch & sync';
const kLabelSyncPairedBefore = 'Paired before - changes sync both ways.';
const kLabelSyncFirstPair = 'First time pairing';
const kLabelSyncApplying = 'Applying changes…';
const kLabelMobileCollaborationHint =
    'Sync your workspace with API Dash on your computer. Open Collaboration on desktop, then scan the QR code.';
const kLabelSyncScanDesktop = 'Scan desktop QR';
const kLabelSyncConnecting = 'Connecting…';
const kLabelSyncScanHint = 'Point your camera at the QR on your computer';
const kLabelSyncSameWifi = 'Phone and computer must be on the same Wi-Fi';
const kLabelSyncLastSynced = 'Last synced';
const kLabelSyncUnsynced = 'changes waiting to sync';
const kLabelSyncAdoptWorkspaceTitle = 'Use this workspace?';
const kLabelSyncAdoptWorkspaceBody =
    'This looks like a new workspace from your computer. Use it for syncing to get a fresh copy on your phone,anything here now will be replaced.';
const kLabelSyncAdoptWorkspaceConfirm = 'Use for syncing';
const kLabelSyncAdoptWorkspaceCancel = 'Not now';
const kLabelSyncClose = 'Close';
const kLabelSyncContinueOnPhone = 'Continue on phone';
const kLabelSyncPhoneLeadsHint =
    'Finish on your phone, nothing to apply on this computer yet.';
const kLabelSyncWaitingForPhoneApply = 'Waiting for your phone to finish…';

// --- Messages ---

const kMsgSyncApplySuccess = 'Sync complete';
const kMsgSyncWorkspaceUpdated = 'Workspace updated from peer';

// --- Errors ---

const kErrSyncNoWorkspace =
    'Select a workspace folder before syncing to your phone.';
const kErrSyncServerStart =
    'Could not start the sync server. Check your network and try again.';
const kErrSyncNoNetwork =
    'No local network connection found. Connect to Wi-Fi and retry.';
const kErrSyncApplyFailed = 'Could not apply sync changes';
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

