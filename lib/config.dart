import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String _keyBaseUrl = 'user_base_url';
  
  // URL Default awal (bisa diubah dari menu Settings)
  static String baseUrl = 'https://rare-olives-give.loca.lt';

  // Memuat URL yang tersimpan dari memori lokal
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_keyBaseUrl) ?? baseUrl;
  }

  // Menyimpan URL baru dari Pengaturan
  static Future<void> setBaseUrl(String newUrl) async {
    String cleanUrl = newUrl.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    
    baseUrl = cleanUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, cleanUrl);
  }

  // Header wajib untuk menembus proteksi LocalTunnel / ngrok
  static Map<String, String> get headers => {
        'bypass-tunnel-reminder': 'true',
        'ngrok-skip-browser-warning': 'true',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
}