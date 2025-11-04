import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleManager {
  static final Guid serviceUuid =
      Guid("12345678-1234-1234-1234-1234567890ab");
  static final Guid charUuid =
      Guid("abcd1234-5678-90ab-cdef-1234567890ab");

  static BluetoothDevice? device;
  static BluetoothCharacteristic? ledChar;

  static bool get isConnected => device != null && ledChar != null;

  static Future<String> scanAndConnect() async {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    final results = await FlutterBluePlus.scanResults.first;

    for (final r in results) {
      if (r.device.platformName == "ESP32C3-LED-B0") {
        device = r.device;
        await device!.connect();
        final services = await device!.discoverServices();
        for (final s in services) {
          if (s.uuid == serviceUuid) {
            for (final c in s.characteristics) {
              if (c.uuid == charUuid) {
                ledChar = c;
              }
            }
          }
        }
        break;
      }
    }

    await FlutterBluePlus.stopScan();

    if (device != null && ledChar != null) {
      return "Connected to ${device!.platformName}";
    } else {
      return "Device not found";
    }
  }

  static Future<void> send(String command) async {
    if (ledChar != null) {
      await ledChar!.write(utf8.encode(command), withoutResponse: true);
    }
  }
}
