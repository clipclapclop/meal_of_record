import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:meal_of_record/utils/permission_utils.dart';

/// A full-screen barcode scanner that returns the scanned barcode string.
/// Returns null if the user cancels or an error occurs.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController? _scannerController;
  bool _hasPermission = false;
  bool _permissionDenied = false;
  bool _isPermanentlyDenied = false;
  bool _isProcessing = false;
  bool _showFlash = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final hasPermission = await PermissionUtils.checkCameraPermission();
    if (hasPermission) {
      _initializeScanner();
      return;
    }

    // Request permission
    final granted = await PermissionUtils.requestCameraPermission();
    if (granted) {
      _initializeScanner();
      return;
    }

    // Check if permanently denied
    final permanentlyDenied =
        await PermissionUtils.isCameraPermissionPermanentlyDenied();

    if (mounted) {
      setState(() {
        _permissionDenied = true;
        _isPermanentlyDenied = permanentlyDenied;
      });
    }
  }

  void _initializeScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );

    if (mounted) {
      setState(() {
        _hasPermission = true;
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue == null || rawValue.isEmpty) continue;

      // Found a valid barcode
      _handleBarcodeFound(rawValue);
      return;
    }
  }

  Future<void> _handleBarcodeFound(String barcode) async {
    // Prevent multiple detections
    setState(() {
      _isProcessing = true;
    });

    // Stop the scanner
    await _scannerController?.stop();

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Show flash animation
    setState(() {
      _showFlash = true;
    });

    // Wait for flash animation
    await Future.delayed(const Duration(milliseconds: 250));

    if (mounted) {
      // Return the barcode
      Navigator.pop(context, barcode);
    }
  }

  Future<void> _openSettings() async {
    await PermissionUtils.openSettings();
    // Recheck permission when returning from settings
    if (mounted) {
      _checkPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Scanner or permission UI
          if (_hasPermission && _scannerController != null)
            _buildScannerView()
          else if (_permissionDenied)
            _buildPermissionDeniedView()
          else if (_errorMessage != null)
            _buildErrorView()
          else
            _buildLoadingView(),

          // Flash overlay
          if (_showFlash)
            AnimatedOpacity(
              opacity: _showFlash ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Container(color: Colors.grey[400]),
            ),

          // Back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        // Camera view
        MobileScanner(
          controller: _scannerController!,
          onDetect: _onDetect,
          errorBuilder: (context, error, child) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'Camera error: ${error.errorCode}',
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      _scannerController?.start();
                    },
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            );
          },
        ),

        // Scanning overlay
        _buildScanningOverlay(),
      ],
    );
  }

  Widget _buildScanningOverlay() {
    return Column(
      children: [
        // Top dark area
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.black.withValues(alpha: 0.5),
            alignment: Alignment.bottomCenter,
            child: const Padding(
              padding: EdgeInsets.only(bottom: 16.0),
              child: Text(
                'Point camera at barcode',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),

        // Scan area with border
        SizedBox(
          height: 200,
          child: Row(
            children: [
              Expanded(
                child: Container(color: Colors.black.withValues(alpha: 0.5)),
              ),
              Container(
                width: 280,
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              Expanded(
                child: Container(color: Colors.black.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),

        // Bottom dark area
        Expanded(
          flex: 3,
          child: Container(color: Colors.black.withValues(alpha: 0.5)),
        ),
      ],
    );
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_outlined, color: Colors.grey, size: 80),
            const SizedBox(height: 16),
            const Text(
              'Camera Permission Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _isPermanentlyDenied
                  ? 'Camera access has been denied. Please enable it in Settings to scan barcodes.'
                  : 'Camera access is needed to scan barcodes.',
              style: const TextStyle(color: Colors.grey, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 80),
            const SizedBox(height: 16),
            const Text(
              'Camera Error',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'An unknown error occurred',
              style: const TextStyle(color: Colors.grey, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                });
                _checkPermission();
              },
              child: const Text('Try Again'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            'Initializing camera...',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
