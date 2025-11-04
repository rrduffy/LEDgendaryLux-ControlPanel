import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

final serviceUuid = Guid("12345678-1234-1234-1234-1234567890ab");
final charUuid    = Guid("abcd1234-5678-90ab-cdef-1234567890ab");

class BleControlPage extends StatefulWidget {
  const BleControlPage({super.key});
  @override
  State<BleControlPage> createState() => _BleControlPageState();
}

class _BleControlPageState extends State<BleControlPage> {
  BluetoothDevice? device;
  BluetoothCharacteristic? ledChar;
  String status = "Not connected";

  Future<void> _scanAndConnect() async {
    setState(() => status = "Scanning...");
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    var results = await FlutterBluePlus.scanResults.first;
    for (final r in results) {
      if (r.device.platformName == "ESP32C3-LED-B0") {
        device = r.device;
        await device!.connect();
        final services = await device!.discoverServices();
        for (final s in services) {
          if (s.uuid == serviceUuid) {
            for (final c in s.characteristics) {
              if (c.uuid == charUuid) ledChar = c;
            }
          }
        }
        break;
      }
    }
    await FlutterBluePlus.stopScan();
    setState(() {
      status = device != null ? "Connected to ${device!.platformName}" : "Not found";
    });
  }

  Future<void> _send(String command) async {
    if (ledChar != null) {
      await ledChar!.write(utf8.encode(command), withoutResponse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("LED Panel BLE Control")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Status: $status"),
            ElevatedButton(
              onPressed: _scanAndConnect,
              child: const Text("Scan & Connect"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _send("B0;L1;31;255,0,0;"),
              child: const Text("Set LED 1 Red"),
            ),
            ElevatedButton(
              onPressed: () => _send("B0;SinglePixelCycle;"),
              child: const Text("Start SinglePixelCycle"),
            ),
            ElevatedButton(
              onPressed: () => _send("B0;ColorCascade;"),
              child: const Text("Start ColorCascade"),
            ),
          ],
        ),
      ),
    );
  }
}
