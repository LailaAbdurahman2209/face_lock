import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.isEnrolled,
    required this.onRegisterPressed,
    required this.onSignInPressed,
  });

  final bool isEnrolled;
  final VoidCallback onRegisterPressed;
  final VoidCallback onSignInPressed;

  @override
  Widget build(BuildContext context) {
    const Color brandCyan = Color(0xFF00D4FF);
    const Color buttonBlue = Color(0xFF007AFF);
    const Color bgDarkBlue = Color(0xFF020B1A);
    const Color bgLightBlue = Color(0xFF051B38);

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgLightBlue, bgDarkBlue],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              children: [
                const Spacer(flex: 3),

                // Center Icon Box with SVG Logo (Native Colors, No Filter)
                Container(
                  width: 140,
                  height: 140,
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF061833),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: brandCyan.withOpacity(0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: brandCyan.withOpacity(0.15),
                        blurRadius: 50,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: SvgPicture.asset(
                    'assets/logo.svg',
                    fit: BoxFit.contain,
                  ),
                ),
                
                const SizedBox(height: 48),

                // IdentityClock Logo
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.shield,
                      color: brandCyan,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                        children: [
                          TextSpan(
                            text: 'Identity',
                            style: TextStyle(color: Colors.white),
                          ),
                          TextSpan(
                            text: 'Clock',
                            style: TextStyle(color: brandCyan),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),

                // Subtitle
                const Text(
                  'Secure identity verification.\nClock in and out with facial recognition.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),

                const Spacer(flex: 4),

                // Action Buttons
                Column(
                  children: [
                    if (!isEnrolled)
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: onRegisterPressed,
                          child: const Text(
                            'Register',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: onSignInPressed,
                          child: const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}