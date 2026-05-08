import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/profile.dart';
import 'config_builder.dart';

/// State machine for the local proxy.
///
/// Renamed from `ConnectionState` to avoid collision with the Flutter-built-in
/// type of the same name (used by `FutureBuilder` / `StreamBuilder`).
enum XrayState { disconnected, connecting, connected, failed }

/// Manages the bundled Xray-core sidecar process.
///
/// Responsibilities:
///   * Resolve the binary location: `<userAppData>/nst_tunnel/bin/xray.exe`
///     (or `xray` on macOS/Linux).
///   * Download the latest stable build from the official XTLS/Xray-core
///     GitHub releases on first run, with progress reporting.
///   * Write the generated config JSON to `<userAppData>/nst_tunnel/config.json`.
///   * Start / stop the process, capturing stdout/stderr to a ring buffer for
///     the in-app log viewer.
class XrayService extends ChangeNotifier {
  XrayService();

  Process? _process;
  XrayState _state = XrayState.disconnected;
  String? _lastError;
  Profile? _activeProfile;
  Directory? _appDir;
  final List<String> _logBuffer = <String>[];

  /// Tail of the last 500 stdout/stderr lines from xray.
  static const int _logCapacity = 500;

  XrayState get state => _state;
  bool get isRunning => _state == XrayState.connected;
  String? get lastError => _lastError;
  Profile? get activeProfile => _activeProfile;
  List<String> get log => List.unmodifiable(_logBuffer);

  /// Resolves and caches the per-user app directory. We only ever create files
  /// under here so uninstall is trivial.
  Future<Directory> _ensureAppDir() async {
    if (_appDir != null) return _appDir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'NSTTunnel'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    _appDir = dir;
    return dir;
  }

  Future<File> _binaryFile() async {
    final dir = await _ensureAppDir();
    final binDir = Directory(p.join(dir.path, 'bin'));
    if (!binDir.existsSync()) binDir.create(recursive: true);
    final exeName = Platform.isWindows ? 'xray.exe' : 'xray';
    return File(p.join(binDir.path, exeName));
  }

  Future<File> _configFile() async {
    final dir = await _ensureAppDir();
    return File(p.join(dir.path, 'config.json'));
  }

  /// True iff the Xray binary is already on disk and executable.
  Future<bool> isBinaryInstalled() async {
    final file = await _binaryFile();
    return file.existsSync() && file.lengthSync() > 0;
  }

  /// Downloads the latest stable Xray-core release archive for the host OS,
  /// extracts the executable into the app's bin directory, and returns the
  /// path. Calls [onProgress] with bytes-received / total during the download.
  ///
  /// Throws on network failure or unsupported platform.
  Future<String> installBinary({
    void Function(double progress)? onProgress,
  }) async {
    final assetName = _xrayAssetName();
    if (assetName == null) {
      throw UnsupportedError('Unsupported host platform: ${Platform.operatingSystem}');
    }

    // 1. Look up the latest release.
    final releaseRes = await http.get(
      Uri.parse('https://api.github.com/repos/XTLS/Xray-core/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (releaseRes.statusCode != 200) {
      throw HttpException('GitHub releases API returned ${releaseRes.statusCode}');
    }
    final release = jsonDecode(releaseRes.body) as Map<String, dynamic>;
    final assets = (release['assets'] as List).cast<Map<String, dynamic>>();
    final asset = assets.firstWhere(
      (a) => a['name'] == assetName,
      orElse: () => throw StateError('Asset $assetName not found in latest release'),
    );
    final downloadUrl = asset['browser_download_url'] as String;

    // 2. Stream the zip to a temp file with progress.
    final dir = await _ensureAppDir();
    final tmp = File(p.join(dir.path, 'xray-download.zip'));
    if (tmp.existsSync()) tmp.deleteSync();

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(downloadUrl));
      final res = await client.send(req);
      final total = res.contentLength ?? 0;
      var received = 0;
      final sink = tmp.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }

    // 3. Extract just the xray executable.
    await _extractXrayExe(tmp, dir);
    if (tmp.existsSync()) tmp.deleteSync();
    final binFile = await _binaryFile();
    if (!binFile.existsSync()) {
      throw StateError('Extraction succeeded but xray binary not found at ${binFile.path}');
    }
    if (!Platform.isWindows) {
      // Make it executable.
      await Process.run('chmod', ['+x', binFile.path]);
    }
    return binFile.path;
  }

  /// Maps the host platform to the GitHub release asset name shipped by
  /// XTLS/Xray-core.  These names are stable across recent releases.
  String? _xrayAssetName() {
    if (Platform.isWindows) return 'Xray-windows-64.zip';
    if (Platform.isMacOS) {
      return Platform.version.contains('arm64')
          ? 'Xray-macos-arm64-v8a.zip'
          : 'Xray-macos-64.zip';
    }
    if (Platform.isLinux) return 'Xray-linux-64.zip';
    return null;
  }

  /// Pulls the `xray(.exe)` entry out of the release zip and writes it into
  /// the bin/ folder. Uses Windows-friendly `tar` (built into Win10+) on
  /// Windows and `unzip` elsewhere — both are guaranteed available.
  Future<void> _extractXrayExe(File zipFile, Directory appDir) async {
    final binDir = Directory(p.join(appDir.path, 'bin'));
    if (Platform.isWindows) {
      // tar.exe ships with Windows 10 1803+ and handles .zip natively.
      final result = await Process.run(
        'tar',
        ['-xf', zipFile.path, '-C', binDir.path, 'xray.exe'],
      );
      if (result.exitCode != 0) {
        throw StateError('tar failed: ${result.stderr}');
      }
    } else {
      final result = await Process.run(
        'unzip',
        ['-o', zipFile.path, 'xray', '-d', binDir.path],
      );
      if (result.exitCode != 0) {
        throw StateError('unzip failed: ${result.stderr}');
      }
    }
  }

  /// Starts the local proxy with the given [profile].
  ///
  /// Idempotent: if it's already running with the same profile, this is a
  /// no-op; otherwise it stops the current process before starting fresh.
  Future<void> connect(Profile profile) async {
    if (_state == XrayState.connecting) return;

    if (!await isBinaryInstalled()) {
      _setState(XrayState.failed, error: 'Xray binary is missing — install it from Settings.');
      return;
    }

    if (isRunning && _activeProfile?.id == profile.id) return;
    if (_process != null) {
      await disconnect();
    }

    _setState(XrayState.connecting);

    try {
      // Write the freshly built config to disk.
      final configFile = await _configFile();
      final cfg = XrayConfigBuilder.build(profile);
      await configFile.writeAsString(const JsonEncoder.withIndent('  ').convert(cfg));

      final binFile = await _binaryFile();
      _process = await Process.start(
        binFile.path,
        ['run', '-c', configFile.path],
        workingDirectory: (await _ensureAppDir()).path,
        // On Windows, hide the console window of the child process. flutter desktop
        // launches without a console; child processes default to inheriting any
        // console that exists, so explicitly detach.
        mode: ProcessStartMode.detachedWithStdio,
      );

      _process!.stdout.transform(utf8.decoder).listen(_onLog);
      _process!.stderr.transform(utf8.decoder).listen(_onLog);
      unawaited(
        _process!.exitCode.then((code) {
          _appendLog('[xray exited with code $code]');
          if (_state == XrayState.connected) {
            _setState(XrayState.failed,
                error: 'Xray process exited unexpectedly (code $code)');
          }
          _process = null;
        }),
      );

      // Heuristic: if we haven't crashed within 600 ms, consider it up.
      // Xray prints listener info on startup which we capture in _onLog.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (_process != null) {
        _activeProfile = profile;
        _setState(XrayState.connected);
      }
    } catch (e, st) {
      debugPrint('XrayService.connect failed: $e\n$st');
      _setState(XrayState.failed, error: e.toString());
    }
  }

  Future<void> disconnect() async {
    if (_process == null) {
      _setState(XrayState.disconnected);
      return;
    }
    try {
      _process!.kill(ProcessSignal.sigterm);
      // Give it half a second to exit gracefully, then force-kill.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _process?.kill(ProcessSignal.sigkill);
    } catch (_) {
      // ignore — best-effort
    }
    _process = null;
    _activeProfile = null;
    _setState(XrayState.disconnected);
  }

  void _onLog(String chunk) {
    for (final line in chunk.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      _appendLog(trimmed);
    }
  }

  void _appendLog(String line) {
    _logBuffer.add(line);
    if (_logBuffer.length > _logCapacity) {
      _logBuffer.removeRange(0, _logBuffer.length - _logCapacity);
    }
    notifyListeners();
  }

  void _setState(XrayState state, {String? error}) {
    _state = state;
    _lastError = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _process?.kill(ProcessSignal.sigkill);
    super.dispose();
  }
}
