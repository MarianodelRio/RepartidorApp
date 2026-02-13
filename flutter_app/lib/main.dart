import 'package:flutter/material.dart';
import 'config/app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/persistence_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PersistenceService.init();
  runApp(const RepartirApp());
}

class RepartirApp extends StatelessWidget {
  const RepartirApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Repartidor',
      debugShowCheckedModeBanner: false,
      theme: appLightTheme,
      darkTheme: appDarkTheme,
      themeMode: ThemeMode.system, // Modo oscuro automático
      home: const SplashScreen(),
    );
  }
}
