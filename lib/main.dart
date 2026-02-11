import 'package:chat_app/screens/splash.dart';
import 'package:flutter/material.dart';
import 'package:chat_app/screens/auth.dart';
import 'package:chat_app/widgets/navigation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:chat_app/services/local_storage_service.dart'; 


var kColorScheme = ColorScheme.fromSeed(
  seedColor: const Color.fromRGBO(255, 109, 77, 1.0),
);

void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "PRIVATE.env");
  await Hive.initFlutter();
  await LocalStorageService().init(); 
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!, 
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    debug: false,
  );

  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return MaterialApp(
      debugShowCheckedModeBanner: false,

      theme: ThemeData().copyWith(
        colorScheme: kColorScheme,
        scaffoldBackgroundColor: kColorScheme.background,
        appBarTheme: AppBarTheme(
          backgroundColor: kColorScheme.surfaceContainerLowest,
          foregroundColor: const Color.fromRGBO(255, 109, 77, 1.0),
          elevation: 0,
        ),
        textTheme: ThemeData().textTheme.copyWith(
          titleLarge: TextStyle(
            fontWeight: FontWeight.bold,
            color: kColorScheme.onPrimary,
            fontSize: 40.0,
          ),
          bodyMedium: TextStyle(
            fontWeight: FontWeight.bold,
            color: const Color.fromRGBO(255, 109, 77, 1.0),
            fontSize: 20.0,
          ),
          bodySmall: TextStyle(
            color: kColorScheme.onPrimary,
            fontSize: 14.0,
          ),
          bodyLarge: TextStyle(
            color: Colors.black,
            fontSize: 18.0,
            fontWeight: FontWeight.w600,
          ),  
        ),

      ),

      home: FutureBuilder(
        future: Future.delayed(const Duration(seconds: 5)), // Always show splash first
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SplashScreen();
          }
          return StreamBuilder<AuthState>(
            stream: authService.onAuthStateChange,
            builder: (context, snapshot) {
              final session = authService.currentSession;
              if (session != null) {
                return const Navigation();
              } else {
                return const AuthScreen();
              }
            },
          );
        },
      ),
    );
  }
}