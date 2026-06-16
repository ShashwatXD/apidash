const kLabelCloneFromGitOptional = 'CLONE FROM GIT [OPTIONAL]';
const kMsgGitCloneSuccess = 'Repository cloned and workspace opened';

const kGitIconAsset = 'assets/git/giticon.png';
const kLabelGitAhead = 'Ahead';
const kLabelGitBehind = 'Behind';
const kLabelGitBackToOverview = 'Back';
const kLabelGitDiffPreview = 'Select a file to preview changes';
const kLabelGitDiffLoading = 'Loading diff…';
const kLabelGitDiffEmpty = 'No diff available';
const kLabelGitFilesSelected = 'files selected';
const kMsgGitNotInstalled =
    'Git is not installed. Install Git to clone repositories or use Collaboration.';
const kMsgGitNotARepository = 'This workspace is not a Git repository yet.';
const kMsgGitNoChanges = 'No uncommitted changes';
const kMsgGitNoCommits = 'No commits yet';
const kMsgGitSyncSuccess = 'Changes synced to remote';
const kMsgGitCommitSuccess = 'Changes committed';
const kMsgGitPushSuccess = 'Pushed to remote';
const kMsgGitFetchSuccess = 'Fetched from remote';
const kMsgGitPullSuccess = 'Pulled latest changes';
const kMsgGitRestoreCommitSuccess = 'Workspace restored to selected commit';
const kMsgGitRestoreCommitConfirmTitle = 'Restore this commit?';
const kMsgGitRestoreCommitConfirmBody =
    'Workspace files will match this commit. Uncommitted changes and any newer commits on this branch are removed locally.';
const kLabelGitRestoreCommit = 'Restore';
const kMsgGitPushRejected =
    'Remote has new changes. Pull first, then push again.';
const kMsgGitPullDivergent =
    'Local and remote both have new commits. Pull again to merge them.';
const kMsgGitMergeConflict =
    'The same file was changed on both sides. Pull was cancelled. Edit the file in your editor, then try Pull again.';
const kMsgGitUnmergedFiles =
    'A previous merge was not finished. Pull was cancelled — try Pull again.';
const kMsgGitAuthRequired =
    'This remote needs authentication. Sign in with Git Credential Manager or SSH, then try again.';
const kMsgGitOverviewHint =
    'Perform git actions or open files from sidebar to view';
const kMsgGitNeverFetched = 'Not fetched yet';
const kMsgGitLastFetchedJustNow = 'Last fetched: less than a minute ago';
const kMsgGitCheckoutSuccess = 'Switched branch';
const kGitInstallUrl = 'https://git-scm.com/downloads';
const kLabelGitSetupStepInstall = 'Install Git';
const kLabelGitSetupStepInit = 'Initialize repository';
const kLabelGitSetupStepRemote = 'Connect remote';
const kLabelGitSetupStepSync = 'Sync workspace';
const kMsgGitSetupInstallBody =
    'Git must be installed on your computer. API Dash uses your system Git for push and pull.';
const kMsgGitSetupInitBody =
    'Turn this workspace folder into a Git repository. Your requests and environments will be versioned as JSON files.';
const kMsgGitSetupRemoteBody =
    'Create an empty repository on GitHub, GitLab, Bitbucket, or any Git host, then paste the clone URL here.';
const kMsgGitSetupSyncBody =
    'Select your changes, write a commit message, and sync to publish the workspace for the first time.';

String formatGitBehindRemoteHint(int behind) {
  final unit = behind == 1 ? 'commit' : 'commits';
  return '$behind $unit behind remote. Pull to update before pushing.';
}
