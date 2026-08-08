import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/image_storage_service.dart';
import 'package:meal_of_record/widgets/screen_background.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QrPortionSharingScreen extends StatefulWidget {
  /// Portions to share (export mode). Null means import/scan mode.
  final List<FoodPortion>? portions;

  const QrPortionSharingScreen({super.key, this.portions});

  @override
  State<QrPortionSharingScreen> createState() => _QrPortionSharingScreenState();
}

class _QrPortionSharingScreenState extends State<QrPortionSharingScreen> {
  static const String _prefKey = 'share_include_images';
  static const int _chunkSize = 600;

  // Export state
  List<String> _qrChunks = [];
  int _currentChunkIndex = 0;
  Timer? _animTimer;
  bool _isAnimating = true;
  bool _includeImages = true;
  bool _isPreparingExport = false;

  // Import state
  MobileScannerController? _scannerController;
  bool _isScanning = true;
  final Map<int, String> _receivedChunks = {};
  int? _totalChunks;
  String? _statusMessage;

  bool get _isExport => widget.portions != null;

  @override
  void initState() {
    super.initState();
    if (_isExport) {
      _loadPrefsAndExport();
    } else {
      _scannerController = MobileScannerController();
    }
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _loadPrefsAndExport() async {
    final prefs = await SharedPreferences.getInstance();
    _includeImages = prefs.getBool(_prefKey) ?? true;
    await _prepareExport();
  }

  Future<void> _prepareExport() async {
    setState(() => _isPreparingExport = true);

    final jsonStr = await _serializePortions(
      widget.portions!,
      includeImages: _includeImages,
    );

    final chunks = _buildChunks(jsonStr);

    if (mounted) {
      setState(() {
        _qrChunks = chunks;
        _currentChunkIndex = 0;
        _isPreparingExport = false;
        if (chunks.length > 1) {
          _startAnimation();
        }
      });
    }
  }

  Future<String> _serializePortions(
    List<FoodPortion> portions, {
    required bool includeImages,
  }) async {
    final foods = <Map<String, dynamic>>[];
    final portionsList = <Map<String, dynamic>>[];
    final images = <String, String>{};
    final imgService = ImageStorageService.instance;

    // Deduplicate foods by building a map keyed on (id, source)
    final foodMap = <String, Food>{};
    for (final p in portions) {
      final key = '${p.food.id}_${p.food.source}';
      foodMap[key] = p.food;
    }

    for (final entry in foodMap.entries) {
      var food = entry.value;

      if (includeImages && food.thumbnail != null) {
        final guid = imgService.extractGuid(food.thumbnail!);
        if (guid != null && !images.containsKey(guid)) {
          final b64 = await imgService.encodeImageToBase64(guid);
          if (b64 != null) {
            images[guid] = b64;
          }
        }
      }

      final foodJson = food.toJson();

      if (!includeImages) {
        // Strip local: thumbnail refs, keep valid URLs
        final thumb = foodJson['thumbnail'] as String?;
        if (thumb != null && !thumb.startsWith('http')) {
          foodJson['thumbnail'] = null;
        }
      }

      foods.add(foodJson);
    }

    for (final p in portions) {
      portionsList.add({
        'food_key': '${p.food.id}_${p.food.source}',
        'grams': p.grams,
        'unit': p.unit,
      });
    }

    final data = <String, dynamic>{
      'type': 'portions',
      'foods': foods,
      'portions': portionsList,
    };

    if (includeImages && images.isNotEmpty) {
      data['images'] = images;
    }

    return jsonEncode(data);
  }

  List<String> _buildChunks(String jsonStr) {
    if (jsonStr.length <= _chunkSize) {
      return ['1/1|$jsonStr'];
    }
    final total = (jsonStr.length / _chunkSize).ceil();
    final chunks = <String>[];
    for (int i = 0; i < total; i++) {
      int end = (i + 1) * _chunkSize;
      if (end > jsonStr.length) end = jsonStr.length;
      final sub = jsonStr.substring(i * _chunkSize, end);
      chunks.add('${i + 1}/$total|$sub');
    }
    return chunks;
  }

  void _startAnimation() {
    _animTimer?.cancel();
    _animTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (!mounted) return;
      setState(() {
        _currentChunkIndex = (_currentChunkIndex + 1) % _qrChunks.length;
      });
    });
  }

  void _toggleAnimation() {
    setState(() {
      _isAnimating = !_isAnimating;
      if (_isAnimating) {
        _startAnimation();
      } else {
        _animTimer?.cancel();
      }
    });
  }

  Future<void> _toggleIncludeImages(bool value) async {
    setState(() => _includeImages = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    _animTimer?.cancel();
    await _prepareExport();
  }

  // --- Import logic ---

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue == null) continue;

      int index = 1;
      int total = 1;
      String data = rawValue;

      if (rawValue.contains('|') && rawValue.contains('/')) {
        try {
          final parts = rawValue.split('|');
          final header = parts[0];
          data = parts.sublist(1).join('|');
          final headerParts = header.split('/');
          index = int.parse(headerParts[0]);
          total = int.parse(headerParts[1]);
        } catch (_) {
          index = 1;
          total = 1;
          data = rawValue;
        }
      }

      if (_totalChunks == null) {
        setState(() => _totalChunks = total);
      } else if (_totalChunks != total) {
        continue;
      }

      if (!_receivedChunks.containsKey(index)) {
        setState(() {
          _receivedChunks[index] = data;
          _statusMessage = 'Received part $index of $total';
        });

        if (_receivedChunks.length == total) {
          _finishScanning();
        }
      }
    }
  }

  Future<void> _finishScanning() async {
    setState(() {
      _isScanning = false;
      _statusMessage = 'Processing...';
    });

    final sb = StringBuffer();
    for (int i = 1; i <= (_totalChunks ?? 1); i++) {
      sb.write(_receivedChunks[i] ?? '');
    }
    final fullJson = sb.toString();

    try {
      final data = jsonDecode(fullJson) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'portions') {
        await _importPortions(data);
      } else {
        // Not a portions payload – could be a recipe. Show error here.
        setState(() {
          _isScanning = true;
          _receivedChunks.clear();
          _totalChunks = null;
          _statusMessage = 'Not a portions QR. Try the recipe scanner.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = true;
          _receivedChunks.clear();
          _totalChunks = null;
          _statusMessage = 'Import failed: $e';
        });
      }
    }
  }

  Future<void> _importPortions(Map<String, dynamic> data) async {
    final imgService = ImageStorageService.instance;
    final guidMap = <String, String>{};

    // Import images
    if (data.containsKey('images')) {
      final images = Map<String, String>.from(data['images']);
      for (final entry in images.entries) {
        final newGuid = await imgService.saveImageFromBase64(entry.value);
        guidMap[entry.key] = newGuid;
      }
    }

    // Build food lookup
    final foodList = (data['foods'] as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();

    final foodLookup = <String, Food>{};
    for (final foodJson in foodList) {
      // Replace image GUIDs
      var jsonStr = jsonEncode(foodJson);
      for (final entry in guidMap.entries) {
        jsonStr = jsonStr.replaceAll(entry.key, entry.value);
      }
      final processed = jsonDecode(jsonStr) as Map<String, dynamic>;
      final food = Food.fromJson(processed);

      // Ensure food exists in local database
      final db = DatabaseService.instance;
      final resolvedFood = await db.ensureFoodExists(food);
      foodLookup['${food.id}_${food.source}'] = resolvedFood;
    }

    // Build portions
    final portionsList = (data['portions'] as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();

    if (!mounted) return;
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    int count = 0;

    for (final pJson in portionsList) {
      final foodKey = pJson['food_key'] as String;
      final grams = (pJson['grams'] as num).toDouble();
      final unit = pJson['unit'] as String;
      final food = foodLookup[foodKey];
      if (food != null) {
        logProvider.addFoodToQueue(
          FoodPortion(food: food, grams: grams, unit: unit),
        );
        count++;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added $count items to queue')));
      Navigator.pop(context);
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return ScreenBackground(
      appBar: AppBar(
        title: Text(_isExport ? 'Share Portions' : 'Scan Portions'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      child: _isExport ? _buildExportView() : _buildImportView(),
    );
  }

  Widget _buildExportView() {
    if (_isPreparingExport || _qrChunks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = _qrChunks[_currentChunkIndex];
    final total = _qrChunks.length;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: data,
            version: QrVersions.auto,
            size: 280.0,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        // Thumbnail toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SwitchListTile(
            title: const Text('Include images'),
            value: _includeImages,
            onChanged: _toggleIncludeImages,
            dense: true,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.portions!.length} item${widget.portions!.length == 1 ? '' : 's'} '
          '• $total chunk${total == 1 ? '' : 's'}',
          style: const TextStyle(color: Colors.grey),
        ),
        if (total > 1) ...[
          const SizedBox(height: 8),
          Text(
            'Part ${_currentChunkIndex + 1} of $total',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          IconButton(
            icon: Icon(
              _isAnimating
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              size: 48,
              color: Colors.blue,
            ),
            onPressed: _toggleAnimation,
          ),
          const Padding(
            padding: EdgeInsets.all(12.0),
            child: Text(
              'Multiple QR codes needed. The recipient must keep scanning until all parts are captured.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImportView() {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: _scannerController!,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(child: Text('Camera error: $error'));
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16.0),
          color: Colors.grey[900],
          width: double.infinity,
          child: Column(
            children: [
              Text(
                _statusMessage ?? 'Point camera at a portions QR code',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              if (_totalChunks != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _receivedChunks.length / _totalChunks!,
                  backgroundColor: Colors.grey[800],
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
