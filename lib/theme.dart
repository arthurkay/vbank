// Common style properties for both themes
import 'package:flutter/material.dart';

const String fontFamily = 'Montserrat';

// New Monochromatic / Shadcn-inspired palette
const Color lightBase = Color(0xFFFFFFFF);
const Color darkBase = Color(0xFF09090B); // Near black
const Color darkCard = Color(0xFF1F1F1F); // Darker gray for cards
const Color lightText = Color(0xFF09090B);
const Color darkText = Color(0xFFFAFAFA);
// A subtle, modern blue accent for Growth visualization (maintaining clarity)
const Color growthAccent = Color(0xFF007AFF);

ThemeData lightTheme() {
  return ThemeData(
    brightness: Brightness.light,
    primaryColor: lightText,
    scaffoldBackgroundColor: lightBase,
    cardColor: lightBase,
    fontFamily: fontFamily,
    appBarTheme: const AppBarTheme(
      color: lightBase,
      elevation: 0,
      iconTheme: IconThemeData(color: lightText),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12.0)),
        borderSide: BorderSide(color: Color(0xFFE0E0E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12.0)),
        borderSide: BorderSide(color: growthAccent, width: 2),
      ),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: lightText),
      titleLarge: TextStyle(color: lightText),
      bodyMedium: TextStyle(color: lightText),
    ),
    useMaterial3: true,
  );
}

ThemeData darkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    primaryColor: darkText,
    scaffoldBackgroundColor: darkBase,
    cardColor: darkCard,
    fontFamily: fontFamily,
    appBarTheme: const AppBarTheme(
      color: darkBase,
      elevation: 0,
      iconTheme: IconThemeData(color: darkText),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12.0)),
        borderSide: BorderSide(color: Color(0xFF333333)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12.0)),
        borderSide: BorderSide(color: growthAccent, width: 2),
      ),
      labelStyle: TextStyle(color: Color(0xFFFAFAFA)),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: darkText),
      titleLarge: TextStyle(color: darkText),
      bodyMedium: TextStyle(color: darkText),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: darkCard,
      selectedItemColor: growthAccent,
      unselectedItemColor: Color(0xFF6B6B6B),
    ),
    useMaterial3: true,
  );
}
