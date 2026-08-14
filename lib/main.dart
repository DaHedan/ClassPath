import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';

/// 当前《用户协议》版本号。
/// 协议内容变更时：同步修改这里的版本号与
/// assets/user_agreement.txt 顶部的更新日期，
/// 已同意过旧版本的手机端用户下次启动会再次要求确认。
const kAgreementVersion = '2026-08-14';

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
            home: app.loaded
                ? (!kIsWeb &&
                        Platform.isAndroid &&
                        app.settings.agreementVersion != kAgreementVersion)
                    ? _AgreementGate(app: app)
                    : const HomePage()
                : const _LoadingScreen(),
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

/// 手机端启动时按《用户协议》版本号判断是否需要确认：
/// 首次启动（从未同意）或协议已更新（版本号与当前不一致）时展示。
/// 点「同意并继续」持久化当前版本号后自动切换回主页；
/// 点「不同意并退出」直接关闭应用。
class _AgreementGate extends StatefulWidget {
  const _AgreementGate({required this.app});

  final AppState app;

  @override
  State<_AgreementGate> createState() => _AgreementGateState();
}

class _AgreementGateState extends State<_AgreementGate> {
  String? _text;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/user_agreement.txt').then((t) {
      if (mounted) setState(() => _text = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('用户协议')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '欢迎使用课途。请阅读并同意《用户协议》后继续使用。',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: _text == null
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: SelectableText(
                        _text!,
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => SystemNavigator.pop(),
                      child: const Text('不同意并退出'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => widget.app.updateSettings(
                        widget.app.settings
                            .copyWith(agreementVersion: kAgreementVersion),
                      ),
                      child: const Text('同意并继续'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
