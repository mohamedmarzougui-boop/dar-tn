import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:5000/api';
  static const _storage = FlutterSecureStorage();

  // --- AUTHENTICATION ---

  static Future<void> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      await _storage.write(key: 'jwt_token', value: data['token']);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['error'] ?? 'Login failed');
    }
  }

  static Future<void> register(String fullName, String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'full_name': fullName, 'email': email, 'password': password}),
    );

    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      await _storage.write(key: 'jwt_token', value: data['token']);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['error'] ?? 'Registration failed');
    }
  }

  static Future<void> logout() async {
    await _storage.delete(key: 'jwt_token');
  }

  static Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: 'jwt_token');
    return token != null;
  }

  // --- LISTINGS & MAP ---

  static Future<List<dynamic>> fetchMapListings({
    double minLat = 34.0,
    double minLng = 8.0,
    double maxLat = 38.0,
    double maxLng = 12.0,
  }) async {
    final url = Uri.parse('$baseUrl/listings/map?min_lat=$minLat&min_lng=$minLng&max_lat=$maxLat&max_lng=$maxLng');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['listings'] ?? [];
      }
      return [];
    } catch (e) {
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

  // --- POINTS & UNLOCK ---

  static Future<Map<String, dynamic>> unlockContact(String listingId) async {
    final token = await _storage.read(key: 'jwt_token');
    
    // If no token exists, immediately throw the error for the UI to catch
    if (token == null) {
      throw Exception('🔒 Please Login or Register to use points.');
    }

    final url = Uri.parse('$baseUrl/points/unlock');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // The backend now knows who is asking!
      },
      body: json.encode({'listing_id': listingId}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['error'] ?? 'Failed to unlock contact');
    }
  }
}