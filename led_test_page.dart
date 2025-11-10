import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:led_control_panel/ble_manager.dart';

class LedTestPage extends StatefulWidget {
  const LedTestPage({super.key});

  @override
  State<LedTestPage> createState() => _LedTestPageState();
}

class _LedTestPageState extends State<LedTestPage> {
  int _ledNumber = 1;
  double _brightness = 0.5;
  Color _selectedColor = Colors.red;

  void _sendLEDCommand() {
    if (!BleManager.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Not connected to BLE device.")),
      );
      return;
    }

    final r = _selectedColor.red;
    final g = _selectedColor.green;
    final b = _selectedColor.blue;
    final brightness = (_brightness * 31).round();

    final command = "B0;L$_ledNumber;$brightness;$r,$g,$b;";
    BleManager.send(command);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Sent: $command")),
    );
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pick LED Color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: _selectedColor,
              onColorChanged: (color) => setState(() => _selectedColor = color),
              pickerAreaHeightPercent: 0.8,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("LED Test Mode"),
        actions: [
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _sendLEDCommand,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("LED Number", style: TextStyle(fontSize: 16)),
            Slider(
              value: _ledNumber.toDouble(),
              min: 1,
              max: 16,
              divisions: 15,
              label: _ledNumber.toString(),
              onChanged: (v) => setState(() => _ledNumber = v.round()),
            ),
            Text("Selected LED: $_ledNumber"),
            const SizedBox(height: 24),

            const Text("Brightness (0–31 scale)", style: TextStyle(fontSize: 16)),
            Slider(
              value: _brightness,
              min: 0.0,
              max: 1.0,
              divisions: 31,
              label: (_brightness * 31).round().toString(),
              onChanged: (v) => setState(() => _brightness = v),
            ),
            Text("Brightness: ${(_brightness * 31).round()} / 31"),
            const SizedBox(height: 24),

            const Text("Color", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showColorPicker,
              child: Container(
                height: 60,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _selectedColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
              ),
            ),

            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.lightbulb),
                label: const Text("Send Command"),
                onPressed: _sendLEDCommand,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
