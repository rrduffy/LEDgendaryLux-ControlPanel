import 'package:flutter/material.dart';
import 'package:led_control_panel/ble_control_page.dart';
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
          titleTextStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      home: const ControlPanelScreen(),
      routes: {
        '/ble': (context) => const BleControlPage(),
      },
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

  final List<List<bool>> _selectedLEDs =
      List.generate(5, (_) => List.filled(5, false));
  final List<List<Color?>> _ledGrid =
      List.generate(5, (_) => List.filled(5, null));
  final List<List<double>> _brightnessGrid =
      List.generate(5, (_) => List.filled(5, 0.5));
  // Grid snapping (no overlap)
  final double _gridGap = 0.0; // spacing between tiles in layout mode

// Panel grid cell assignments
  final List<int?> _panelCells = List<int?>.filled(25, null);

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _trailController;
  late AnimationController _rainbowController;

  int _trailPosition = 0;
  int? _draggingPanelIndex;
  Offset _pointerOffsetInsidePanel = Offset.zero;
  List<List<double>> _trailBrightnessGrid =
      List.generate(5, (_) => List.filled(5, 0.0));
  List<List<Color>> _rainbowColors =
      List.generate(5, (_) => List.filled(5, Colors.transparent));
  List<Offset> _panelPositions = List.generate(25, (index) => Offset.zero);
  final List<List<bool>> _panelConnections =
      List.generate(25, (_) => List.filled(4, false));

  Future<void> _showColorPickerForSingleLED(int row, int col) async {


  Color tempColor = _ledGrid[row][col] ?? Colors.white;
  double tempBrightness = _brightnessGrid[row][col];
  bool applied = false;

  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Panel ${row * 5 + col + 1}'),
            content: SingleChildScrollView(
              child: Column(
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
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  applied = true;
                  Navigator.of(context).pop();
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
      _ledGrid[row][col] = tempColor;
      _brightnessGrid[row][col] = tempBrightness;
      _globalBrightness = tempBrightness;
    });
  }
}


  // Drag selection variables (grid selection, not panel layout)
  Offset? _dragStart;
  Offset? _dragEnd;
  bool _isDragging = false;

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
  return Duration(milliseconds: fastMs + ((slowMs - fastMs) * (1 - _effectSpeed)).toInt());
}

void _updateEffectSpeed(double speed) {
  if (!mounted) return;
  setState(() {
    _effectSpeed = speed;
    final newDuration = _calculateEffectDuration();
    for (final c in [_pulseController, _trailController, _rainbowController]) {
      c.duration = newDuration;
    }

    // Restart running animations to apply the new speed
    if (_pulseEnabled) _pulseController..stop()..repeat(reverse: true);
    if (_trailEnabled) _trailController..stop()..repeat();
    if (_rainbowEnabled) _rainbowController..stop()..repeat();
  });
}

void _updateGlobalBrightness(double brightness) {
  if (!mounted) return;
  setState(() {
    _globalBrightness = brightness;

    // Auto toggle LEDs if brightness hits 0 or recovers
    if (brightness == 0.0 && _ledsEnabled) {
      _toggleLEDs();
    } else if (brightness > 0.0 && !_ledsEnabled) {
      _toggleLEDs();
    }

    if (_ledsEnabled) {
      for (int i = 0; i < 5; i++) {
        for (int j = 0; j < 5; j++) {
          _brightnessGrid[i][j] = brightness;
        }
      }
    }
  });
}
void _initializePanels() async {
  // Optional: visual feedback for the user
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Initializing connected panels...'),
      duration: Duration(seconds: 2),
    ),
  );

  // TODO: send BLE command to ESP32 here once protocol is ready
  // Example (if you already have a BLE connection class):
  // await BleManager.instance.sendCommand("INIT_PANELS");

  // Simulate ESP response for now
  await Future.delayed(const Duration(seconds: 2));

  // Update UI — flash all active panels to confirm initialization
  setState(() {
    for (int i = 0; i < _ledGrid.length; i++) {
      for (int j = 0; j < _ledGrid[i].length; j++) {
        _ledGrid[i][j] = Colors.greenAccent;
        _brightnessGrid[i][j] = 0.8;
      }
    }
  });

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Initialization complete!'),
      duration: Duration(seconds: 2),
    ),
  );
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
    } else {
      _pulseController.stop();
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
      _trailController.repeat();
      _trailBrightnessGrid =
          List.generate(5, (_) => List.filled(5, 0.0));
    } else {
      _trailController.stop();
    }
  });
}

void _toggleRainbowEffect() {
  setState(() {
    _rainbowEnabled = !_rainbowEnabled;

    if (_rainbowEnabled) {
      for (int i = 0; i < 5; i++) {
        for (int j = 0; j < 5; j++) {
          _ledGrid[i][j] ??= Colors.white;
          _brightnessGrid[i][j] = 0.7;
        }
      }
      _rainbowController.repeat();
      _rainbowColors =
          List.generate(5, (_) => List.filled(5, Colors.transparent));
    } else {
      _rainbowController.stop();
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

  for (int i = 0; i < 5; i++) {
    for (int j = 0; j < 5; j++) {
      int index = i * 5 + j;
      int distance = (index - newPosition).abs();
      if (distance > 12) distance = 25 - distance;

      // Use adjustable fade length instead of fixed 6
      final fade = _trailFadeLength.clamp(1.0, 12.0);
      newBrightnessGrid[i][j] = (1.0 - (distance / fade)).clamp(0.0, 1.0);
    }
  }

  if (mounted) {
    setState(() {
      _trailPosition = newPosition;
      _trailBrightnessGrid = newBrightnessGrid;
    });
  }
}

bool _hasLitLEDs() {
  for (int i = 0; i < 5; i++) {
    for (int j = 0; j < 5; j++) {
      if (_ledGrid[i][j] != null) {
        return true;
      }
    }
  }
  return false;
}

void _toggleLEDs() {
  setState(() {
    _ledsEnabled = !_ledsEnabled;

    if (_ledsEnabled) {
      // Restore LEDs if none lit
      if (!_hasLitLEDs()) {
        for (int i = 0; i < 5; i++) {
          for (int j = 0; j < 5; j++) {
            _ledGrid[i][j] = Colors.white;
            _brightnessGrid[i][j] = _globalBrightness;
          }
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
  final newRainbowColors =
      List.generate(5, (_) => List.filled(5, Colors.transparent));

  for (int i = 0; i < 5; i++) {
    for (int j = 0; j < 5; j++) {
      final idx = i * 5 + j;
      final baseHue = (idx / 25 * 180 - hueShift) % 360;
      final hue = baseHue < 0 ? baseHue + 360 : baseHue;
      final color = HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor();
      newRainbowColors[i][j] = color;
    }
  }

  if (mounted) setState(() => _rainbowColors = newRainbowColors);
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

  // Handle drag selection (LED grid, not layout mode)
  void _handleDragStart(DragStartDetails details, Size gridSize) {


    final position =
        _getGridPositionFromOffset(details.localPosition, gridSize);
    if (position != null) {
      setState(() {
        _dragStart = details.localPosition;
        _dragEnd = details.localPosition;
        _isDragging = true;

        // Toggle the starting LED
        final (row, col) = position;
        _selectedLEDs[row][col] = !_selectedLEDs[row][col];

        // Update global brightness to match the first selected LED
        if (_selectedLEDs[row][col]) {
          _globalBrightness = _brightnessGrid[row][col];
        }
      });
    }
  }

  void _handleDragUpdate(DragUpdateDetails details, Size gridSize) {
    if (!_isDragging) return;

    setState(() {
      _dragEnd = details.localPosition;

      // Select all LEDs in the drag rectangle
      final startPos = _getGridPositionFromOffset(_dragStart!, gridSize);
      final endPos = _getGridPositionFromOffset(_dragEnd!, gridSize);

      if (startPos != null && endPos != null) {
        final (startRow, startCol) = startPos;
        final (endRow, endCol) = endPos;

        final minRow = min(startRow, endRow);
        final maxRow = max(startRow, endRow);
        final minCol = min(startCol, endCol);
        final maxCol = max(startCol, endCol);

        for (int i = minRow; i <= maxRow; i++) {
          for (int j = minCol; j <= maxCol; j++) {
            _selectedLEDs[i][j] = true;
          }
        }
      }
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_isDragging) return;

    setState(() {
      _isDragging = false;
      _dragStart = null;
      _dragEnd = null;
    });
  }

  Future<void> _handleLEDTap(int row, int col) async {


    // Always in multi-select mode, so toggle selection on tap
    setState(() {
      _selectedLEDs[row][col] = !_selectedLEDs[row][col];

      // Update global brightness to match the selected LED
      if (_selectedLEDs[row][col]) {
        _globalBrightness = _brightnessGrid[row][col];
      }
    });
  }

  void _applyToSelectedLEDs(Color color, double brightness) {

    setState(() {
      for (int i = 0; i < 5; i++) {
        for (int j = 0; j < 5; j++) {
          if (_selectedLEDs[i][j]) {
            _ledGrid[i][j] = color;
            _brightnessGrid[i][j] = brightness;
          }
        }
      }

      // Update global brightness to match the applied brightness
      _globalBrightness = brightness;

      // Clear the selection after applying color
      for (int i = 0; i < 5; i++) {
        for (int j = 0; j < 5; j++) {
          _selectedLEDs[i][j] = false;
        }
      }
    });
  }

  void _selectAllLEDs(bool select) {

    setState(() {
      for (var row in _selectedLEDs) {
        for (var i = 0; i < row.length; i++) {
          row[i] = select;
        }
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
  icon: const Icon(Icons.power_settings_new, color: Colors.orangeAccent),
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
          icon: const Icon(Icons.settings_bluetooth, color: Colors.lightBlueAccent),
          tooltip: 'Bluetooth Controls',
          onPressed: () => Navigator.pushNamed(context, '/ble'),
        ),
            if (_isLayoutMode)
      IconButton(
        icon: const Icon(Icons.power_settings_new, color: Colors.orangeAccent),
        tooltip: 'Initialize Panels',
        onPressed: _initializePanels,
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
          icon: Icon(
            _ledsEnabled ? Icons.toggle_on : Icons.toggle_off,
            color: _ledsEnabled ? Colors.greenAccent : Colors.grey,
          ),
          tooltip: _ledsEnabled ? 'Turn LEDs Off' : 'Turn LEDs On',
          onPressed: _toggleLEDs,
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
                    const Text('Selection Tools',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                        for (int i = 0; i < 5; i++) {
                          for (int j = 0; j < 5; j++) {
                            if (_selectedLEDs[i][j] && _ledGrid[i][j] != null) {
                              defaultColor = _ledGrid[i][j]!;
                              defaultBrightness = _brightnessGrid[i][j];
                              break outerLoop;
                            }
                          }
                        }
                        _showColorPickerForMultiSelect(defaultColor, defaultBrightness);
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
                      const Text('Layout Tools',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                        onPressed: () => setState(() => _activePanels.clear()),
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
    child: AspectRatio(
      aspectRatio: 1,
      child: _isLayoutMode
          ? _buildLayoutModeView()
          : _buildGridView(),
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

Widget _buildBrightnessControl() {
  return Card(
    margin: const EdgeInsets.all(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          const Text('Brightness',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Slider(
            value: _globalBrightness,
            onChanged: _updateGlobalBrightness,
            min: 0.0,
            max: 1.0,
            divisions: 100,
          ),
          Text('${(_globalBrightness * 100).round()}%',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
              Text('Slow', style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text('Fast', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                Text('Short', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('Long', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
          Text('Effects',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

Widget _buildWarning(String message) {
  return Positioned(
    bottom: 40,
    left: MediaQuery.of(context).size.width / 2 - 150,
    child: AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        width: 300,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.orange.shade800.withOpacity(0.9),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black45)],
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    ),
  );
}

Widget _buildGridView() {
  return LayoutBuilder(
    builder: (context, constraints) {
      final gridSize = Size(constraints.maxWidth, constraints.maxWidth);
      final cellSize = (gridSize.width - 16) / 5;
      return AnimatedBuilder(
        animation: Listenable.merge([
          _pulseAnimation,
          _trailController,
          _rainbowController,
        ]),
        builder: (context, _) {
          return GestureDetector(
            onPanStart: (details) => _handleDragStart(details, gridSize),
            onPanUpdate: (details) => _handleDragUpdate(details, gridSize),
            onPanEnd: _handleDragEnd,
            child: Container(
              width: gridSize.width,
              height: gridSize.width,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (row) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (col) {
                      final isSelected = _selectedLEDs[row][col];

                      // base color/brightness
                      Color? baseColor = _ledGrid[row][col];
                      double brightness = _brightnessGrid[row][col];

                      // if rainbow is on, override color from rainbow buffer
                      if (_rainbowEnabled) {
                        baseColor = _rainbowColors[row][col];
                      }

                      // if LEDs are off, show "off" look
                      if (!_ledsEnabled) {
                        baseColor = null;
                      }

                      // start from a neutral default
                      Color displayColor = Colors.grey.shade900;

                      if (baseColor != null) {
  var hsv = HSVColor.fromColor(baseColor);

  // Combine base brightness + trail brightness smoothly
  double trailFactor = _trailEnabled ? _trailBrightnessGrid[row][col] : 1.0;
  double pulseFactor = _pulseEnabled ? _pulseAnimation.value : 1.0;

  // Blend brightness * trail * pulse for intensity
  double combinedValue =
      (brightness * trailFactor * pulseFactor).clamp(0.0, 1.0);

  // Apply to the HSV brightness channel instead of just opacity
  hsv = hsv.withValue(combinedValue);
  displayColor = hsv.toColor();
}

                      return GestureDetector(
                        onTap: () => _handleLEDTap(row, col),
                        onLongPress: () =>
                            _showColorPickerForSingleLED(row, col),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: cellSize - 4,
                          height: cellSize - 4,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: baseColor == null
                                ? Colors.grey.shade900
                                : displayColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.amberAccent
                                  : Colors.white24,
                              width: isSelected ? 2.5 : 1,
                            ),
                            boxShadow: [
                              if (_pulseEnabled &&
                                  _ledsEnabled &&
                                  baseColor != null)
                                BoxShadow(
                                  color: displayColor.withOpacity((_pulseAnimation.value * 0.8).clamp(0.0, 1.0)),

                                  blurRadius: 15 * _pulseAnimation.value,
                                  spreadRadius: 1.5,
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ),
          );
        },
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
              final row = index ~/ 5;
              final col = index % 5;

              Color? color = _ledGrid[row][col];
              if (!_ledsEnabled) color = null;

              final brightness = _brightnessGrid[row][col];
              final isSelected = _selectedLEDs[row][col];

              final pulseValue = _pulseEnabled ? _pulseAnimation.value : 1.0;
              final trailValue =
                  _trailEnabled ? _trailBrightnessGrid[row][col] : 1.0;

              if (_rainbowEnabled) {
                color = _rainbowColors[row][col];
              }

              final effectiveBrightness =
                  brightness * pulseValue * trailValue;

              return Positioned(
                left: pos.dx,
                top: pos.dy,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedLEDs[row][col] = !_selectedLEDs[row][col];
                      if (_selectedLEDs[row][col]) {
                        _globalBrightness = _brightnessGrid[row][col];
                      }
                    });
                  },
                  onLongPress: () => _showColorPickerForSingleLED(row, col),
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
                      color: color?.withOpacity(effectiveBrightness) ??
                          Colors.grey[800],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? Colors.amberAccent : Colors.white24,
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
                          fontSize: 10),
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
    Color initialColor, double initialBrightness) async {


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
      _currentColor =
          HSVColor.fromAHSV(1.0, hue, saturation, _currentColor.value);
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