import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'providers/chat_provider.dart';
import 'providers/profiles_provider.dart';
import 'screens/home_screen.dart';
import 'services/websocket_service.dart';

/// Root 1Claw application widget.
/// Sets up providers, theme, and navigation.
class ClawApp extends StatefulWidget {
  const ClawApp({super.key});

  @override
  State<ClawApp> createState() => _ClawAppState();
}

class _ClawAppState extends State<ClawApp> {
  late final WebSocketService _wsService;

  @override
  void initState() {
    super.initState();
    _wsService = WebSocketService();
    _wsService.connect();
  }

  @override
  void dispose() {
    _wsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ProfilesProvider(_wsService),
        ),
        ChangeNotifierProvider(
          create: (_) => ChatProvider(_wsService),
        ),
      ],
      child: _AppStartup(
        child: MaterialApp(
          title: '1Claw',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}

/// Runs startup logic (connect, default profiles) from within the provider
/// subtree so `context.read<ProfilesProvider>()` can find the provider.
class _AppStartup extends StatefulWidget {
  final Widget child;
  const _AppStartup({required this.child});

  @override
  State<_AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<_AppStartup> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profilesProvider = context.read<ProfilesProvider>();

      // Load default profiles if no server response after timeout
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && profilesProvider.profiles.isEmpty) {
          profilesProvider.loadDefaultProfiles();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
