import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const tealColor = Color(0xFF26A69A);
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final padding = mq.padding;
    final horizontalPadding = (size.width * 0.08).clamp(16.0, 40.0);
    final illustrationSize = (size.width * 0.6).clamp(180.0, 280.0);
    final iconSize = (illustrationSize * 0.48).clamp(80.0, 140.0);
    final titleFontSize = (size.width * 0.1).clamp(28.0, 42.0);
    final bodyFontSize = (size.width * 0.045).clamp(14.0, 20.0);

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
                size: Size(size.width, (size.height * 0.2).clamp(100.0, 180.0)),
                painter: WavePainter(),
              ),
            ),
            // Main content – scrollable so it fits any screen height
            SingleChildScrollView(
              padding: EdgeInsets.only(
                top: (size.height * 0.08).clamp(40.0, 80.0) + padding.top,
                left: horizontalPadding + padding.left,
                right: horizontalPadding + padding.right,
                bottom: 24 + padding.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: size.height - padding.top - padding.bottom - 100),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Welcome!",
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Find your clean route",
                      style: TextStyle(
                        fontSize: bodyFontSize,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: (size.height * 0.04).clamp(24.0, 48.0)),
                    Center(
                      child: Container(
                        width: illustrationSize,
                        height: illustrationSize,
                        decoration: BoxDecoration(
                          color: tealColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.route,
                          size: iconSize,
                          color: tealColor,
                        ),
                      ),
                    ),
                    SizedBox(height: (size.height * 0.04).clamp(24.0, 48.0)),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/signup');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tealColor,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: (size.height * 0.02).clamp(14.0, 20.0),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          "Sign Up",
                          style: TextStyle(
                            fontSize: bodyFontSize + 2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/login');
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: tealColor,
                          side: const BorderSide(color: tealColor, width: 2),
                          padding: EdgeInsets.symmetric(
                            vertical: (size.height * 0.02).clamp(14.0, 20.0),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          "Login",
                          style: TextStyle(
                            fontSize: bodyFontSize + 2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom painter for wave pattern
class WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF26A69A)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height * 0.6);
    
    // Create wave pattern
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
    
    // Second wave layer
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
