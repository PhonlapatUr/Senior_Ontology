import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';

class UserData {
  final String firstname;
  final String lastname;
  final String email;
  final String phonenum;
  final String password;

  UserData({
    required this.firstname,
    required this.lastname,
    required this.email,
    required this.phonenum,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'firstname': firstname,
      'lastname': lastname,
      'email': email,
      'phonenum': phonenum,
      'password': password,
    };
  }
}

class AuthService {
  String get baseUrl => backendBase;

  Future<bool> emailExists(String email) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/check-email?email=$email"),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['exists'] == true;
      }
      return false;
    } catch (e) {
      print('Error checking email: $e');
      return false;
    }
  }

  Future<bool> saveUserData(UserData userData) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/signup"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(userData.toJson()),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('✅ User saved to Server successfully');
        return true;
      } else {
        print('❌ Server Error: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Connection Error: $e');
      return false;
    }
  }

  Future<bool> verifyCredentials(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "password": password}),
      );

      if (response.statusCode == 200) {
        print('✅ Login successful via Server');
        return true;
      } else {
        print('❌ Invalid credentials or Server error');
        return false;
      }
    } catch (e) {
      print('❌ Error verifying credentials: $e');
      return false;
    }
  }

  Future<bool> clearUserData() async {
    return true;
  }
}
