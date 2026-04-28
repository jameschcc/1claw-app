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

    // Connect on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wsService.connect();

      // Load default profiles if no server response
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          final profilesProvider = context.read<ProfilesProvider>();
          if (profilesProvider.profiles.isEmpty) {
            profilesProvider.loadDefaultProfiles();
          }
        }
      });
    });
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
      child: MaterialApp(
        title: '1Claw',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const HomeScreen(),
      ),
    );
  }
}
