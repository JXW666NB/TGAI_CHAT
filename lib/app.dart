import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'domain/providers/chat_provider.dart';
import 'domain/providers/models_provider.dart';
import 'domain/providers/settings_provider.dart';
import 'presentation/screens/home_screen.dart';

class TgChatApp extends StatelessWidget {
  const TgChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeNotifier()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()..init()),
        ChangeNotifierProvider(create: (_) => ModelsProvider()..load()),
        ChangeNotifierProvider(create: (_) => ChatProvider()..init()),
      ],
      child: Consumer<ThemeNotifier>(
        builder: (context, theme, _) => MaterialApp(
          title: 'TG CHAT',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme.mode,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
