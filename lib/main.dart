import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/app_state.dart';
import 'services/notification_service.dart';
import 'utils/app_theme.dart';
import 'screens/lock_screen.dart';
import 'screens/welcome_screen.dart';

/// 외부(.gido 파일 탭)로 진입 시 저장되는 파일 경로
/// HomeScreen initState에서 읽고 null로 초기화
String? pendingGidoFilePath;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // 알림 서비스 초기화 및 권한 요청
  final notificationService = NotificationService();
  await notificationService.initialize();
  await notificationService.requestPermissions();

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDark') ?? false;

  // .gido 파일로 앱이 열렸는지 확인
  try {
    const fileChannel = MethodChannel('com.gido.gido/file_handler');
    pendingGidoFilePath =
        await fileChannel.invokeMethod<String>('getInitialFilePath');
  } catch (_) {
    pendingGidoFilePath = null;
  }

  // 첫 실행 여부 확인 (PIN 설정 여부로 판단)
  const secureStorage = FlutterSecureStorage();
  final pin = await secureStorage.read(key: 'gido_pin');
  final isFirstRun = pin == null || pin.isEmpty;

  runApp(GidoApp(initialIsDark: isDark, isFirstRun: isFirstRun));
}

class ThemeNotifier extends ChangeNotifier {
  ThemeMode _themeMode;

  ThemeNotifier(bool isDark)
      : _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> toggle() async {
    _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', isDark);
    notifyListeners();
  }
}

class GidoApp extends StatelessWidget {
  final bool initialIsDark;
  final bool isFirstRun;
  const GidoApp({super.key, required this.initialIsDark, required this.isFirstRun});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => ThemeNotifier(initialIsDark)),
      ],
      child: Consumer<ThemeNotifier>(
        builder: (context, themeNotifier, child) {
          return MaterialApp(
            title: '기억 도우미',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.theme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeNotifier.themeMode,
            locale: const Locale('ko', 'KR'),
            supportedLocales: const [
              Locale('ko', 'KR'),
              Locale('en', 'US'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // 첫 실행(PIN 미설정)이면 환영 화면, 아니면 잠금 화면
            home: isFirstRun ? const WelcomeScreen() : const LockScreen(),
          );
        },
      ),
    );
  }
}