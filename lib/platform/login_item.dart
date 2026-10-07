import 'dart:io';

import 'package:flutter/services.dart';

class LoginItem {
  static const MethodChannel _channel = MethodChannel('dot/login_item');

  static Future<bool> isSupported() async {
    if (!Platform.isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    if (!Platform.isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> setEnabled(bool enabled) async {
    if (!Platform.isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>('setEnabled', enabled) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
