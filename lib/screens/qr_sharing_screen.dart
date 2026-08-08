import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:meal_of_record/models/recipe.dart';
import 'package:meal_of_record/providers/recipe_provider.dart';
import 'package:meal_of_record/screens/qr_portion_sharing_screen.dart';
import 'package:meal_of_record/widgets/screen_background.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrSharingScreen extends StatefulWidget {
  final Recipe? recipeToShare;

  const QrSharingScreen({super.key, this.recipeToShare});

  @override
  State<QrSharingScreen> createState() => _QrSharingScreenState();
}

class _QrSharingScreenState extends State<QrSharingScreen>
    with SingleTickerProviderStateMixin {
  // Export State
  List<String> _qrChunks = [];
  int _currentChunkIndex = 0;
  Timer? _animTimer;
  bool _isAnimating = true;

  // Import State
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isScanning = true;
  final Map<int, String> _receivedChunks = {};
  int? _totalChunks;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    if (widget.recipeToShare != null) {
      _prepareExport();
    }
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _prepareExport() async {
    final recipeProvider = Provider.of<RecipeProvider>(context, listen: false);
    final jsonStr = await recipeProvider.exportRecipe(widget.recipeToShare!);

    // Naive chunking strategy: ~800 chars per chunk to be safe for standard QR
    // Header format: "current_index/total_chunks|data"
    // e.g. "1/3|..."

    // Better yet, use a compressed format if we were fancy, but simple string split works for MVP.
    // Let's use 600 chars to be safe with base64 overhead if we added it later.
    const chunkSize = 600;
    final chunks = <String>[];

    if (jsonStr.length <= chunkSize) {
      chunks.add('1/1|$jsonStr');
    } else {
      int total = (jsonStr.length / chunkSize).ceil();
      for (int i = 0; i < total; i++) {
        int end = (i + 1) * chunkSize;
        if (end > jsonStr.length) end = jsonStr.length;
        final sub = jsonStr.substring(i * chunkSize, end);
        chunks.add('${i + 1}/$total|$sub');
      }
    }

    if (mounted) {
      setState(() {
        _qrChunks = chunks;
        if (chunks.length > 1) {
          _startAnimation();
        }
      });
    }
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

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue == null) continue;

      // Parse our format "index/total|data"
      // If it's just raw JSON (legacy/simple), treat as 1/1

      int index = 1;
      int total = 1;
      String data = rawValue;

      if (rawValue.contains('|') && rawValue.contains('/')) {
        try {
          final parts = rawValue.split('|');
          final header = parts[0]; // "1/3"
          data = parts
              .sublist(1)
              .join('|'); // Rejoin rest in case data had pipes

          final headerParts = header.split('/');
          index = int.parse(headerParts[0]);
          total = int.parse(headerParts[1]);
        } catch (e) {
          // Fallback to treating as single chunk
          index = 1;
          total = 1;
          data = rawValue;
        }
      }

      // Initialize total expectation
      if (_totalChunks == null) {
        setState(() {
          _totalChunks = total;
        });
      } else if (_totalChunks != total) {
        // Mismatch in stream? Reset or ignore.
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

    // Reassemble
    final sb = StringBuffer();
    for (int i = 1; i <= (_totalChunks ?? 1); i++) {
      sb.write(_receivedChunks[i] ?? '');
    }
    final fullJson = sb.toString();

    // Detect portions format and redirect
    try {
      final decoded = jsonDecode(fullJson) as Map<String, dynamic>;
      if (decoded['type'] == 'portions') {
        if (!mounted) return;
        // Navigate to the portions import screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const QrPortionSharingScreen()),
        );
        return;
      }
    } catch (_) {
      // Not valid JSON or not portions format — continue with recipe import
    }

    final recipeProvider = Provider.of<RecipeProvider>(context, listen: false);
    final newId = await recipeProvider.importRecipe(fullJson);

    if (!mounted) return;

    if (newId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recipe imported successfully!')),
      );
      Navigator.pop(context, newId);
    } else {
      setState(() {
        _isScanning = true;
        _receivedChunks.clear();
        _totalChunks = null;
        _statusMessage = 'Import failed. tap to retry or scan again.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(recipeProvider.errorMessage ?? 'Unknown error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExport = widget.recipeToShare != null;

    return ScreenBackground(
      appBar: AppBar(
        title: Text(isExport ? 'Share Recipe' : 'Scan Recipe'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      child: isExport ? _buildExportView() : _buildImportView(),
    );
  }

  Widget _buildExportView() {
    if (_qrChunks.isEmpty) {
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
        if (total > 1) ...[
          Text(
            'Part ${_currentChunkIndex + 1} of $total',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
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
              'This recipe is large, so it is split into multiple QR codes. The recipient needs to keep scanning until all parts are captured.',
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
            controller: _scannerController,
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
                _statusMessage ?? 'Point camera at a recipe QR code',
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
