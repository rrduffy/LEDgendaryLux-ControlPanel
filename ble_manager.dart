// lib/ble_manager.dart
import 'dart:typed_data';
import 'dart:convert';
import 'dart:js_util' as jsutil;
import 'package:web/web.dart' as web; // ✅ Flutter-safe replacement for dart:html

class BleManager {
  static dynamic _device;
  static dynamic _characteristic;

  static bool get isConnected => _characteristic != null;

  // ---------------------------------------------------------------------------
  // Scan & connect using Web Bluetooth (Chrome only)
  // ---------------------------------------------------------------------------
  static Future<String> scanAndConnect() async {
    try {
      print("🔍 Requesting Bluetooth device...");

      final options = jsutil.jsify({
  "filters": [
    {"name": "Primary"}
  ],
  "optionalServices": [
    "12345678-1234-1234-1234-1234567890ab"
  ]
});


      // ✅ use js_util to call navigator.bluetooth.requestDevice safely
      final bluetooth = jsutil.getProperty(web.window.navigator, 'bluetooth');
      final devicePromise = jsutil.callMethod(bluetooth, 'requestDevice', [options]);
      _device = await jsutil.promiseToFuture(devicePromise);
      final deviceName = jsutil.getProperty(_device, 'name');
      print("Device selected: $deviceName");

      // Connect to GATT server
      final gatt = await jsutil.promiseToFuture(
        jsutil.callMethod(jsutil.getProperty(_device, 'gatt'), 'connect', []),
      );

      // Get primary service
      final service = await jsutil.promiseToFuture(
        jsutil.callMethod(gatt, 'getPrimaryService',
            ["12345678-1234-1234-1234-1234567890ab"]),
      );

      // Get characteristic
      _characteristic = await jsutil.promiseToFuture(
        jsutil.callMethod(
            service, 'getCharacteristic', ["abcd1234-5678-90ab-cdef-1234567890ab"]),
      );

      print("✅ Connected to $deviceName");
      return "Connected to $deviceName";
    } catch (e) {
      print("❌ BLE connection error: $e");
      return "Connection failed: $e";
    }
  }

  // ---------------------------------------------------------------------------
  // Send data to the BLE characteristic
  // ---------------------------------------------------------------------------
  static Future<void> send(String command) async {
    if (_characteristic == null) {
      print("⚠️ Not connected. Cannot send: $command");
      return;
    }

    try {
      final data = Uint8List.fromList(utf8.encode(command));
      await jsutil.promiseToFuture(
        jsutil.callMethod(_characteristic, 'writeValue', [data]),
      );
      print("📤 Sent: $command");
    } catch (e) {
      print("❌ Write failed: $e");
    }
  }
}
