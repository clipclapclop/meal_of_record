import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:meal_of_record/utils/permission_utils.dart';

/// A camera screen with a square viewfinder for taking food photos.
/// Returns the captured file path via Navigator.pop, or null on cancel.
class SquareCameraScreen extends StatefulWidget {
  const SquareCameraScreen({super.key});

  @override
  State<SquareCameraScreen> createState() => _SquareCameraScreenState();
}

class _SquareCameraScreenState extends State<SquareCameraScreen> {
  CameraController? _controller;
  bool _hasPermission = false;
  bool _permissionDenied = false;
  bool _isPermanentlyDenied = false;
  bool _isTakingPhoto = false;
  String? _errorMessage;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final hasPermission = await PermissionUtils.checkCameraPermission();
    if (hasPermission) {
      _initializeCamera();
      return;
    }

    final granted = await PermissionUtils.requestCameraPermission();
    if (granted) {
      _initializeCamera();
      return;
    }

    final permanentlyDenied =
        await PermissionUtils.isCameraPermissionPermanentlyDenied();

    if (mounted) {
      setState(() {
        _permissionDenied = true;
        _isPermanentlyDenied = permanentlyDenied;
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = 'No cameras available';
          });
        }
        return;
      }

      // Prefer back camera
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();

      if (mounted) {
        setState(() {
          _controller = controller;
          _hasPermission = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize camera: $e';
        });
      }
    }
  }

  Future<void> _takePicture() async {
    if (_isTakingPhoto ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return;
    }

    setState(() {
      _isTakingPhoto = true;
    });

    try {
      final xFile = await _controller!.takePicture();
      if (mounted) {
        Navigator.pop(context, xFile.path);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to take photo: $e')));
      }
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_controller == null) return;
    final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if (newZoom != _currentZoom) {
      _currentZoom = newZoom;
      _controller!.setZoomLevel(_currentZoom);
    }
  }

  Future<void> _openSettings() async {
    await PermissionUtils.openSettings();
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
          if (_hasPermission &&
              _controller != null &&
              _controller!.value.isInitialized)
            _buildCameraView()
          else if (_permissionDenied)
            _buildPermissionDeniedView()
          else if (_errorMessage != null)
            _buildErrorView()
          else
            _buildLoadingView(),

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

  Widget _buildCameraView() {
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      children: [
        // Top spacer
        const Expanded(flex: 1, child: SizedBox()),

        // Square viewfinder
        GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          child: SizedBox(
            width: screenWidth,
            height: screenWidth,
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.previewSize!.height,
                  height: _controller!.value.previewSize!.width,
                  child: CameraPreview(_controller!),
                ),
              ),
            ),
          ),
        ),

        // Bottom area with shutter button
        Expanded(
          flex: 1,
          child: Center(
            child: GestureDetector(
              onTap: _isTakingPhoto ? null : _takePicture,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isTakingPhoto ? Colors.grey : Colors.white,
                    width: 4,
                  ),
                ),
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isTakingPhoto ? Colors.grey : Colors.white,
                  ),
                ),
              ),
            ),
          ),
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
                  ? 'Camera access has been denied. Please enable it in Settings to take photos.'
                  : 'Camera access is needed to take photos.',
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
