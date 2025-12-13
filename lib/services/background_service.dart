import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Manages native Android background operation:
/// - Partial Wake Lock (keeps CPU running when screen is off)
/// - Screen on/off detection
class BackgroundService {
  static const MethodChannel _channel = MethodChannel('com.tangential/background');
  static bool _isRunning = false;
  static Timer? _keepAliveTimer;
  
  // Callbacks for screen state changes
  static VoidCallback? onScreenOff;
  static VoidCallback? onScreenOn;
  
  /// Start background operation (acquire wake lock)
  static Future<bool> start() async {
    if (_isRunning) return true;
    
    try {
      final result = await _channel.invokeMethod<bool>('startBackground');
      if (result == true) {
        _isRunning = true;
        _startKeepAlive();
        debugPrint('BACKGROUND: Started - wake lock acquired');
        return true;
      } else {
        debugPrint('BACKGROUND: Failed to start');
        return false;
      }
    } catch (e) {
      debugPrint('BACKGROUND: Error starting - $e');
      // Fallback: continue without native wake lock
      _isRunning = true;
      return true;
    }
  }
  
  /// Stop background operation (release wake lock)
  static Future<void> stop() async {
    if (!_isRunning) return;
    
    try {
      _stopKeepAlive();
      await _channel.invokeMethod('stopBackground');
      _isRunning = false;
      debugPrint('BACKGROUND: Stopped - wake lock released');
    } catch (e) {
      debugPrint('BACKGROUND: Error stopping - $e');
      _isRunning = false;
    }
  }
  
  /// Setup handler for messages from native code
  static void setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onScreenOff':
          debugPrint('BACKGROUND: Screen OFF detected');
          onScreenOff?.call();
          break;
        case 'onScreenOn':
          debugPrint('BACKGROUND: Screen ON detected');
          onScreenOn?.call();
          break;
      }
    });
  }
  
  /// Keep-alive timer to prevent service from being killed
  static void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_isRunning) {
        debugPrint('BACKGROUND: Keep-alive ping');
      } else {
        timer.cancel();
      }
    });
  }
  
  static void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }
  
  static bool get isRunning => _isRunning;
}

