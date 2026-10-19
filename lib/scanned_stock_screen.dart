import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ScannedStockScreen extends StatefulWidget {
  const ScannedStockScreen({super.key});

  @override
  State<ScannedStockScreen> createState() => _ScannedStockScreenState();
}

class _ScannedStockScreenState extends State<ScannedStockScreen> {
  static const String _baseUrl = 'http://10.21.13.96:8000';

  bool _isLoading = true;
  List<dynamic> _mongoStockItems = [];
  List<dynamic> _shiftSummaries = [];
  String _errorMessage = "";
  String _activeShiftLabel = "Memuat Shift...";

  @override
  void initState() {
    super.initState();
    _fetchStockAndShiftData();
  }

  Future<void> _fetchStockAndShiftData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      final stockResponse = await http.get(
        Uri.parse('$_baseUrl/inventory'),
      ).timeout(const Duration(seconds: 5));

      final summaryResponse = await http.get(
        Uri.parse('$_baseUrl/api/v1/shift-summary/today'),
      ).timeout(const Duration(seconds: 5));

      if (stockResponse.statusCode == 200) {
        final stockData = jsonDecode(stockResponse.body);
        setState(() {
          _mongoStockItems = stockData is List ? stockData : [];
        });
      }

      if (summaryResponse.statusCode == 200) {
        final summaryData = jsonDecode(summaryResponse.body);
        setState(() {
          _shiftSummaries = summaryData['summaries'] ?? [];
          if (_shiftSummaries.isNotEmpty) {
            final latest = _shiftSummaries.last;
            _activeShiftLabel = "${latest['shift_name']} (${latest['shift_date']})";
          } else {
            _activeShiftLabel = "Shift Berjalan";
          }
        });
      }
    } catch (e) {
      setState(() {
        _mongoStockItems = [];
        _shiftSummaries = [];
        _activeShiftLabel = "Offline / Server Mati";
        _errorMessage = "Gagal terhubung ke server FastAPI.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showShiftReportDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.assessment, color: Colors.indigo),
              SizedBox(width: 8),
              Text("Rekap Hasil Shift", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: _shiftSummaries.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("Belum ada data rekapitulasi shift hari ini.", textAlign: TextAlign.center),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _shiftSummaries.length,
                    itemBuilder: (context, index) {
                      final shift = _shiftSummaries[index];
                      final classCounts = shift['class_counts'] as Map<String, dynamic>? ?? {};

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        color: Colors.indigo.shade50,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    shift['shift_name'] ?? 'Shift',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "Total: ${shift['total_count'] ?? 0} Pcs",
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text("Tanggal: ${shift['shift_date']}", style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                              const Divider(height: 16),
                              const Text("Rincian Item Terdeteksi:", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(height: 6),
                              classCounts.isEmpty
                                  ? const Text("Tidak ada item", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic))
                                  : Column(
                                      children: classCounts.entries.map((entry) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text("• ${entry.key}", style: const TextStyle(fontSize: 13)),
                                              Text("${entry.value} Pcs", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context),
              child: const Text("Tutup"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Stok Shift Aktif", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: _showShiftReportDialog,
            tooltip: "Lihat Rekap Shift",
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchStockAndShiftData,
            tooltip: "Refresh Data",
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.indigo,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_filled, color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Status Shift Saat Ini", style: TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(_activeShiftLabel, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: Colors.indigo,
              onRefresh: _fetchStockAndShiftData,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
                  : _mongoStockItems.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                                      const SizedBox(height: 12),
                                      Text(
                                        _errorMessage.isNotEmpty ? _errorMessage : "Stok kosong untuk shift ini (Reset Otomatis).",
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: Colors.grey, fontSize: 15),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        "Stok akan mulai terhitung dari 0 pada shift baru.",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.grey, fontSize: 12),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: _fetchStockAndShiftData,
                                        icon: const Icon(Icons.refresh),
                                        label: const Text("Coba Lagi"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.indigo,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _mongoStockItems.length,
                          itemBuilder: (context, index) {
                            final item = _mongoStockItems[index];
                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.inventory_2, color: Colors.indigo),
                                ),
                                title: Text(
                                  item["item_name"] ?? "Tanpa Nama",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text("Update: ${item["updated_at"] ?? "Baru saja"}", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                ),
                                trailing: Text(
                                  "${item["quantity"] ?? 0} Pcs",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}