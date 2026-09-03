import 'package:flutter/material.dart';

import '../face_lock.dart';
import 'clock_in_screen.dart'; // Add import for ClockInScreen
import 'face_capture_page.dart';
import 'registration_form_screen.dart';
import 'thank_you_screen.dart';
import 'unlocked_page.dart';
import 'welcome_screen.dart';

enum AppPhase {
  loading,
  error,
  welcome,
  registerDetails,
  enroll,
  thankYou,
  verify,
  unlocked,
}

class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  AppPhase _phase = AppPhase.loading;
  String? _error;
  bool _isEnrolled = false;

  // State variables for pre-verified employee details
  String _employeeName = '';
  String _employeeId = '';
  String _employeePin = '';
  String _customerId = ''; // <--- Added to store the ID returned from pre-check
  String _siteId = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _phase = AppPhase.loading;
      _error = null;
    });
    try {
      await FaceLock.instance.init();
      final enrolled = await FaceLock.instance.isEnrolled();
      
      if (!mounted) return;
      setState(() {
        _isEnrolled = enrolled;
        _phase = AppPhase.welcome;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = AppPhase.error;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      AppPhase.loading => const _StartupScreen(
        title: 'Starting face lock',
        message: 'Loading the on-device face model…',
      ),
      AppPhase.error => _StartupScreen(
        title: 'Could not start',
        message: _error ?? 'Unknown error',
        actionLabel: 'Try again',
        onAction: _bootstrap,
      ),
      AppPhase.welcome => WelcomeScreen(
        isEnrolled: _isEnrolled,
        onRegisterPressed: () => setState(() => _phase = AppPhase.registerDetails),
        onSignInPressed: () => setState(() => _phase = AppPhase.verify),
      ),
      AppPhase.registerDetails => RegistrationFormScreen(
        onNextPressed: (name, idNumber, pin, customerId) {
          setState(() {
            _employeeName = name;
            _employeeId = idNumber;
            _employeePin = pin;
            _customerId = customerId; // <--- Saved from pre-check
            _phase = AppPhase.enroll;
          });
        },
        onBackPressed: () => setState(() => _phase = AppPhase.welcome),
      ),
      AppPhase.enroll => FaceCapturePage(
        mode: FaceCaptureMode.enroll,
        employeeName: _employeeName,
        employeeId: _employeeId,
        employeePin: _employeePin,
        siteId: _siteId,
        customerId: _customerId, // <--- Passed down for local saving
        latitude: 0.0,  // Enrollment doesn't require GPS
        longitude: 0.0, // Enrollment doesn't require GPS
        onSuccess: () => setState(() => _phase = AppPhase.thankYou),
      ),
      AppPhase.thankYou => ThankYouScreen(
        onPressed: () => setState(() {
          _isEnrolled = true;
          _phase = AppPhase.welcome;
        }),
      ),
      AppPhase.verify =>  ClockInScreen(), // Updated to route through site selection and GPS capture first
      AppPhase.unlocked => UnlockedPage(
        onLock: () => setState(() => _phase = AppPhase.welcome),
        onReset: () async {
          await FaceLock.instance.reset();
          if (!mounted) return;
          setState(() {
            _isEnrolled = false;
            _phase = AppPhase.registerDetails;
          });
        },
      ),
    };
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    const brandCyan = Color(0xFF5EEAD4);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.face, size: 72, color: brandCyan),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              if (onAction == null)
                const CircularProgressIndicator()
              else
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ),
        ),
      ),
    );
  }
}