import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _serverUrlController = TextEditingController(
    text: 'http://10.21.13.96:8000',
  );
  
  bool _isSaving = false;

  void _saveSettings() {
    setState(() => _isSaving = true);
    
    Future.delayed(const Duration(seconds: 1), () {
      setState(() => _isSaving = false);
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Konfigurasi server & MongoDB berhasil disimpan!"),
          backgroundColor: Colors.green,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Pengaturan & Database", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Koneksi Server & FastAPI",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "URL Endpoint FastAPI",
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "FastAPI bertindak sebagai jembatan ke database MongoDB.",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _serverUrlController,
                      decoration: InputDecoration(
                        labelText: "Server URL",
                        prefixIcon: const Icon(Icons.dns_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              "Database Status",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.storage, color: Colors.green),
                    title: Text("MongoDB Atlas / Local"),
                    subtitle: Text("Koleksi: inventory_items"),
                    trailing: Chip(
                      label: Text("Terhubung", style: TextStyle(color: Colors.green, fontSize: 12)),
                      backgroundColor: Color(0xFFE8F5E9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              "Informasi",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.info_outline, color: Colors.indigo),
                    title: Text("Versi Aplikasi"),
                    trailing: Text("1.0.0 (YOLO + MongoDB)", style: TextStyle(color: Colors.grey)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.person_outline, color: Colors.indigo),
                    title: const Text("Operator Aktif"),
                    trailing: Text("Operator AI", style: TextStyle(color: Colors.grey.shade700)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Simpan Konfigurasi", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}