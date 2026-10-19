import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

class LiveScanScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const LiveScanScreen({super.key, required this.cameras});

  @override
  State<LiveScanScreen> createState() => _LiveScanScreenState();
}

class _LiveScanScreenState extends State<LiveScanScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isScanning = false;
  bool _isLoopActive = true;
  bool _isPanelExpanded = false;

  Uint8List? _processedImageBytes;
  List<dynamic> _detectedItems = [];
  String _scanStatusMessage = "Mempersiapkan kamera live...";

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      if (widget.cameras.isNotEmpty) {
        _controller = CameraController(
          widget.cameras[0],
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await _controller!.initialize();
        if (!mounted) return;
        setState(() {
          _isCameraInitialized = true;
          _scanStatusMessage = "Deteksi otomatis berjalan...";
        });

        _startAutoScanLoop();
      } else {
        if (!mounted) return;
        setState(() {
          _scanStatusMessage = "Tidak ada kamera yang tersedia pada perangkat.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanStatusMessage = "Gagal menginisialisasi kamera: $e";
      });
    }
  }

  Future<void> _startAutoScanLoop() async {
    while (_isLoopActive && mounted) {
      if (_controller != null &&
          _controller!.value.isInitialized &&
          !_isScanning) {
        await _captureAndScan();
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
  }

  @override
  void dispose() {
    _isLoopActive = false;
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndScan() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    _isScanning = true;

    try {
      XFile imageFile = await _controller!.takePicture();
      Uint8List imageBytes = await imageFile.readAsBytes();

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/predict'),
      );

      request.headers.addAll(AppConfig.headers);

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'live_frame.jpg',
        ),
      );

      var streamedResponse =
          await request.send().timeout(const Duration(seconds: 10));
      var responseBody = await streamedResponse.stream.bytesToString();

      if (!mounted) return;

      if (streamedResponse.statusCode == 200) {
        var data = jsonDecode(responseBody);

        Uint8List? decodedBytes;
        if (data['image_base64'] != null) {
          decodedBytes = base64Decode(data['image_base64']);
        }

        setState(() {
          _processedImageBytes = decodedBytes;
          _detectedItems = data['detections'] ?? [];
          int newAdded = data['new_counted_items'] ?? 0;

          if (_detectedItems.isEmpty) {
            _scanStatusMessage = "Arahkan kamera ke objek...";
          } else if (newAdded > 0) {
            _scanStatusMessage = "➕ Stok bertambah +$newAdded (${data['shift_name'] ?? 'Shift'})";
          } else {
            _scanStatusMessage = "Tersimpan di layar (${_detectedItems.length} barang)";
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanStatusMessage = "Koneksi terputus: Cek server...";
      });
    } finally {
      if (mounted) {
        _isScanning = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Pindai Barang Live",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: !_isCameraInitialized
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      if (_isPanelExpanded) {
                        setState(() => _isPanelExpanded = false);
                      }
                    },
                    child: _processedImageBytes != null
                        ? Image.memory(
                            _processedImageBytes!,
                            fit: BoxFit.contain,
                          )
                        : CameraPreview(_controller!),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: GestureDetector(
                    onVerticalDragUpdate: (details) {
                      if (details.delta.dy < -5) {
                        setState(() => _isPanelExpanded = true);
                      } else if (details.delta.dy > 5) {
                        setState(() => _isPanelExpanded = false);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, -3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              setState(
                                  () => _isPanelExpanded = !_isPanelExpanded);
                            },
                            child: Container(
                              width: 40,
                              height: 5,
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white54,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          if (!_isPanelExpanded)
                            InkWell(
                              onTap: () =>
                                  setState(() => _isPanelExpanded = true),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.keyboard_arrow_up,
                                      color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text(
                                    _scanStatusMessage,
                                    style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          if (_isPanelExpanded) ...[
                            Text(
                              _scanStatusMessage,
                              style: const TextStyle(
                                  color: Colors.greenAccent, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            if (_detectedItems.isNotEmpty)
                              Container(
                                constraints:
                                    const BoxConstraints(maxHeight: 150),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _detectedItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _detectedItems[index];
                                    final String namaBarang =
                                        item['nama_barang'] ??
                                            item['class_name'] ??
                                            'Barang';
                                    final String persenConf = item[
                                            'persen_kepercayaan'] ??
                                        "${((item['confidence'] ?? 0.0) * 100).toStringAsFixed(1)}%";

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4.0, horizontal: 8.0),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "• $namaBarang",
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 15),
                                          ),
                                          Text(
                                            persenConf,
                                            style: const TextStyle(
                                              color: Colors.greenAccent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              )
                            else
                              const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text(
                                  "Belum ada objek terdeteksi",
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontStyle: FontStyle.italic),
                                ),
                              ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _isPanelExpanded = false),
                              child: const Text("Sembunyikan Panel",
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}