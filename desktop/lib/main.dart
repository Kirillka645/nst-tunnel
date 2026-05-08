import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'data/profile_repository.dart';
import 'service/xray_service.dart';
import 'theme/app_theme.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sensible default window size on desktop platforms. Phone/tablet builds
  // (which we don't ship for now) skip this entirely.
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      size: Size(900, 640),
      minimumSize: Size(560, 420),
      title: 'NST Tunnel',
      backgroundColor: Color(0xFF15140F), // matches dark theme surface
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final prefs = await SharedPreferences.getInstance();
  final repo = ProfileRepository(prefs);
  final xray = XrayService();

  runApp(NstTunnelApp(repo: repo, xray: xray));
}

class NstTunnelApp extends StatelessWidget {
  const NstTunnelApp({
    super.key,
    required this.repo,
    required this.xray,
  });

  final ProfileRepository repo;
  final XrayService xray;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileRepository>.value(value: repo),
        ChangeNotifierProvider<XrayService>.value(value: xray),
      ],
      child: MaterialApp(
        title: 'NST Tunnel',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
