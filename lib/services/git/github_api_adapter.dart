import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class DeviceFlowResponse {
  const DeviceFlowResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;
}

class GitHubApiException implements Exception {
  GitHubApiException({
    required this.statusCode,
    required this.message,
    this.body,
  });

  final int statusCode;
  final String message;
  final String? body;

  @override
  String toString() =>
      'GitHubApiException(statusCode: $statusCode, message: $message, body: $body)';
}

class RepoInfo {
  const RepoInfo({
    required this.owner,
    required this.name,
    required this.fullName,
    required this.defaultBranch,
    required this.private,
  });

  final String owner;
  final String name;
  final String fullName;
  final String defaultBranch;
  final bool private;
}

class BranchInfo {
  const BranchInfo({
    required this.name,
    required this.sha,
    this.protected = false,
  });

  final String name;
  final String sha;
  final bool protected;
}

class CommitInfo {
  const CommitInfo({
    required this.sha,
    required this.message,
    this.authorName,
    this.authorEmail,
    this.date,
    required this.treeSha,
  });

  final String sha;
  final String message;
  final String? authorName;
  final String? authorEmail;
  final DateTime? date;
  final String treeSha;
}

class PullResult {
  const PullResult({
    required this.commitSha,
    required this.files,
  });

  final String commitSha;
  final Map<String, String> files;
}

class GitHubApiAdapter {
  GitHubApiAdapter({
    FlutterSecureStorage? storage,
    http.Client? httpClient,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _httpClient = httpClient ?? http.Client();

  static const String clientId = 'Ov23lisXbdRM4Sc4wwe1';

  static const String _baseUrl = 'https://api.github.com';
  static const String _authUrl = 'https://github.com';
  static const String _tokenKey = 'apidash_github_access_token';
  static const String _fallbackTokenKey = 'apidash_github_access_token_fallback';

  final FlutterSecureStorage _storage;
  final http.Client _httpClient;

  String _scopes = 'repo workflow';

  Future<bool> isAuthenticated() async {
    final token = await _readToken();
    return token != null && token.isNotEmpty;
  }

  Future<String?> getToken() async {
    return _readToken();
  }

  Future<void> setToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) return;
    await _writeToken(normalized);
  }

  Future<void> ensureRequiredScopes() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      throw GitHubApiException(statusCode: 401, message: 'Not authenticated');
    }
    final response = await _httpClient.get(
      Uri.parse('$_baseUrl/user'),
      headers: _authHeaders(token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GitHubApiException(
        statusCode: response.statusCode,
        message: 'Unable to verify GitHub token scopes',
        body: response.body,
      );
    }
    final rawScopes = response.headers['x-oauth-scopes'] ?? '';
    final scopes = rawScopes
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    if (!scopes.contains('repo') || !scopes.contains('workflow')) {
      throw GitHubApiException(
        statusCode: 403,
        message:
            'GitHub token is missing required scopes (repo, workflow). Remove saved auth and reconnect.',
        body: 'granted_scopes=$rawScopes',
      );
    }
  }

  Future<void> clearToken() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_fallbackTokenKey);
  }

  Future<String> authenticateWithDeviceFlow({
    required void Function(String userCode, String verificationUri) onShowCode,
    bool autoOpenBrowser = true,
  }) async {
    final device = await _startDeviceFlow();
    onShowCode(device.userCode, device.verificationUri);
    if (autoOpenBrowser) {
      await openVerificationUrl(device.verificationUri);
    }

    final expiry = DateTime.now().add(Duration(seconds: device.expiresIn));
    var pollIntervalSec = device.interval + 1;
    while (DateTime.now().isBefore(expiry)) {
      await Future.delayed(Duration(seconds: pollIntervalSec));
      final poll = await _pollForToken(device.deviceCode);
      if (poll.shouldSlowDown) {
        pollIntervalSec += 2;
      }
      final token = poll.token;
      if (token != null) return token;
    }

    throw GitHubApiException(
      statusCode: 408,
      message: 'GitHub authorization timed out',
    );
  }

  Future<DeviceFlowResponse> _startDeviceFlow() async {
    final resolvedClientId = _requireClientId();
    final response = await _httpClient.post(
      Uri.parse('$_authUrl/login/device/code'),
      headers: {'Accept': 'application/json'},
      body: {
        'client_id': resolvedClientId,
        'scope': _scopes,
      },
    );

    if (response.statusCode != 200) {
      throw GitHubApiException(
        statusCode: response.statusCode,
        message: 'Failed to start device flow',
        body: response.body,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return DeviceFlowResponse(
      deviceCode: data['device_code'] as String,
      userCode: data['user_code'] as String,
      verificationUri: data['verification_uri'] as String,
      expiresIn: data['expires_in'] as int,
      interval: data['interval'] as int,
    );
  }

  Future<_PollTokenResult> _pollForToken(String deviceCode) async {
    final resolvedClientId = _requireClientId();
    final response = await _httpClient.post(
      Uri.parse('$_authUrl/login/oauth/access_token'),
      headers: {'Accept': 'application/json'},
      body: {
        'client_id': resolvedClientId,
        'device_code': deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      },
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final error = data['error'] as String?;
    if (error == 'authorization_pending') {
      return const _PollTokenResult(token: null, shouldSlowDown: false);
    }
    if (error == 'slow_down') {
      return const _PollTokenResult(token: null, shouldSlowDown: true);
    }
    if (error == 'expired_token') {
      throw GitHubApiException(
        statusCode: 401,
        message: 'GitHub authorization expired',
      );
    }
    if (error == 'access_denied') {
      throw GitHubApiException(
        statusCode: 403,
        message: 'GitHub authorization denied',
      );
    }
    if (error != null) {
      final description = data['error_description'] as String?;
      throw GitHubApiException(
        statusCode: 400,
        message: description == null || description.isEmpty
            ? 'GitHub authorization failed: $error'
            : 'GitHub authorization failed: $description',
        body: response.body,
      );
    }

    final token = data['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw GitHubApiException(
        statusCode: 400,
        message: 'GitHub authorization failed: no access token received',
        body: response.body,
      );
    }

    await _writeToken(token);
    return _PollTokenResult(token: token, shouldSlowDown: false);
  }

  Future<void> openVerificationUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<String?> _readToken() async {
    try {
      final secure = await _storage.read(key: _tokenKey);
      if (secure != null && secure.isNotEmpty) return secure;
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_fallbackTokenKey);
  }

  Future<void> _writeToken(String token) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
      return;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fallbackTokenKey, token);
    }
  }

  Map<String, String> _authHeaders(String token) => <String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Future<dynamic> _authedRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      throw GitHubApiException(statusCode: 401, message: 'Not authenticated');
    }

    final uri = Uri.parse('$_baseUrl$path');
    final headers = _authHeaders(token);

    http.Response response;
    switch (method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: headers);
        break;
      case 'POST':
        headers['Content-Type'] = 'application/json';
        response = await _httpClient.post(uri, headers: headers, body: jsonEncode(body));
        break;
      case 'PATCH':
        headers['Content-Type'] = 'application/json';
        response = await _httpClient.patch(uri, headers: headers, body: jsonEncode(body));
        break;
      case 'DELETE':
        response = await _httpClient.delete(uri, headers: headers);
        break;
      case 'PUT':
        headers['Content-Type'] = 'application/json';
        response = await _httpClient.put(uri, headers: headers, body: jsonEncode(body));
        break;
      default:
        throw GitHubApiException(statusCode: 400, message: 'Unknown HTTP method $method');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.statusCode == 204) return null;
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    throw GitHubApiException(
      statusCode: response.statusCode,
      message: _extractGitHubErrorMessage(response.body),
      body: response.body,
    );
  }

  String _extractGitHubErrorMessage(String body) {
    if (body.trim().isEmpty) return 'GitHub API request failed';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'] as String?;
        final errors = decoded['errors'];
        if (errors is List && errors.isNotEmpty) {
          final first = errors.first;
          if (first is Map<String, dynamic>) {
            final code = first['code']?.toString();
            final field = first['field']?.toString();
            final errMsg = first['message']?.toString();
            final details = [
              if (code != null && code.isNotEmpty) code,
              if (field != null && field.isNotEmpty) field,
              if (errMsg != null && errMsg.isNotEmpty) errMsg,
            ].join(': ');
            if (message != null && message.isNotEmpty) {
              return details.isEmpty ? message : '$message ($details)';
            }
          }
        }
        if (message != null && message.isNotEmpty) return message;
      }
    } catch (_) {}
    return 'GitHub API request failed';
  }

  Future<String> getCurrentUserLogin() async {
    final res = await _authedRequest('GET', '/user');
    return (res as Map<String, dynamic>)['login'] as String;
  }

  Future<RepoInfo> getRepository(String owner, String repo) async {
    final res = await _authedRequest('GET', '/repos/$owner/$repo');
    final map = res as Map<String, dynamic>;
    return RepoInfo(
      owner: map['owner']['login'] as String,
      name: map['name'] as String,
      fullName: map['full_name'] as String,
      defaultBranch: (map['default_branch'] as String?) ?? 'main',
      private: map['private'] as bool,
    );
  }

  Future<RepoInfo> createRepository({
    required String name,
    String? description,
    bool private = true,
  }) async {
    final res = await _authedRequest(
      'POST',
      '/user/repos',
      body: <String, dynamic>{
        'name': name,
        'description': description ?? 'API Dash collection',
        'private': private,
        'auto_init': false,
      },
    );
    final map = res as Map<String, dynamic>;
    return RepoInfo(
      owner: map['owner']['login'] as String,
      name: map['name'] as String,
      fullName: map['full_name'] as String,
      defaultBranch: (map['default_branch'] as String?) ?? 'main',
      private: map['private'] as bool,
    );
  }

  Future<String> getBranchHeadSha({
    required String owner,
    required String repo,
    required String branch,
  }) async {
    final res = await _authedRequest(
      'GET',
      '/repos/$owner/$repo/git/refs/heads/$branch',
    );
    final map = res as Map<String, dynamic>;
    return (map['object'] as Map<String, dynamic>)['sha'] as String;
  }

  Future<List<BranchInfo>> listBranches({
    required String owner,
    required String repo,
  }) async {
    final res = await _authedRequest('GET', '/repos/$owner/$repo/branches');
    final list = res as List<dynamic>;
    return list
        .map((e) {
          final map = e as Map<String, dynamic>;
          return BranchInfo(
            name: map['name'] as String,
            sha: (map['commit'] as Map<String, dynamic>)['sha'] as String,
            protected: (map['protected'] as bool?) ?? false,
          );
        })
        .toList();
  }

  Future<void> createBranch({
    required String owner,
    required String repo,
    required String branchName,
    required String fromSha,
  }) async {
    await _authedRequest(
      'POST',
      '/repos/$owner/$repo/git/refs',
      body: <String, dynamic>{
        'ref': 'refs/heads/$branchName',
        'sha': fromSha,
      },
    );
  }

  Future<void> deleteBranch({
    required String owner,
    required String repo,
    required String branchName,
  }) async {
    await _authedRequest(
      'DELETE',
      '/repos/$owner/$repo/git/refs/heads/$branchName',
    );
  }

  Future<List<CommitInfo>> getCommitHistory({
    required String owner,
    required String repo,
    required String branch,
    int perPage = 30,
  }) async {
    final res = await _authedRequest(
      'GET',
      '/repos/$owner/$repo/commits?sha=$branch&per_page=$perPage',
    );
    final list = res as List<dynamic>;
    return Future.wait(
      list.map((e) async {
        final map = e as Map<String, dynamic>;
        final sha = map['sha'] as String;
        final commit = map['commit'] as Map<String, dynamic>;
        final author = commit['author'] as Map<String, dynamic>?;
        return CommitInfo(
          sha: sha,
          message: commit['message'] as String,
          authorName: author?['name'] as String?,
          authorEmail: author?['email'] as String?,
          date: author?['date'] != null ? DateTime.parse(author!['date'] as String) : null,
          treeSha: await _getTreeShaForCommit(owner: owner, repo: repo, commitSha: sha),
        );
      }),
    );
  }

  Future<String> _getTreeShaForCommit({
    required String owner,
    required String repo,
    required String commitSha,
  }) async {
    final res = await _authedRequest(
      'GET',
      '/repos/$owner/$repo/git/commits/$commitSha',
    );
    final map = res as Map<String, dynamic>;
    return (map['tree'] as Map<String, dynamic>)['sha'] as String;
  }

  Future<PullResult> pullCollectionAtBranchHead({
    required String owner,
    required String repo,
    required String branch,
  }) async {
    final headSha = await getBranchHeadSha(owner: owner, repo: repo, branch: branch);
    return pullCollectionAtCommit(owner: owner, repo: repo, commitSha: headSha);
  }

  Future<PullResult> pullCollectionAtCommit({
    required String owner,
    required String repo,
    required String commitSha,
  }) async {
    final treeSha = await _getTreeShaForCommit(owner: owner, repo: repo, commitSha: commitSha);
    final tree = await _authedRequest(
      'GET',
      '/repos/$owner/$repo/git/trees/$treeSha?recursive=1',
    );

    final files = <String, String>{};
    final treeMap = tree as Map<String, dynamic>;
    final items = treeMap['tree'] as List<dynamic>;
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final path = map['path'] as String?;
      if (path == null) continue;
      final type = map['type'] as String?;
      if (type != 'blob') continue;
      if (path != 'collection.json' &&
          path != 'environments.json' &&
          !(path.startsWith('requests/') && path.endsWith('.json'))) {
        continue;
      }
      final blobSha = map['sha'] as String;
      final blob = await _authedRequest(
        'GET',
        '/repos/$owner/$repo/git/blobs/$blobSha',
      );
      final blobMap = blob as Map<String, dynamic>;
      final encoding = blobMap['encoding'] as String?;
      final content = blobMap['content'] as String;
      final decoded = encoding == 'base64'
          ? utf8.decode(base64.decode(content.replaceAll('\n', '')))
          : content;
      files[path] = decoded;
    }

    return PullResult(commitSha: commitSha, files: files);
  }

  Future<String> pushFiles({
    required String owner,
    required String repo,
    required String branch,
    required Map<String, String> files,
    required String commitMessage,
  }) async {
    Future<String> doPush(Map<String, String> inputFiles) async {
      String? parentSha;
      try {
        parentSha = await getBranchHeadSha(owner: owner, repo: repo, branch: branch);
      } on GitHubApiException catch (e) {
        if (e.statusCode != 404 && e.statusCode != 409) rethrow;
        parentSha = null;
      }

      if (parentSha == null) {
        await _bootstrapEmptyRepoWithContentsApi(
          owner: owner,
          repo: repo,
          branch: branch,
        );
        try {
          parentSha = await getBranchHeadSha(owner: owner, repo: repo, branch: branch);
        } on GitHubApiException catch (e) {
          if (e.statusCode != 404 && e.statusCode != 409) rethrow;
          final repoInfo = await getRepository(owner, repo);
          final defaultHead = await getBranchHeadSha(
            owner: owner,
            repo: repo,
            branch: repoInfo.defaultBranch,
          );
          if (branch != repoInfo.defaultBranch) {
            await createBranch(
              owner: owner,
              repo: repo,
              branchName: branch,
              fromSha: defaultHead,
            );
          }
          parentSha = await getBranchHeadSha(owner: owner, repo: repo, branch: branch);
        }
      }

      final parentCommit = await _authedRequest(
        'GET',
        '/repos/$owner/$repo/git/commits/$parentSha',
      );
      final parentMap = parentCommit as Map<String, dynamic>;
      final baseTreeSha = (parentMap['tree'] as Map<String, dynamic>)['sha'] as String;

      final existingTree = await _authedRequest(
        'GET',
        '/repos/$owner/$repo/git/trees/$baseTreeSha?recursive=1',
      );
      final existingItems =
          (existingTree as Map<String, dynamic>)['tree'] as List<dynamic>? ??
              const <dynamic>[];
      final existingManagedPaths = existingItems
          .whereType<Map<String, dynamic>>()
          .where((item) {
            final type = item['type'] as String?;
            final path = item['path'] as String?;
            if (type != 'blob' || path == null) return false;
            return path == 'collection.json' ||
                path == 'environments.json' ||
                path == '.apidash-bootstrap' ||
                (path.startsWith('requests/') && path.endsWith('.json'));
          })
          .map((item) => item['path'] as String)
          .toSet();

      final treeItems = <Map<String, dynamic>>[];
      for (final entry in inputFiles.entries) {
        final blob = await _authedRequest(
          'POST',
          '/repos/$owner/$repo/git/blobs',
          body: <String, dynamic>{
            'content': entry.value,
            'encoding': 'utf-8',
          },
        );
        final blobMap = blob as Map<String, dynamic>;
        treeItems.add(<String, dynamic>{
          'path': entry.key,
          'mode': '100644',
          'type': 'blob',
          'sha': blobMap['sha'] as String,
        });
      }

      for (final path in existingManagedPaths) {
        if (!inputFiles.containsKey(path)) {
          treeItems.add(<String, dynamic>{
            'path': path,
            'mode': '100644',
            'type': 'blob',
            'sha': null,
          });
        }
      }

      final treeResponse = await _authedRequest(
        'POST',
        '/repos/$owner/$repo/git/trees',
        body: <String, dynamic>{
          'base_tree': baseTreeSha,
          'tree': treeItems,
        },
      );
      final treeMap = treeResponse as Map<String, dynamic>;
      final newTreeSha = treeMap['sha'] as String;

      final commitResponse = await _authedRequest(
        'POST',
        '/repos/$owner/$repo/git/commits',
        body: <String, dynamic>{
          'message': commitMessage,
          'tree': newTreeSha,
          'parents': [parentSha],
        },
      );
      final commitMap = commitResponse as Map<String, dynamic>;
      final newCommitSha = commitMap['sha'] as String;

      await _authedRequest(
        'PATCH',
        '/repos/$owner/$repo/git/refs/heads/$branch',
        body: <String, dynamic>{
          'sha': newCommitSha,
        },
      );

      return newCommitSha;
    }

    return doPush(files);
  }

  Future<void> _bootstrapEmptyRepoWithContentsApi({
    required String owner,
    required String repo,
    required String branch,
  }) async {
    final seedPath = '.apidash-bootstrap';
    final seedContent = base64.encode(
      utf8.encode('Bootstrapped by API Dash\n'),
    );
    await _authedRequest(
      'PUT',
      '/repos/$owner/$repo/contents/$seedPath',
      body: <String, dynamic>{
        'message': 'Bootstrap repository',
        'content': seedContent,
        'branch': branch,
      },
    );
  }

  String _requireClientId() {
    if (clientId.trim().isNotEmpty) return clientId.trim();
    throw GitHubApiException(
      statusCode: 400,
      message:
          'GitHub OAuth client id is missing. Pass --dart-define=APIDASH_GITHUB_CLIENT_ID=<client-id>.',
    );
  }
}

class _PollTokenResult {
  const _PollTokenResult({
    required this.token,
    required this.shouldSlowDown,
  });

  final String? token;
  final bool shouldSlowDown;
}

