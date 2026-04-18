# Implementation plan: Remove Hive → Git-friendly filesystem storage

**Audience:** Implementation and review.  
**POC focus:** Remove **`hive_ce_flutter` completely** first. **One collection = one folder on disk** that matches **one GitHub repo** (same JSON layout as `GitCollectionSerializer`). **No Hive** in dependencies or code paths when done.

---

## 1. Executive summary

| Item | Decision |
|------|----------|
| **Storage** | JSON files under a single **root** (`<workspace>/.apidash_data` or app documents `apidash_data/`). |
| **Collection** | A **folder** `collections/<collectionId>/`, not one monolithic file. |
| **Git** | **Local tree = Git repo layout**: `collection.json`, `environments.json`, `requests/*.json` per collection (see `GitCollectionPaths`). **Connect / import / push / pull** behavior stays the same; only the **data source** for snapshots changes from Hive → files. |
| **UX** | Unchanged: Riverpod, sidebar (collections + request **names**), debounced autosave, `saveData()`. |
| **Migration from Hive** | **Out of scope for initial POC** unless explicitly added later (fresh start or re-import). |

---

## 2. Core architecture (mental model)

```
┌─────────────────────────────────────────────────────────────┐
│  UI (Riverpod) — same as today                               │
│  CollectionModel, RequestModel, environments, etc.         │
└───────────────────────────┬─────────────────────────────────┘
                            │ read / write
┌───────────────────────────▼─────────────────────────────────┐
│  FileSystemHandler (single persistence API)                 │
│  Atomic writes (*.tmp → rename)                            │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  On-disk tree under <root>/                                 │
│  collections/<id>/  ←→  one GitHub repo per collection      │
└─────────────────────────────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  GitSyncService + GitHubApiAdapter + GitCollectionSerializer │
│  Build file map from disk OR from models after saveData()   │
└─────────────────────────────────────────────────────────────┘
```

**Rule:** `CollectionModel.gitConnection` still means **this collection’s** remote; **1 collection : 1 repo** is unchanged.

---

## 3. On-disk layout (full)

**Root** `apidash_data/` (or `.apidash_data` under workspace):

```
apidash_data/
  app.json                         # minimal app index (optional): activeCollectionId, activeWorkflowId, schemaVersion
                                   # OR fold into first collection / shared_preferences — keep small

  collections/
    <collectionId>/
      collection.json              # id, name, description, requestOrder, activeEnvironmentId, gitConnection, …
      environments.json            # same shape Git push uses (export + global merge rules as today)
      requests/
        <requestId>.json           # full RequestModel (includes name for sidebar)

  environments/                    # global env list (sidebar “Global” + named envs) — if still global in app
    <environmentId>.json

  workflows/
    <workflowId>.json
    runs_<workflowId>.json

  history/
    <historyId>.json               # full HistoryRequestModel (or split later if size matters)

  dashbot/
    messages.json
```

**Why a folder per collection (not one JSON file):**

- Matches **Git** (`requests/*.json` per file).
- Autosave can update **one request file** without rewriting the whole collection.
- **`collection.json`** holds **metadata + request order** (what the pane shows); each **`requests/<id>.json`** holds the full request including **`name`**.

**Optional `app.json`:** only if you need a single place for **active collection id** / **workflow id** without scanning. Can be replaced by **`shared_preferences`** for pointers only—team choice.

---

## 4. What replaces Hive (feature map)

| Former Hive box | On-disk |
|-----------------|--------|
| `apidash-data` (collections, requests, workflows) | `collections/`, `workflows/` |
| `apidash-request-meta` | Derive from `collection.json` + `requests/*.json` (or cache in memory) |
| `apidash-environments` | `environments/` + per-collection `environments.json` for Git |
| `apidash-history-*` | `history/` |
| `apidash-dashbot-data` | `dashbot/messages.json` |

---

## 5. Phased implementation

### Phase 1 — Foundation (storage API + init)

**Goal:** App can resolve **root**, create tree, read/write JSON with **atomic writes**.

**Deliverables:**

- [ ] Add `lib/services/file_system_handler.dart` — `FileSystemHandler` with same **logical API** as `HiveHandler` (or subset + expand in Phase 2).
- [ ] `initFileSystemHandler(bool useWorkspacePath, String? path)` — mirror `initHiveBoxes` rules.
- [ ] Unit tests: atomic write, round-trip for `RequestModel` / `CollectionModel` JSON.
- [ ] Export from `lib/services/services.dart` (alongside or replacing hive export during transition).

**Exit criteria:** Tests pass; handler can create `collections/<id>/collection.json` and `requests/<rid>.json`.

---

### Phase 2 — Collections + requests (largest surface)

**Goal:** **Sidebar and autosave** work with **no Hive** for core collection data.

**Deliverables:**

- [ ] Refactor `lib/providers/collection_providers.dart`: replace `hiveHandler` with `fileSystemHandler` (or injected abstraction).
- [ ] Bootstrap: load `collectionIds`, `activeCollectionId`, load active collection’s `requestOrder` + request files.
- [ ] `_persistCollectionsState` / `saveData` / `replaceActiveCollectionFromGit` persist via handler.
- [ ] Remove legacy flat-request migration paths that depended on Hive (`_initializeCollectionsStorage` Hive-only branches) — **POC: default empty → create default collection** if none.
- [ ] Update `test/providers/helpers.dart` to init file store + temp directory.

**Exit criteria:** Create/rename/switch collections, add/edit requests, restart app, data still there; **no Hive** calls in this provider.

---

### Phase 3 — Environments, workflows, history, Dashbot

**Goal:** All former Hive boxes **gone**.

**Deliverables:**

- [ ] `environment_providers.dart` — read/write `environments/` (+ per-collection `environments.json` for Git export rules).
- [ ] `workflow_providers.dart` + `workflow_page.dart` / `workflow_dashboard_analytics.dart` — `workflows/`.
- [ ] `history_providers.dart` + `history_service.dart` — `history/`.
- [ ] Dashbot persistence — `dashbot/messages.json` if still used.
- [ ] `removeUnused` / `clear` equivalents on file tree.

**Exit criteria:** Full app features work without opening Hive; **analyze** clean for Hive imports in these modules.

---

### Phase 4 — Git sync reads from filesystem

**Goal:** **GitHub snapshot** matches **disk**; **1 collection = 1 repo** unchanged.

**Deliverables:**

- [ ] `lib/services/git/git_sync_service.dart`: replace `_buildFilesFromHiveSnapshot` with **`_buildFilesFromLocalTree`** (or similar): after `saveData()`, read `collections/<activeId>/collection.json`, `environments.json`, `requests/*.json` into `Map<String, String>` **or** build from models loaded from disk — must match **`GitCollectionSerializer`** output paths.
- [ ] Manual: push → inspect GitHub tree; pull/import → local folder + providers updated.

**Exit criteria:** Push preview and push produce **identical structure** to pre-Hive behavior for the same models.

---

### Phase 5 — Remove Hive completely

**Goal:** Zero Hive dependency.

**Deliverables:**

- [ ] Delete `lib/services/hive_services.dart` (or leave empty shim only if tests need it — prefer delete).
- [ ] Remove `hive_ce_flutter` from `pubspec.yaml`.
- [ ] `main.dart` / `app.dart`: only `initFileSystemHandler`.
- [ ] Grep repo for `hive`, `Hive`, `hiveHandler` — zero in `lib/`.
- [ ] Fix all tests.

**Exit criteria:** `flutter analyze` / `flutter test` green; app runs on target platforms.

---

### Phase 6 — Documentation + polish

**Deliverables:**

- [ ] Update `doc/dev_guide/architecture.md` — persistence section.
- [ ] Short **developer note**: where `apidash_data` lives per OS / workspace.
- [ ] Optional: performance pass (history size, lazy load).

---

## 6. User review & platform notes

> [!IMPORTANT]
> **POC / no migration:** If users had Hive data, they may need a **fresh install** or **re-import from Git** unless a **migration phase** is added later.

> [!WARNING]
> **Web:** `dart:io` is unavailable. Ship **conditional** storage (IndexedDB / localStorage) or **defer web** for this POC. Desktop/mobile first is the usual path.

---

## 7. Verification

### Automated

- Unit tests for `FileSystemHandler` (paths, atomic write, JSON round-trip).
- Provider tests with mocked or temp-dir handler.
- Git serializer: golden or snapshot tests for `toGitFiles` from disk inputs (optional).

### Manual

1. **Collections:** Create two collections, add requests, switch, restart — data persists.
2. **Folder:** Open `apidash_data/collections/<id>/` — JSON readable; **`collection.json`** + **`requests/`** present.
3. **Git:** Connect repo, push, verify remote tree matches **GitCollectionPaths**.
4. **Import:** Import repo into new collection — sidebar matches.

---

## 8. Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Torn JSON on crash | Atomic temp + rename. |
| Drift memory vs disk | Single handler API; `saveData()` before Git operations. |
| Large history | Later: split meta/body or cap retention. |
| Web | Separate implementation or scope. |

---

## Appendix A — Hive → filesystem mapping (reference)

See detailed box-by-box mapping in git history if needed; summarized in **§4** above.

---

## Appendix B — File checklist (tracking)

- [ ] `lib/services/file_system_handler.dart` — **new**
- [ ] `lib/services/hive_services.dart` — **delete** (Phase 5)
- [ ] `lib/services/services.dart`
- [ ] `lib/services/git/git_sync_service.dart`
- [ ] `lib/main.dart`, `lib/app.dart`
- [ ] `lib/providers/collection_providers.dart`, `environment_providers.dart`, `workflow_providers.dart`, `history_providers.dart`
- [ ] `lib/services/history_service.dart`
- [ ] `lib/screens/workflow/workflow_page.dart`, `workflow_dashboard_analytics.dart`
- [ ] `pubspec.yaml`
- [ ] `test/providers/helpers.dart` + related tests
- [ ] `doc/dev_guide/architecture.md`

---

*Document version: 3.0 — full plan + phased build; POC: Hive removed entirely, 1 collection = 1 folder = 1 Git repo layout.*
