import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AiService {
  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';
  static String get _apiUrl => dotenv.env['GEMINI_API_URL'] ?? '';

  /// Sends a message to the Gemini API and returns the response text.
  Future<String> sendMessage(String message) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiUrl?key=$_apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': message}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          return data['candidates'][0]['content']['parts'][0]['text'];
        } else {
          return 'Sorry, I couldn\'t generate a response.';
        }
      } else {
        print('API Error: ${response.statusCode} - ${response.body}');
        return 'API Error: ${response.statusCode}. Please check your API key.';
      }
    } catch (e) {
      print('Network Error: $e');
      return 'Network error. Please check your internet connection.';
    }
  }
}