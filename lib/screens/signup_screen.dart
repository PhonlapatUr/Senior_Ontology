import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    // Add listeners to all text fields to update button state
    _firstNameController.addListener(_updateButtonState);
    _lastNameController.addListener(_updateButtonState);
    _emailController.addListener(_updateButtonState);
    _phoneController.addListener(_updateButtonState);
    _passwordController.addListener(_updateButtonState);
    _confirmPasswordController.addListener(_updateButtonState);
  }

  @override
  void dispose() {
    _firstNameController.removeListener(_updateButtonState);
    _lastNameController.removeListener(_updateButtonState);
    _emailController.removeListener(_updateButtonState);
    _phoneController.removeListener(_updateButtonState);
    _passwordController.removeListener(_updateButtonState);
    _confirmPasswordController.removeListener(_updateButtonState);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _updateButtonState() {
    setState(() {}); // Trigger rebuild to update button state
  }

  // Check if all fields are filled (not validating format/length - that's done by validators)
  bool _areAllFieldsValid() {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // Only check if all fields are not empty
    // Format/length validation will be shown as error messages when user clicks sign up
    return firstName.isNotEmpty &&
        lastName.isNotEmpty &&
        email.isNotEmpty &&
        phone.isNotEmpty &&
        password.isNotEmpty &&
        confirmPassword.isNotEmpty;
  }

  Future<void> _handleSignUp() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      
      // Check if email already exists
      print('\n' + '='.padRight(60, '='));
      print('CHECKING EMAIL EXISTENCE');
      print('='.padRight(60, '='));
      print('Email to check: $email');
      
      final emailAlreadyExists = await _authService.emailExists(email);
      print('Email exists: $emailAlreadyExists');
      
      if (emailAlreadyExists) {
        // Get existing user data to show in console
        final existingUser = await _authService.getUserData();
        
        print('\n' + '='.padRight(60, '='));
        print('ERROR: EMAIL ALREADY EXISTS');
        print('='.padRight(60, '='));
        print('The email "$email" is already registered.');
        if (existingUser != null) {
          print('Existing account information:');
          print('   First Name: ${existingUser.firstname}');
          print('   Last Name: ${existingUser.lastname}');
          print('   Email: ${existingUser.email}');
          print('   Phone: ${existingUser.phonenum}');
        }
        print('='.padRight(60, '='));
        print('Please use the Login page instead.');
        print('='.padRight(60, '=') + '\n');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Account already exists with email: $email\nPlease use Login instead.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      print('Email is available. Proceeding with sign up...');

      final userData = UserData(
        firstname: _firstNameController.text.trim(),
        lastname: _lastNameController.text.trim(),
        email: email,
        phonenum: _phoneController.text.trim(),
        password: _passwordController.text,
      );

      print('\n' + '='.padRight(60, '='));
      print('SIGN UP PROCESS STARTED');
      print('='.padRight(60, '='));
      print('Email: $email');
      print('Starting save process...');
      
      final success = await _authService.saveUserData(userData);
      print('Save result: $success');
      
      if (success) {
        // Print success message with all user information immediately
        print('\n' + '='.padRight(60, '='));
        print('SIGN UP SUCCESSFUL!');
        print('='.padRight(60, '='));
        print('USER INFORMATION:');
        print('   First Name: ${userData.firstname}');
        print('   Last Name: ${userData.lastname}');
        print('   Email: ${userData.email}');
        print('   Phone Number: ${userData.phonenum}');
        print('   Password: ${'*' * userData.password.length} (${userData.password.length} characters)');
        print('='.padRight(60, '='));
        print('Account created successfully!');
        print('Data saved to Key.json');
        print('User can now login with the credentials above');
        print('='.padRight(60, '=') + '\n');
        
        if (mounted) {
          // Small delay to ensure file is written
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Verify the data was saved by checking if email exists in all users
          final allUsers = await _authService.getAllUsers();
          print('Verification - Total users in database: ${allUsers.length}');
          print('Verification - Checking if email exists: $email');
          
          final userExists = allUsers.any((user) => user.email.toLowerCase() == email.toLowerCase());
          
          if (userExists) {
            final savedUser = allUsers.firstWhere(
              (user) => user.email.toLowerCase() == email.toLowerCase(),
            );
            print('Verification - User found: ${savedUser.firstname} ${savedUser.lastname} (${savedUser.email})');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Account created successfully! Data saved to Key.json'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
            Navigator.pushReplacementNamed(context, '/login');
          } else {
            print('Verification warning: Email not found in database, but account creation reported success');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Account created but verification failed. Please try logging in.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
            Navigator.pushReplacementNamed(context, '/login');
          }
        }
      } else {
        print('\n' + '='.padRight(60, '='));
        print('SIGN UP FAILED');
        print('='.padRight(60, '='));
        print('Failed to create account');
        print('Please check console/logs for details');
        print('='.padRight(60, '=') + '\n');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create account. Please check console/logs for details.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const tealColor = Color(0xFF4DD0E1);
    const darkTeal = Color(0xFF26A69A);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Decorative wave pattern at top
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: CustomPaint(
                size: Size(MediaQuery.of(context).size.width, 120),
                painter: WavePainter(),
              ),
            ),
            
            // Main content
            SingleChildScrollView(
              padding: const EdgeInsets.only(top: 100),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      const Text(
                        "Create Account",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: tealColor,
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // First Name
                      TextFormField(
                        controller: _firstNameController,
                        decoration: InputDecoration(
                          labelText: "First Name",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor, width: 2),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your first name';
                          }
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Last Name
                      TextFormField(
                        controller: _lastNameController,
                        decoration: InputDecoration(
                          labelText: "Last Name",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor, width: 2),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your last name';
                          }
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Email
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9@._-]')),
                        ],
                        decoration: InputDecoration(
                          labelText: "Email",
                          helperText: "Enter a valid email address (e.g., user@gmail.com)",
                          helperMaxLines: 1,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor, width: 2),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!value.contains('@') || !value.contains('.')) {
                            return 'Please enter a valid email address';
                          }
                          // More strict email validation
                          final emailRegex = RegExp(r'^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                          if (!emailRegex.hasMatch(value)) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Phone Number
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: "Phone Number",
                          helperText: "Enter 9-10 digits only (e.g., 0912345678)",
                          helperMaxLines: 1,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor, width: 2),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your phone number';
                          }
                          if (value.trim().length < 9 || value.trim().length > 10) {
                            return 'Phone number must be 9-10 digits';
                          }
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Create Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: "Create Password",
                          helperText: "Enter at least 6 characters (e.g., password123)",
                          helperMaxLines: 1,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor, width: 2),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility : Icons.visibility_off,
                              color: tealColor,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Confirm Password
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          labelText: "Confirm Password",
                          helperText: "Re-enter your password to confirm",
                          helperMaxLines: 1,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: tealColor, width: 2),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                              color: tealColor,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword = !_obscureConfirmPassword;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Sign up button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (_isLoading || !_areAllFieldsValid()) ? null : _handleSignUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tealColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade600,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  "Sign up",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Terms and conditions
                      Center(
                        child: Text.rich(
                          TextSpan(
                            text: "By continuing you are agreeing our ",
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                            children: [
                              TextSpan(
                                text: "terms & conditions",
                                style: TextStyle(
                                  color: tealColor,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              const TextSpan(text: " and our "),
                              TextSpan(
                                text: "privacy polices",
                                style: TextStyle(
                                  color: tealColor,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
            
            // Back button - placed last so it's on top
            Positioned(
              top: 10,
              left: 0,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: 56,
                    height: 56,
                    padding: const EdgeInsets.all(12),
                    child: const Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Reuse wave painter
class WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4DD0E1)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height * 0.6);
    path.quadraticBezierTo(
      size.width * 0.25, size.height * 0.4,
      size.width * 0.5, size.height * 0.6,
    );
    path.quadraticBezierTo(
      size.width * 0.75, size.height * 0.8,
      size.width, size.height * 0.6,
    );
    path.lineTo(size.width, 0);
    path.lineTo(0, 0);
    path.close();

    canvas.drawPath(path, paint);
    
    final paint2 = Paint()
      ..color = const Color(0xFF26A69A)
      ..style = PaintingStyle.fill;

    final path2 = Path();
    path2.moveTo(0, size.height * 0.7);
    path2.quadraticBezierTo(
      size.width * 0.3, size.height * 0.5,
      size.width * 0.6, size.height * 0.7,
    );
    path2.quadraticBezierTo(
      size.width * 0.9, size.height * 0.9,
      size.width, size.height * 0.7,
    );
    path2.lineTo(size.width, 0);
    path2.lineTo(0, 0);
    path2.close();

    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
