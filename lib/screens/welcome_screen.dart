import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.isEnrolled, // Added parameter to check status
    required this.onRegisterPressed,
    required this.onSignInPressed,
  });

  final bool isEnrolled;
  final VoidCallback onRegisterPressed;
  final VoidCallback onSignInPressed;

  @override
  Widget build(BuildContext context) {
    // Colors matching the design
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

                // Glowing Center Icon Box
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: const Color(0xFF061833), // Darker inner box
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
                  child: const Center(
                    child: Icon(
                      Icons.face_retouching_natural,
                      size: 80,
                      color: brandCyan,
                    ),
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
                    // Show Register Button ONLY IF NOT enrolled yet
                    if (!isEnrolled) ...[
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
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    // Sign In Button (Changes text/role based on state, always visible if enrolled)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: buttonBlue, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: onSignInPressed,
                        child: Text(
                          isEnrolled ? 'Sign In' : 'Already Registered',
                          style: const TextStyle(
                            fontSize: 18,
                            color: buttonBlue,
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