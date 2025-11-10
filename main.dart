import 'package:flutter/material.dart';
import 'package:led_control_panel/ble_control_page.dart';
import 'package:led_control_panel/ble_manager.dart';
import 'dart:math';

void main() => runApp(const LEDControlApp());

class LEDControlApp extends StatelessWidget {
  const LEDControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Material 3 + dark gray surface
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: Colors.blueAccent,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LED Control Panel',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      home: const ControlPanelScreen(),
      routes: {'/ble': (context) => const BleControlPage()},
    );
  }
}

class ControlPanelScreen extends StatefulWidget {
  const ControlPanelScreen({super.key});

  @override
  State<ControlPanelScreen> createState() => _ControlPanelScreenState();
}

class _ControlPanelScreenState extends State<ControlPanelScreen>
    with TickerProviderStateMixin {
  bool _pulseEnabled = false;
  bool _ledsEnabled = true;
  bool _showPulseWarning = false;
  bool _trailEnabled = false;
  bool _showTrailWarning = false;
  bool _rainbowEnabled = false;
  bool _isLayoutMode = false;

  // Grid snapping (no overlap)
  final double _gridGap = 0.0; // spacing between tiles in layout mode

  // Panel grid cell assignments
  final List<int?> _panelCells = List<int?>.filled(25, null);

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _trailController;
  late AnimationController _rainbowController;
  late List<Color?> _ledColors;
  late List<double> _ledBrightness;
  late List<bool> _ledSelected;

  int _trailPosition = 0;
  int? _draggingPanelIndex;
  Offset _pointerOffsetInsidePanel = Offset.zero;
  final int ledCount = 16;

  final List<Offset> _panelPositions = List.generate(
    25,
    (index) => Offset.zero,
  );
  final List<List<bool>> _panelConnections = List.generate(
    25,
    (_) => List.filled(4, false),
  );

  Future<void> _showColorPickerForSingleLED(int index) async {
    Color tempColor = _ledColors[index] ?? Colors.white;
    double tempBrightness = _ledBrightness[index];
    bool applied = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('LED ${index + 1}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ColorWheelWithSliders(
                    color: tempColor,
                    onColorChanged: (c) => setState(() => tempColor = c),
                  ),
                  const SizedBox(height: 16),
                  Text('Brightness: ${(tempBrightness * 100).round()}%'),
                  Slider(
                    value: tempBrightness,
                    onChanged: (v) => setState(() => tempBrightness = v),
                    min: 0.0,
                    max: 1.0,
                    divisions: 100,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    applied = true;
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (applied) {
      setState(() {
        _ledColors[index] = tempColor;
        _ledBrightness[index] = tempBrightness;
        _globalBrightness = tempBrightness;
      });

      if (BleManager.isConnected) {
        final r = tempColor.red, g = tempColor.green, b = tempColor.blue;
        final bright = (tempBrightness * 31).round();
        BleManager.send("B0;L${index + 1};$bright;$r,$g,$b;");
      }
    }
  }

  // Drag selection variables (grid selection, not panel layout)
  Offset? _dragStart;
  Offset? _dragEnd;
  final bool _isDragging = false;

  // Unified speed control
  double _effectSpeed = 0.5; // 0.0 to 1.0 (slow to fast)

  // Trail length control (how far the trail extends)
  double _trailFadeLength = 6.0; // default: smooth fade across ~6 LEDs

  // Global brightness control
  double _globalBrightness = 0.5;

  // Layout sandbox + snapping/grid vars
  final double _panelSize = 60.0; // panel size
  final GlobalKey _layoutKey = GlobalKey();

  // Simple sandbox: add/clear active panels
  final List<int> _activePanels = []; // start empty; Add Panel button populates

  int _colsFor(Size size) =>
      ((size.width + _gridGap) / (_panelSize + _gridGap)).floor();

  int _rowsFor(Size size) =>
      ((size.height + _gridGap) / (_panelSize + _gridGap)).floor();

  Offset _posForCell(int cell, Size size) {
    final cols = _colsFor(size);
    final row = cell ~/ cols;
    final col = cell % cols;
    final dx = col * (_panelSize + _gridGap);
    final dy = row * (_panelSize + _gridGap);
    return Offset(dx, dy);
  }

  int _cellForPos(Offset pos, Size size) {
    final cols = _colsFor(size);
    final rows = _rowsFor(size);
    int col = (pos.dx / (_panelSize + _gridGap)).round().clamp(0, cols - 1);
    int row = (pos.dy / (_panelSize + _gridGap)).round().clamp(0, rows - 1);
    return row * cols + col;
  }

  bool _cellOccupied(int cell, {int? exceptPanel}) {
    for (int p = 0; p < _panelCells.length; p++) {
      if (p == exceptPanel) continue;
      if (_panelCells[p] == cell) return true;
    }
    return false;
  }

  int _nearestFreeCell(int desiredCell, Size size, {int? exceptPanel}) {
    final cols = _colsFor(size);
    final rows = _rowsFor(size);
    final total = cols * rows;

    if (!_cellOccupied(desiredCell, exceptPanel: exceptPanel)) {
      return desiredCell;
    }

    // Search outward by Manhattan distance
    int best = desiredCell;
    double bestDist = double.infinity;
    final dRow0 = desiredCell ~/ cols;
    final dCol0 = desiredCell % cols;

    for (int cell = 0; cell < total; cell++) {
      if (_cellOccupied(cell, exceptPanel: exceptPanel)) continue;
      final r = cell ~/ cols;
      final c = cell % cols;
      final dist = (r - dRow0).abs() + (c - dCol0).abs();
      if (dist < bestDist) {
        bestDist = dist.toDouble();
        best = cell;
      }
    }
    return best;
  }

  void _placePanelOnGrid(int index) {
    final keyContext = _layoutKey.currentContext;
    if (keyContext == null) {
      // Layout not ready yet
      _panelCells[index] = null;
      _panelPositions[index] = Offset.zero;
      return;
    }
    final box = keyContext.findRenderObject() as RenderBox;
    final size = box.size;
    final cols = _colsFor(size);
    final rows = _rowsFor(size);
    final total = cols * rows;

    for (int cell = 0; cell < total; cell++) {
      if (!_cellOccupied(cell)) {
        _panelCells[index] = cell;
        _panelPositions[index] = _posForCell(cell, size);
        return;
      }
    }

    // If grid is full, just keep it at (0,0)
    _panelCells[index] = null;
    _panelPositions[index] = Offset.zero;
  }

  @override
  void initState() {
    super.initState();

    _ledColors = List.filled(ledCount, null);
    _ledBrightness = List.filled(ledCount, 0.5);
    _ledSelected = List.filled(ledCount, false);

    final duration = _calculateEffectDuration();
    _pulseController = AnimationController(vsync: this, duration: duration);
    _trailController = AnimationController(vsync: this, duration: duration);
    _rainbowController = AnimationController(vsync: this, duration: duration);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _trailController.addListener(_updateTrailPosition);
    _rainbowController.addListener(_updateRainbowEffect);
  }

  Duration _calculateEffectDuration() {
    // Slower at 0, faster near 1
    const int slowMs = 5000;
    const int fastMs = 1000;
    return Duration(
      milliseconds: fastMs + ((slowMs - fastMs) * (1 - _effectSpeed)).toInt(),
    );
  }

  void _updateEffectSpeed(double speed) {
    if (!mounted) return;
    setState(() {
      _effectSpeed = speed;
      final newDuration = _calculateEffectDuration();
      for (final c in [
        _pulseController,
        _trailController,
        _rainbowController,
      ]) {
        c.duration = newDuration;
      }
      if (BleManager.isConnected) {
        if (_pulseEnabled) {
          _sendBleEffect("Pulse", speed: _effectSpeed);
        } else if (_trailEnabled) {
          _sendBleEffect(
            "Trail",
            speed: _effectSpeed,
            fadeLength: _trailFadeLength,
          );
        } else if (_rainbowEnabled) {
          _sendBleEffect("Rainbow", speed: _effectSpeed);
        }
      }

      // Restart running animations to apply the new speed
      if (_pulseEnabled)
        _pulseController
          ..stop()
          ..repeat(reverse: true);
      if (_trailEnabled)
        _trailController
          ..stop()
          ..repeat();
      if (_rainbowEnabled)
        _rainbowController
          ..stop()
          ..repeat();
    });
  }

  void _updateGlobalBrightness(double brightness) {
    if (!mounted) return;
    setState(() => _globalBrightness = brightness);

    if (BleManager.isConnected) {
      final buffer = StringBuffer();
      final bright = (brightness * 31).round();

      for (int idx = 0; idx < ledCount; idx++) {
        final color = _ledColors[idx];
        if (color != null) {
          final r = color.red, g = color.green, b = color.blue;
          final ledNumber = idx + 1;
          buffer.write("B0;L$ledNumber;$bright;$r,$g,$b;");
        }
      }
      BleManager.send(buffer.toString());
    }
  }
  Future<void> _initializePanels() async {
  if (!BleManager.isConnected) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Connect to BLE first')));
    return;
  }

  // Simple flash sequence to test all panels
  BleManager.send("MODE;0;0|LED;0;31;255;255;255|");
  await Future.delayed(const Duration(milliseconds: 500));
  BleManager.send("LED;0;0;0;0;0|");

  setState(() {
    for (int i = 0; i < ledCount; i++) {
      _ledColors[i] = Colors.white;
      _ledBrightness[i] = 0.5;
    }
  });

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Panels initialized successfully')),
  );
}

  void _sendBleEffect(
    String effect, {
    Color? color,
    double? speed,
    double? fadeLength,
  }) {
    if (!BleManager.isConnected) return;
    final s = ((speed ?? 0.5) * 50).clamp(1, 50).round();
    final r = color?.red ?? 255,
        g = color?.green ?? 255,
        b = color?.blue ?? 255;

    switch (effect) {
      case "Pulse":
        BleManager.send("MODE;0;1|MODECOL;0;$r,$g,$b|MODESPD;0;$s|");
        break;
      case "Rainbow":
        BleManager.send("MODE;0;2|MODESPD;0;$s|");
        break;
      case "Trail":
        final f = (fadeLength ?? 6.0).round();
        BleManager.send(
          "MODE;0;3|MODECOL;0;$r,$g,$b|MODESPD;0;$s|MODEFADE;0;$f|",
        );
        break;
      case "Sparkle":
        BleManager.send("MODE;0;4|MODECOL;0;$r,$g,$b|MODESPD;0;$s|");
        break;
      case "Wave":
        BleManager.send("MODE;0;5|MODECOL;0;$r,$g,$b|MODESPD;0;$s|");
        break;
      default:
        BleManager.send("MODE;0;0|LED;0;0;0;0;0|");
    }
  }

  void _togglePulseEffect() {
    if (!_hasLitLEDs()) {
      _showTemporaryWarning('_showPulseWarning');
      return;
    }

    setState(() {
      _pulseEnabled = !_pulseEnabled;
      if (_pulseEnabled) {
        _pulseController.repeat(reverse: true);
        _sendBleEffect("Pulse", speed: _effectSpeed);
      } else {
        _pulseController.stop();
        _sendBleEffect("Off");
      }
    });
  }

  void _toggleTrailEffect() {
    if (!_hasLitLEDs()) {
      _showTemporaryWarning('_showTrailWarning');
      return;
    }

    setState(() {
      _trailEnabled = !_trailEnabled;
      _trailPosition = 0;
      if (_trailEnabled) {
        _sendBleEffect(
          "Trail",
          speed: _effectSpeed,
          fadeLength: _trailFadeLength,
        );
      } else {
        _trailController.stop();
        _sendBleEffect("Off");
      }
    });
  }

  void _toggleRainbowEffect() {
    setState(() {
      _rainbowEnabled = !_rainbowEnabled;

      if (_rainbowEnabled) {
        for (int idx = 0; idx < ledCount; idx++) {
          _ledColors[idx] ??= Colors.white;
          _ledBrightness[idx] = 0.7;
        }
        _rainbowController.repeat();

        _sendBleEffect("Rainbow", speed: _effectSpeed);
      } else {
        _rainbowController.stop();
        _sendBleEffect("Off");
      }
    });
  }

  // helper to briefly show a warning flag like _showPulseWarning
  void _showTemporaryWarning(String flagName) {
    setState(() {
      if (flagName == '_showPulseWarning') _showPulseWarning = true;
      if (flagName == '_showTrailWarning') _showTrailWarning = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        if (flagName == '_showPulseWarning') _showPulseWarning = false;
        if (flagName == '_showTrailWarning') _showTrailWarning = false;
      });
    });
  }

  void _updateTrailPosition() {
    if (!_trailEnabled) return;
    final newPosition = (_trailController.value * 25).floor() % 25;
    final newBrightnessGrid = List.generate(5, (_) => List.filled(5, 0.0));

    if (mounted) {
      setState(() {
        _trailPosition = newPosition;
      });
    }
  }

  bool _hasLitLEDs() {
    return _ledColors.any((color) => color != null);
  }

  void _turnAllOff() {
    if (!BleManager.isConnected) return;
    BleManager.send("MODE;0;0|LED;0;0;0;0;0|");
    setState(() {
      for (int i = 0; i < ledCount; i++) {
        _ledColors[i] = null;
        _ledSelected[i] = false;
        _ledBrightness[i] = 0;
      }
    });
  }

  void _toggleLEDs() {
    setState(() {
      _ledsEnabled = !_ledsEnabled;

      if (_ledsEnabled) {
        // Restore LEDs if none lit
        if (!_hasLitLEDs()) {
          for (int idx = 0; idx < ledCount; idx++) {
            _ledColors[idx] = Colors.white;
            _ledBrightness[idx] = _globalBrightness;
          }
        }
      } else {
        // Turning off LEDs stops all effects
        _pulseEnabled = false;
        _trailEnabled = false;
        _rainbowEnabled = false;
        _pulseController.stop();
        _trailController.stop();
        _rainbowController.stop();
      }
    });
  }

  void _updateRainbowEffect() {
    if (!_rainbowEnabled) return;
    final hueShift = _rainbowController.value * 360;

    setState(() {
      for (int i = 0; i < ledCount; i++) {
        final baseHue = ((i / ledCount) * 360 - hueShift) % 360;
        final hue = baseHue < 0 ? baseHue + 360 : baseHue;
        _ledColors[i] = HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _trailController.dispose();
    _rainbowController.dispose();
    super.dispose();
  }

  void _toggleLayoutMode() {
    setState(() {
      _isLayoutMode = !_isLayoutMode;
      if (!_isLayoutMode) {
        // Exiting layout mode: clear temporary connection visuals
        for (var connections in _panelConnections) {
          for (int i = 0; i < connections.length; i++) {
            connections[i] = false;
          }
        }
      }
      // NOTE: No auto-populating or resetting of _panelPositions here.
    });
  }

  // Start panel drag
  void _startPanelDrag(int index, Offset localPositionInsidePanel) {
    final keyContext = _layoutKey.currentContext;
    if (keyContext == null) return;

    final box = keyContext.findRenderObject() as RenderBox;
    final size = box.size;

    // Remember pointer offset inside the tile for smooth dragging
    _pointerOffsetInsidePanel = localPositionInsidePanel;

    // Mark which panel is being dragged
    setState(() {
      _draggingPanelIndex = index;
    });
  }

  void _updatePanelDrag(Offset globalPosition) {
    if (_draggingPanelIndex == null) return;
    final keyContext = _layoutKey.currentContext;
    if (keyContext == null) return;

    final box = keyContext.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    final size = box.size; // ✅ add this line

    // Optional clamp to keep tiles in-bounds
    final unclamped = local - _pointerOffsetInsidePanel;
    final clamped = Offset(
      unclamped.dx.clamp(0.0, size.width - _panelSize).toDouble(),
      unclamped.dy.clamp(0.0, size.height - _panelSize).toDouble(),
    );

    setState(() {
      _panelPositions[_draggingPanelIndex!] = clamped;
    });
  }

  void _endPanelDrag() {
    final idx = _draggingPanelIndex;
    final keyContext = _layoutKey.currentContext;

    if (idx != null && keyContext != null) {
      final box = keyContext.findRenderObject() as RenderBox;
      final size = box.size;

      // Where did the user drop it?
      final desiredCell = _cellForPos(_panelPositions[idx], size);

      // Find the nearest free cell (can be the same if free)
      final targetCell = _nearestFreeCell(desiredCell, size, exceptPanel: idx);

      setState(() {
        _panelCells[idx] = targetCell;
        _panelPositions[idx] = _posForCell(targetCell, size);
        _draggingPanelIndex = null;
      });
    } else {
      setState(() {
        _draggingPanelIndex = null;
      });
    }
  }

  void _resetPanelLayout() {
    final keyContext = _layoutKey.currentContext;
    if (keyContext == null) return;

    final box = keyContext.findRenderObject() as RenderBox;
    final size = box.size;

    setState(() {
      // clear connections
      for (var connections in _panelConnections) {
        for (int i = 0; i < connections.length; i++) {
          connections[i] = false;
        }
      }

      // re-pack active panels into first N slots
      // (order = by panel id)
      final cols = _colsFor(size);
      int nextCell = 0;

      for (final i in _activePanels..sort()) {
        // advance to next free cell
        while (_cellOccupied(nextCell)) {
          nextCell++;
        }
        _panelCells[i] = nextCell;
        _panelPositions[i] = _posForCell(nextCell, size);
        nextCell++;
      }
    });
  }

  // Convert global position to grid coordinates (for LED selection mode)
  (int, int)? _getGridPositionFromOffset(Offset position, Size gridSize) {
    final gridPadding = 8.0;
    final cellSize = (gridSize.width - gridPadding * 2) / 5;

    final relativeX = position.dx - gridPadding;
    final relativeY = position.dy - gridPadding;

    if (relativeX < 0 || relativeY < 0) return null;

    final col = (relativeX / cellSize).floor();
    final row = (relativeY / cellSize).floor();

    if (row >= 0 && row < 5 && col >= 0 && col < 5) {
      return (row, col);
    }
    return null;
  }

  void _applyToSelectedLEDs(Color color, double brightness) {
    if (!BleManager.isConnected) {
      print("BLE not connected");
      return;
    }

    final buffer = StringBuffer();
    final bright = (brightness * 31).round();

    setState(() {
      for (int idx = 0; idx < ledCount; idx++) {
        if (_ledSelected[idx]) {
          _ledColors[idx] = color;
          _ledBrightness[idx] = brightness;

          final ledNumber = idx + 1;
          buffer.write(
            "B0;L$ledNumber;$bright;${color.red},${color.green},${color.blue};",
          );
        }
      }
    });

    BleManager.send(buffer.toString());
    _selectAllLEDs(false); // clear selection
  }

  void _selectAllLEDs(bool select) {
    setState(() {
      for (int i = 0; i < _ledSelected.length; i++) {
        _ledSelected[i] = select;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LED Control Panel'),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.settings_backup_restore,
              color: Colors.orangeAccent,
            ),
            tooltip: 'Initialize Panels',
            onPressed: _initializePanels,
          ),

          IconButton(
            icon: Icon(
              _isLayoutMode ? Icons.grid_on : Icons.grid_off,
              color: _isLayoutMode ? Colors.amberAccent : Colors.white,
            ),
            tooltip: _isLayoutMode ? 'Exit Layout Mode' : 'Arrange Panels',
            onPressed: _toggleLayoutMode,
          ),
          IconButton(
            icon: const Icon(
              Icons.settings_bluetooth,
              color: Colors.lightBlueAccent,
            ),
            tooltip: 'Bluetooth Controls',
            onPressed: () => Navigator.pushNamed(context, '/ble'),
          ),
          IconButton(
            icon: Icon(
              _rainbowEnabled ? Icons.gradient : Icons.color_lens_outlined,
              color: _rainbowEnabled ? Colors.lightBlueAccent : Colors.white,
            ),
            tooltip: 'Rainbow Effect',
            onPressed: _toggleRainbowEffect,
          ),
          IconButton(
            icon: Icon(
              _trailEnabled ? Icons.waves : Icons.waves_outlined,
              color: _trailEnabled ? Colors.lightBlueAccent : Colors.white,
            ),
            tooltip: 'Trail Effect',
            onPressed: _toggleTrailEffect,
          ),
          IconButton(
            icon: Icon(
              _pulseEnabled ? Icons.animation : Icons.animation_outlined,
              color: _pulseEnabled ? Colors.lightBlueAccent : Colors.white,
            ),
            tooltip: 'Pulse Effect',
            onPressed: _togglePulseEffect,
          ),
          IconButton(
            icon: const Icon(Icons.lightbulb_outline, color: Colors.redAccent),
            tooltip: 'Turn All LEDs Off',
            onPressed: _turnAllOff,
          ),
        ],
      ),

      body: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 170,
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selection Tools',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () => _selectAllLEDs(true),
                        child: const Text('Select All'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: () => _selectAllLEDs(false),
                        child: const Text('Clear All'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: () {
                          Color defaultColor = Colors.blue;
                          double defaultBrightness = 0.5;

                          outerLoop:
                          for (int idx = 0; idx < ledCount; idx++) {
                            if (_ledSelected[idx] && _ledColors[idx] != null) {
                              defaultColor = _ledColors[idx]!;
                              defaultBrightness = _ledBrightness[idx];
                              break outerLoop;
                            }
                          }
                          _showColorPickerForMultiSelect(
                            defaultColor,
                            defaultBrightness,
                          );
                        },
                        child: const Text('Apply Color'),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Click or drag to select LEDs',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      if (_isLayoutMode) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Layout Tools',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          onPressed: () {
                            setState(() {
                              for (int i = 0; i < 25; i++) {
                                if (!_activePanels.contains(i)) {
                                  _activePanels.add(i);
                                  _placePanelOnGrid(i);
                                  break;
                                }
                              }
                            });
                          },
                          child: const Text('Add Panel'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: () =>
                              setState(() => _activePanels.clear()),
                          child: const Text('Clear Panels'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: _resetPanelLayout,
                          child: const Text('Reset Layout'),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Drag panels to arrange them',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Center Grid
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 450),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: _isLayoutMode
                                  ? _buildLayoutModeView()
                                  : _buildGridView(),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),
                    _buildBrightnessControl(),
                  ],
                ),
              ),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: (_pulseEnabled || _trailEnabled || _rainbowEnabled)
                    ? _buildEffectSpeedControl()
                    : _buildEffectInfoPanel(),
              ),
            ],
          ),

          if (_showPulseWarning)
            _buildWarning('Turn on at least one LED to use pulse effect'),
          if (_showTrailWarning)
            _buildWarning('Turn on at least one LED to use trail effect'),
        ],
      ),
    );
  }

  Widget _buildWarning(String text) {
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrightnessControl() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          children: [
            const Text(
              'Brightness',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Slider(
              value: _globalBrightness,
              onChanged: _updateGlobalBrightness,
              min: 0.0,
              max: 1.0,
              divisions: 100,
            ),
            Text(
              '${(_globalBrightness * 100).round()}%',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectSpeedControl() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Effect Speed',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Slider(
              value: _effectSpeed,
              onChanged: _updateEffectSpeed,
              min: 0.0,
              max: 1.0,
              divisions: 10,
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Slow',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  'Fast',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            if (_trailEnabled) ...[
              const SizedBox(height: 20),
              const Text(
                'Trail Fade Length',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Slider(
                value: _trailFadeLength,
                onChanged: (v) => setState(() => _trailFadeLength = v),
                min: 2.0,
                max: 12.0,
                divisions: 10,
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Short',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    'Long',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEffectInfoPanel() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Effects',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Enable an effect from the toolbar to adjust speed',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: ledCount,
      itemBuilder: (context, index) {
        final color = _ledColors[index] ?? Colors.grey.shade900;
        final selected = _ledSelected[index];
        return GestureDetector(
          onTap: () => setState(() => _ledSelected[index] = !selected),
          onLongPress: () => _showColorPickerForSingleLED(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? Colors.amber : Colors.white24,
                width: selected ? 3 : 1.2,
              ),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLayoutModeView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          key: _layoutKey,
          width: constraints.maxWidth,
          height: constraints.maxWidth,
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              if (_activePanels.isEmpty)
                const Center(
                  child: Text(
                    'No panels yet. Tap "Add Panel" to place one.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ..._activePanels.map((index) {
                final pos = _panelPositions[index];
                final idx = index % ledCount;

                Color? color = _ledColors[idx];
                if (!_ledsEnabled) color = null;

                final brightness = _ledBrightness[idx];
                final isSelected = _ledSelected[idx];

                final pulseValue = _pulseEnabled ? _pulseAnimation.value : 1.0;
                final trailValue = _trailEnabled ? brightness : 1.0;

                if (_rainbowEnabled) {
                  color = _ledColors[idx];
                }

                final effectiveBrightness =
                    brightness * pulseValue * trailValue;

                return Positioned(
                  left: pos.dx,
                  top: pos.dy,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _ledSelected[idx] = !_ledSelected[idx];
                        if (_ledSelected[idx]) {
                          _globalBrightness = _ledBrightness[idx];
                        }
                      });
                    },
                    onLongPress: () => _showColorPickerForSingleLED(idx),
                    onPanStart: (details) =>
                        _startPanelDrag(index, details.localPosition),
                    onPanUpdate: (details) =>
                        _updatePanelDrag(details.globalPosition),
                    onPanEnd: (_) => _endPanelDrag(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: _panelSize,
                      height: _panelSize,
                      decoration: BoxDecoration(
                        color:
                            color?.withOpacity(effectiveBrightness) ??
                            Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? Colors.amberAccent
                              : Colors.white24,
                          width: isSelected ? 3 : 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'P${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // Dialog & helper widgets
  Future<void> _showColorPickerForMultiSelect(
    Color initialColor,
    double initialBrightness,
  ) async {
    Color tempColor = initialColor;
    double tempBrightness = initialBrightness;
    bool changesConfirmed = false;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Apply to Selected LEDs'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Color wheel and RGB sliders
                    ColorWheelWithSliders(
                      color: tempColor,
                      onColorChanged: (Color newColor) {
                        setState(() => tempColor = newColor);
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Brightness: ${(tempBrightness * 100).round()}%',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: tempBrightness,
                      onChanged: (value) {
                        setState(() => tempBrightness = value);
                      },
                      min: 0.0,
                      max: 1.0,
                      divisions: 100,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    changesConfirmed = true;
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
    if (changesConfirmed) {
      _applyToSelectedLEDs(tempColor, tempBrightness);
    }
  }
}

// Combined color wheel and RGB sliders widget
class ColorWheelWithSliders extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onColorChanged;

  const ColorWheelWithSliders({
    super.key,
    required this.color,
    required this.onColorChanged,
  });

  @override
  _ColorWheelWithSlidersState createState() => _ColorWheelWithSlidersState();
}

class _ColorWheelWithSlidersState extends State<ColorWheelWithSliders> {
  late int _red;
  late int _green;
  late int _blue;
  late HSVColor _hsvColor;

  @override
  void initState() {
    super.initState();
    _red = widget.color.red;
    _green = widget.color.green;
    _blue = widget.color.blue;
    _hsvColor = HSVColor.fromColor(widget.color);
  }

  @override
  void didUpdateWidget(ColorWheelWithSliders oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _red = widget.color.red;
      _green = widget.color.green;
      _blue = widget.color.blue;
      _hsvColor = HSVColor.fromColor(widget.color);
    }
  }

  void _updateFromRGB() {
    final newColor = Color.fromRGBO(_red, _green, _blue, 1.0);
    _hsvColor = HSVColor.fromColor(newColor);
    widget.onColorChanged(newColor);
  }

  void _updateFromHSV(HSVColor hsvColor) {
    final newColor = hsvColor.toColor();
    _red = newColor.red;
    _green = newColor.green;
    _blue = newColor.blue;
    _hsvColor = hsvColor;
    widget.onColorChanged(newColor);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Color preview
        Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: Color.fromRGBO(_red, _green, _blue, 1.0),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 1),
          ),
        ),
        const SizedBox(height: 16),

        // Color wheel
        SizedBox(
          width: 200,
          height: 200,
          child: ColorWheel(
            initialColor: _hsvColor,
            onColorChanged: _updateFromHSV,
          ),
        ),
        const SizedBox(height: 16),

        // Red slider
        Row(
          children: [
            const Text('R:', style: TextStyle(color: Colors.red)),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: _red.toDouble(),
                onChanged: (value) {
                  setState(() {
                    _red = value.round();
                    _updateFromRGB();
                  });
                },
                min: 0,
                max: 255,
                divisions: 255,
                label: _red.toString(),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(_red.toString(), textAlign: TextAlign.center),
            ),
          ],
        ),

        // Green slider
        Row(
          children: [
            const Text('G:', style: TextStyle(color: Colors.green)),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: _green.toDouble(),
                onChanged: (value) {
                  setState(() {
                    _green = value.round();
                    _updateFromRGB();
                  });
                },
                min: 0,
                max: 255,
                divisions: 255,
                label: _green.toString(),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(_green.toString(), textAlign: TextAlign.center),
            ),
          ],
        ),

        // Blue slider
        Row(
          children: [
            const Text('B:', style: TextStyle(color: Colors.blue)),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: _blue.toDouble(),
                onChanged: (value) {
                  setState(() {
                    _blue = value.round();
                    _updateFromRGB();
                  });
                },
                min: 0,
                max: 255,
                divisions: 255,
                label: _blue.toString(),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(_blue.toString(), textAlign: TextAlign.center),
            ),
          ],
        ),
      ],
    );
  }
}

// Color wheel widget
class ColorWheel extends StatefulWidget {
  final HSVColor initialColor;
  final ValueChanged<HSVColor> onColorChanged;

  const ColorWheel({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
  });

  @override
  _ColorWheelState createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  late HSVColor _currentColor;
  late Offset _selectorPosition;

  @override
  void initState() {
    super.initState();
    _currentColor = widget.initialColor;
    _updateSelectorPosition();
  }

  @override
  void didUpdateWidget(ColorWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialColor != widget.initialColor) {
      _currentColor = widget.initialColor;
      _updateSelectorPosition();
    }
  }

  void _updateSelectorPosition() {
    final hue = _currentColor.hue;
    final saturation = _currentColor.saturation;

    final angle = hue * pi / 180;
    final radius = saturation * 90;

    _selectorPosition = Offset(
      100 + radius * cos(angle),
      100 + radius * sin(angle),
    );
  }

  void _onPanUpdate(Offset localPosition) {
    const center = Offset(100, 100);
    final offset = localPosition - center;
    final distance = offset.distance;

    if (distance > 100) return;

    final angle = atan2(offset.dy, offset.dx);
    final hue = (angle * 180 / pi) % 360;
    final saturation = distance.clamp(0, 100) / 100;

    setState(() {
      _currentColor = HSVColor.fromAHSV(
        1.0,
        hue,
        saturation,
        _currentColor.value,
      );
      _selectorPosition = localPosition;
      widget.onColorChanged(_currentColor);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) => _onPanUpdate(details.localPosition),
      onPanUpdate: (details) => _onPanUpdate(details.localPosition),
      child: CustomPaint(
        size: const Size(200, 200),
        painter: ColorWheelPainter(),
        child: Stack(
          children: [
            Positioned(
              left: _selectorPosition.dx - 10,
              top: _selectorPosition.dy - 10,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  color: _currentColor.toColor(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Color wheel painter
class ColorWheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Draw the hue wheel with proper color distribution
    final hueShader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * pi,
      colors: const [
        Color(0xFFFF0000), // Red
        Color(0xFFFFFF00), // Yellow
        Color(0xFF00FF00), // Green
        Color(0xFF00FFFF), // Cyan
        Color(0xFF0000FF), // Blue
        Color(0xFFFF00FF), // Magenta
        Color(0xFFFF0000), // Back to Red
      ],
    ).createShader(rect);

    final huePaint = Paint()
      ..shader = hueShader
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, huePaint);

    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
