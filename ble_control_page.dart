// lib/ble_control_page.dart
import 'package:flutter/material.dart';
import 'ble_manager.dart';

class BleControlPage extends StatefulWidget {
  const BleControlPage({super.key});

  @override
  State<BleControlPage> createState() => _BleControlPageState();
}

class _BleControlPageState extends State<BleControlPage> {
  String _status = "Not connected";

  // ---------------------- SCAN & CONNECT ----------------------
  Future<void> _connect() async {
    setState(() => _status = "Scanning...");
    final result = await BleManager.scanAndConnect();
    setState(() => _status = result);
  }

  // ---------------------- TEST SEND ----------------------
  Future<void> _testSend() async {
    await BleManager.send("B0;L1;31;255,0,0;");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Sent test LED command to ESP32")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool connected = BleManager.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text("LED Panel BLE Control"),
        backgroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFF121212),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 🔹 Status Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: connected ? Colors.lightBlueAccent : Colors.redAccent,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  connected ? "Status: Connected ✅" : "Status: Not Connected ❌",
                  style: TextStyle(
                    fontSize: 18,
                    color: connected ? Colors.greenAccent : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _status,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),

            // 🔵 Scan & Connect button
            ElevatedButton.icon(
              onPressed: _connect,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text("Scan & Connect"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 20),

            // 🟢 Test command button
            ElevatedButton.icon(
              onPressed: connected ? _testSend : null,
              icon: const Icon(Icons.send),
              label: const Text("Test LED Command"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent.shade400,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
