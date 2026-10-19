import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

class SnapshotScanScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const SnapshotScanScreen({super.key, required this.cameras});

  @override
  State<SnapshotScanScreen> createState() => _SnapshotScanScreenState();
}

class _SnapshotScanScreenState extends State<SnapshotScanScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isScanning = false;
  XFile? _capturedImage;
  Uint8List? _processedImageBytes;

  List<dynamic> _detectedItems = [];
  String _shiftInfoText =
      "Arahkan kamera ke objek, lalu tekan tombol untuk mengambil foto.";

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;

    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      setState(() {
        _shiftInfoText = "Gagal menginisialisasi kamera: $e";
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndScan() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _shiftInfoText = "Memproses gambar dengan AI...";
      _detectedItems = [];
      _processedImageBytes = null;
    });

    try {
      XFile imageFile = await _controller!.takePicture();
      Uint8List imageBytes = await imageFile.readAsBytes();

      setState(() {
        _capturedImage = imageFile;
      });

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/predict'),
      );

      request.headers.addAll(AppConfig.headers);

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'snapshot.jpg',
        ),
      );

      var streamedResponse =
          await request.send().timeout(const Duration(seconds: 10));
      var responseBody = await streamedResponse.stream.bytesToString();

      if (!mounted) return;

      if (streamedResponse.statusCode == 200) {
        var data = jsonDecode(responseBody);
        String shiftName = data['shift_name'] ?? '-';
        int totalDetected = data['total_detected'] ?? data['total_in_screen'] ?? 0;
        var detections = data['detections'] as List<dynamic>? ?? [];

        Uint8List? decodedBytes;
        if (data['image_base64'] != null) {
          decodedBytes = base64Decode(data['image_base64']);
        }

        setState(() {
          _processedImageBytes = decodedBytes;
          _detectedItems = detections;
          if (detections.isEmpty) {
            _shiftInfoText = "Shift: $shiftName | Tidak ada objek valid terdeteksi.";
          } else {
            _shiftInfoText = "Shift: $shiftName | Total Terdeteksi: $totalDetected objek";
          }
        });
      } else {
        setState(() {
          _shiftInfoText = "Error Server (${streamedResponse.statusCode}): $responseBody";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _shiftInfoText = "Gagal terhubung ke API: Cek koneksi server ($e)";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedImage = null;
      _processedImageBytes = null;
      _detectedItems = [];
      _shiftInfoText = "Arahkan kamera ke objek, lalu tekan tombol untuk mengambil foto.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pindai Foto Manual', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: !_isCameraInitialized
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                    child: _capturedImage == null
                        ? CameraPreview(_controller!)
                        : (_processedImageBytes != null
                            ? Image.memory(_processedImageBytes!, fit: BoxFit.contain)
                            : Image.memory(_processedImageBytes!, fit: BoxFit.cover)),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.teal.shade100),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _shiftInfoText,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.teal.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Divider(height: 12),
                                Expanded(
                                  child: _detectedItems.isNotEmpty
                                      ? ListView.builder(
                                          itemCount: _detectedItems.length,
                                          itemBuilder: (context, index) {
                                            final item = _detectedItems[index];
                                            final name = item['nama_barang'] ?? item['class_name'] ?? 'Objek';
                                            final confidenceStr = item['persen_kepercayaan'] ??
                                                "${((item['confidence'] ?? 0.0) * 100).toStringAsFixed(1)}%";

                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 3.0),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    "• $name",
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: Colors.teal.shade900,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  Text(
                                                    confidenceStr,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: Colors.green,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        )
                                      : Center(
                                          child: Text(
                                            _isScanning ? "Memindai gambar..." : "Belum ada hasil pemindaian.",
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.teal.shade700,
                                              fontStyle: FontStyle.italic,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _capturedImage == null
                            ? ElevatedButton.icon(
                                onPressed: _isScanning ? null : _captureAndScan,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: _isScanning
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.camera_alt),
                                label: Text(
                                  _isScanning ? "Memproses..." : "Ambil Foto & Pindai",
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: _retakePhoto,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.refresh),
                                label: const Text(
                                  "Foto Ulang",
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}