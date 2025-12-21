import 'package:flutter/foundation.dart';

/// Simplified background service - wakelock management now handled by wakelock_plus package only
/// Screen state monitoring removed - foreground service handles this natively
class BackgroundService {
  static bool _isRunning = false;
  
  /// Start background operation
  /// Now just tracks state - actual wakelock managed by wakelock_plus in conversation_manager
  static Future<bool> start() async {
    if (_isRunning) return true;
    
    _isRunning = true;
    debugPrint('BACKGROUND: Started (wakelock managed by wakelock_plus)');
    return true;
  }
  
  /// Stop background operation
  static Future<void> stop() async {
    if (!_isRunning) return;
    
    _isRunning = false;
    debugPrint('BACKGROUND: Stopped');
  }
  
  /// Setup method call handler (kept for compatibility, does nothing)
  static void setupMethodCallHandler() {
    debugPrint('BACKGROUND: Method call handler setup (no-op)');
  }
  
  static bool get isRunning => _isRunning;
}
