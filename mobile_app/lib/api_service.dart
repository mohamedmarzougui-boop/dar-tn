import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // 127.0.0.1 works seamlessly across Chrome and Desktop
  static const String baseUrl = 'http://127.0.0.1:5000/api';

  static Future<List<dynamic>> fetchMapListings({
    double minLat = 34.0,
    double minLng = 8.0,
    double maxLat = 38.0,
    double maxLng = 12.0,
  }) async {
    final url = Uri.parse(
      '$baseUrl/listings/map?min_lat=$minLat&min_lng=$minLng&max_lat=$maxLat&max_lng=$maxLng',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['listings'] ?? [];
      } else {
        return [];
      }
    } catch (e) {
      print('Network Error: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> fetchListingDetails(String id) async {
    final url = Uri.parse('$baseUrl/listings/$id');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load listing details');
    }
  }
}