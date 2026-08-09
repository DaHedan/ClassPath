import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';

/// 课途 ClassPath —— 多端课程表软件。
///
/// 数据完全存储在本地（SharedPreferences），不做登录。
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(const ClassPathApp());
}

class ClassPathApp extends StatefulWidget {
  const ClassPathApp({super.key});

  @override
  State<ClassPathApp> createState() => _ClassPathAppState();
}

class _ClassPathAppState extends State<ClassPathApp> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..load(),
      child: Consumer<AppState>(
        builder: (context, app, _) {
          return MaterialApp(
            title: '课途 ClassPath',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF5B8DEF)),
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF5B8DEF),
                  brightness: Brightness.dark),
            ),
            themeMode: app.settings.themeMode,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: app.loaded ? const HomePage() : const _LoadingScreen(),
          );
        },
      ),
    );
  }
}

/// 数据加载完成前的启动画面。
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
