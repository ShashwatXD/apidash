import 'package:flutter_riverpod/legacy.dart';

/// Which segment is selected inside [DashboardPage] (Collections vs Workflows).
enum DashboardMainTab {
  collections,
  workflows,
}

/// One-shot intent when navigating from elsewhere (e.g. Workflow page → analytics).
class DashboardOpenIntent {
  const DashboardOpenIntent({
    required this.tab,
    this.workflowId,
  });

  final DashboardMainTab tab;
  final String? workflowId;
}

final dashboardOpenIntentProvider = StateProvider<DashboardOpenIntent?>((ref) => null);

/// When set, [WorkflowDashboardPage] selects this workflow id once, then clears.
final workflowDashboardFocusIdProvider = StateProvider<String?>((ref) => null);
