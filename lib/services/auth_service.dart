import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'package:path_provider/path_provider.dart';

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

  factory UserData.fromJson(Map<String, dynamic> json) {
    return UserData(
      firstname: json['firstname'] ?? '',
      lastname: json['lastname'] ?? '',
      email: json['email'] ?? '',
      phonenum: json['phonenum'] ?? '',
      password: json['password'] ?? '',
    );
  }
}

class AuthService {
  static const String _fileName = 'Key.json';

  // Get the file path in the app's documents directory
  Future<File> _getAppFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      if (directory.path.isEmpty) {
        throw Exception('Documents directory path is empty');
      }
      return File('${directory.path}/$_fileName');
    } catch (e) {
      print('Error getting documents directory: $e');
      rethrow;
    }
  }

  // Get project root Key.json file (for reading/writing)
  File _getProjectRootFile() {
    try {
      // Try to get current working directory first
      final currentDir = Directory.current;
      final projectFile = File('${currentDir.path}/Key.json');
      
      // If that doesn't work, try the known absolute path
      if (!projectFile.existsSync()) {
        const projectRootPath = '/Users/phonlapaturairong/Desktop/Senior_1/senior copy/Key.json';
        return File(projectRootPath);
      }
      
      return projectFile;
    } catch (e) {
      // Fallback to absolute path
      const projectRootPath = '/Users/phonlapaturairong/Desktop/Senior_1/senior copy/Key.json';
      return File(projectRootPath);
    }
  }

  // Read all users from Key.json (checks both app directory and project root)
  Future<List<UserData>> getAllUsers() async {
    try {
      List<UserData> users = [];
      
      // First try app directory
      final appFile = await _getAppFile();
      if (await appFile.exists()) {
        final jsonString = await appFile.readAsString();
        if (jsonString.isNotEmpty) {
          final jsonData = jsonDecode(jsonString);
          users = _parseUsersFromJson(jsonData);
          if (users.isNotEmpty) {
            return users;
          }
        }
      }
      
      // Then try project root
      final projectFile = _getProjectRootFile();
      if (await projectFile.exists()) {
        final jsonString = await projectFile.readAsString();
        if (jsonString.isNotEmpty) {
          final jsonData = jsonDecode(jsonString);
          users = _parseUsersFromJson(jsonData);
        }
      }
      
      return users;
    } catch (e) {
      print('Error reading user data: $e');
      return [];
    }
  }

  // Parse users from JSON (handles both old single-user format and new array format)
  List<UserData> _parseUsersFromJson(dynamic jsonData) {
    List<UserData> users = [];
    
    try {
      if (jsonData is List) {
        // New format: array of users
        for (var userJson in jsonData) {
          if (userJson is Map<String, dynamic>) {
            users.add(UserData.fromJson(userJson));
          }
        }
      } else if (jsonData is Map<String, dynamic>) {
        // Old format: single user object (for backward compatibility)
        if (jsonData.containsKey('email')) {
          users.add(UserData.fromJson(jsonData));
        }
      }
    } catch (e) {
      print('Error parsing users from JSON: $e');
    }
    
    return users;
  }

  // Read user data from Key.json (for backward compatibility - returns first user)
  Future<UserData?> getUserData() async {
    final users = await getAllUsers();
    return users.isNotEmpty ? users.first : null;
  }

  // Check if email already exists in Key.json
  Future<bool> emailExists(String email) async {
    try {
      final users = await getAllUsers();
      return users.any((user) => user.email.toLowerCase() == email.toLowerCase());
    } catch (e) {
      print('Error checking email existence: $e');
      return false;
    }
  }

  // Save user data to Key.json - Appends to existing users array
  Future<bool> saveUserData(UserData userData) async {
    try {
      // Get all existing users
      List<UserData> allUsers = await getAllUsers();
      
      // Check if email already exists
      final emailExists = allUsers.any((user) => user.email.toLowerCase() == userData.email.toLowerCase());
      if (emailExists) {
        print('⚠️  Email ${userData.email} already exists - updating existing user');
        // Remove old user with same email and add new one
        allUsers.removeWhere((user) => user.email.toLowerCase() == userData.email.toLowerCase());
      }
      
      // Add new user to the list
      allUsers.add(userData);
      
      // Convert to JSON array
      final usersJson = allUsers.map((user) => user.toJson()).toList();
      final prettyJson = const JsonEncoder.withIndent('  ').convert(usersJson);
      
      print('📝 Saving ${allUsers.length} user(s) to Key.json');
      
      // PRIMARY GOAL: Update project root Key.json file
      // First check if we're on mobile (can't write to project root)
      if (Platform.isAndroid || Platform.isIOS) {
        print('⚠️  Mobile device detected - saving to app directory');
        try {
          final appFile = await _getAppFile();
          await appFile.writeAsString(prettyJson);
          print('✅ Saved to app directory: ${appFile.path}');
          print('✅ Total users: ${allUsers.length}');
          print('✅ New/Updated user: ${userData.firstname} ${userData.lastname} (${userData.email})');
          print('⚠️  Note: On mobile, Key.json is saved in app directory, not project root');
          return true;
        } catch (appError) {
          print('❌ Failed to save to app directory: $appError');
          return false;
        }
      }
      
      // Desktop/Web: Try to save to project root
      try {
        final projectFile = _getProjectRootFile();
        final projectPath = projectFile.absolute.path;
        
        print('📝 Attempting to update Key.json at: $projectPath');
        print('📝 Platform: ${Platform.operatingSystem}');
        
        // Ensure parent directory exists
        final parentDir = projectFile.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
          print('📝 Created parent directory: ${parentDir.path}');
        }
        
        // Write the data to Key.json
        await projectFile.writeAsString(prettyJson);
        print('📝 File written, verifying...');
        
        // Verify it was written correctly
        final verifyContent = await projectFile.readAsString();
        if (verifyContent.isNotEmpty) {
          final verifyData = jsonDecode(verifyContent);
          if (verifyData is List && verifyData.isNotEmpty) {
            final lastUser = verifyData.last;
            if (lastUser['email'] == userData.email) {
              print('✅ SUCCESS: Key.json updated successfully!');
              print('✅ File location: $projectPath');
              print('✅ Total users: ${verifyData.length}');
              print('✅ New/Updated user: ${userData.firstname} ${userData.lastname} (${userData.email})');
              
              // Also save to app directory as backup
              try {
                final appFile = await _getAppFile();
                await appFile.writeAsString(prettyJson);
                print('✅ Also saved to app directory as backup: ${appFile.path}');
              } catch (e) {
                print('⚠️  Could not save to app directory: $e');
              }
              
              return true;
            } else {
              print('❌ ERROR: Verification failed - email mismatch');
              print('❌ Expected: ${userData.email}, Got: ${lastUser['email']}');
              return false;
            }
          } else {
            print('❌ ERROR: Invalid data format after write');
            return false;
          }
        } else {
          print('❌ ERROR: File appears empty after write');
          return false;
        }
      } catch (e, stackTrace) {
        print('❌ ERROR updating project root Key.json: $e');
        print('❌ Stack trace: $stackTrace');
        print('⚠️  Attempting to save to app directory as fallback...');
        
        // Fallback to app directory
        try {
          final appFile = await _getAppFile();
          await appFile.writeAsString(prettyJson);
          print('✅ Saved to app directory (fallback): ${appFile.path}');
          print('✅ Total users: ${allUsers.length}');
          print('✅ New/Updated user: ${userData.firstname} ${userData.lastname} (${userData.email})');
          return true;
        } catch (appError) {
          print('❌ Failed to save to app directory: $appError');
          return false;
        }
      }
    } catch (e, stackTrace) {
      print('❌ CRITICAL ERROR: $e');
      print('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  // Verify login credentials against Key.json (checks all users)
  Future<bool> verifyCredentials(String email, String password) async {
    try {
      final users = await getAllUsers();
      if (users.isEmpty) {
        return false;
      }
      
      // Find user with matching email
      final user = users.firstWhere(
        (u) => u.email.toLowerCase() == email.toLowerCase(),
        orElse: () => UserData(
          firstname: '',
          lastname: '',
          email: '',
          phonenum: '',
          password: '',
        ),
      );
      
      // Check if user was found and password matches
      if (user.email.isEmpty) {
        return false;
      }
      
      return user.password == password;
    } catch (e) {
      print('Error verifying credentials: $e');
      return false;
    }
  }

  // Clear user data (logout)
  Future<bool> clearUserData() async {
    try {
      final appFile = await _getAppFile();
      if (await appFile.exists()) {
        await appFile.delete();
      }
      return true;
    } catch (e) {
      print('Error clearing user data: $e');
      return false;
    }
  }
}
