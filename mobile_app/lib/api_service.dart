import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';

// Fallback for the rare case XFile.mimeType is null. Matches exactly the
// three types the server's upload endpoint accepts - anything else defaults
// to jpeg rather than sending a type the server is guaranteed to reject.
String _guessMimeType(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:5000/api';
  static const _storage = FlutterSecureStorage();

  // --- AUTHENTICATION ---

  static Future<void> register(String phoneNumber, String fullName, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'phone_number': phoneNumber, 'full_name': fullName, 'password': password}),
    );

    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      await _storage.write(key: 'jwt_token', value: data['token']);
    } else {
      throw Exception(_extractErrorMessage(response.body) ?? 'Registration failed');
    }
  }

  static Future<void> login(String phoneNumber, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'phone_number': phoneNumber, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      await _storage.write(key: 'jwt_token', value: data['token']);
    } else {
      throw Exception(_extractErrorMessage(response.body) ?? 'Login failed');
    }
  }

  static Future<void> logout() async {
    await _storage.delete(key: 'jwt_token');
  }

  static Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: 'jwt_token');
    return token != null;
  }

  static Future<Map<String, dynamic>?> fetchCurrentUser() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) return null;

    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      return json.decode(response.body)['user'];
    }
    // Token expired/invalid - clear it so the UI stops treating us as logged in.
    await _storage.delete(key: 'jwt_token');
    return null;
  }

  // Express-validator errors come back as {errors: [{msg: ...}, ...]};
  // plain server errors come back as {error: "..."}. Handle both shapes.
  static String? _extractErrorMessage(String body) {
    try {
      final data = json.decode(body);
      if (data['error'] != null) return data['error'];
      if (data['errors'] is List && data['errors'].isNotEmpty) {
        return data['errors'][0]['msg'];
      }
    } catch (_) {}
    return null;
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
    if (token == null) {
      throw NotLoggedInException();
    }

    final response = await http.post(
      Uri.parse('$baseUrl/points/unlock'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'listing_id': listingId}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception(_extractErrorMessage(response.body) ?? 'Failed to unlock contact');
    }
  }

  // --- CREATE LISTING ---

  static Future<Map<String, dynamic>> createListing(Map<String, dynamic> listingData) async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) {
      throw NotLoggedInException();
    }

    final response = await http.post(
      Uri.parse('$baseUrl/listings'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(listingData),
    );

    if (response.statusCode == 201) {
      return json.decode(response.body)['listing'];
    } else {
      throw Exception(_extractErrorMessage(response.body) ?? 'Failed to create listing');
    }
  }

  static Future<void> uploadListingImages(String listingId, List<XFile> images) async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) {
      throw NotLoggedInException();
    }

    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/listings/$listingId/images'))
      ..headers['Authorization'] = 'Bearer $token';

    for (final image in images) {
      // XFile.readAsBytes works on every platform including web, unlike
      // dart:io File which web doesn't have. Without an explicit contentType,
      // MultipartFile.fromBytes falls back to guessing from the filename and
      // defaults to application/octet-stream when that fails - which the
      // server correctly rejects even for a perfectly valid image, since it
      // only recognizes image/jpeg, image/png, image/webp.
      request.files.add(http.MultipartFile.fromBytes(
        'images',
        await image.readAsBytes(),
        filename: image.name,
        contentType: MediaType.parse(image.mimeType ?? _guessMimeType(image.name)),
      ));
    }

    final response = await request.send();
    if (response.statusCode != 201) {
      final body = await response.stream.bytesToString();
      throw Exception(_extractErrorMessage(body) ?? 'Failed to upload images');
    }
  }

  // Best-effort field extraction from pasted text (e.g. a Facebook post) to
  // prefill the create-listing form. The caller must still let the user
  // review/edit every field before submitting via createListing.
  static Future<Map<String, dynamic>> parseListingText(String text) async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) {
      throw NotLoggedInException();
    }

    final response = await http.post(
      Uri.parse('$baseUrl/listings/parse-text'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'text': text}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception(_extractErrorMessage(response.body) ?? 'Failed to parse text');
    }
  }

  // --- ADMIN MODERATION ---

  static Future<List<dynamic>> fetchModerationQueue() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) throw NotLoggedInException();

    final response = await http.get(
      Uri.parse('$baseUrl/admin/listings'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      return json.decode(response.body)['listings'];
    } else {
      throw Exception(_extractErrorMessage(response.body) ?? 'Failed to load moderation queue');
    }
  }

  static Future<void> moderateListing(String listingId, String status) async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) throw NotLoggedInException();

    final response = await http.patch(
      Uri.parse('$baseUrl/admin/listings/$listingId/status'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'status': status}),
    );

    if (response.statusCode != 200) {
      throw Exception(_extractErrorMessage(response.body) ?? 'Failed to moderate listing');
    }
  }
}

// Thrown by unlockContact when there's no stored token, so the caller can
// prompt a login instead of showing a generic server-error message.
class NotLoggedInException implements Exception {
  @override
  String toString() => 'Please login to unlock owner contact details.';
}
