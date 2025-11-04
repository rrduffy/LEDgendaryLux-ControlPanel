import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:led_control_panel/ble_manager.dart';

class BleControlPage extends StatefulWidget {
  const BleControlPage({super.key});

  @override
  State<BleControlPage> createState() => _BleControlPageState();
}

class _BleControlPageState extends State<BleControlPage> {
  String status = "Not connected";

  Future<void> _connect() async {
    setState(() => status = "Scanning...");
    final result = await BleManager.scanAndConnect();
    setState(() => status = result);
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
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _connect,
              child: const Text("Scan & Connect"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: BleManager.isConnected
                  ? () => BleManager.send("B0;Test;")
                  : null,
              child: const Text("Test LED Command"),
            ),
            const SizedBox(height: 12),
            const Text(
              "Once connected, use the main screen to pick effects.\nThey'll be sent over BLE.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
