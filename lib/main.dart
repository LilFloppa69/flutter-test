import 'dart:convert'; // for json encode/decode
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Incident Report',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ReportFormPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Report {
  final String title;
  final String description;
  final double latitude;
  final double longitude;

  Report({
    required this.title,
    required this.description,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory Report.fromMap(Map<String, dynamic> map) {
    return Report(
      title: map['title'],
      description: map['description'],
      latitude: map['latitude'],
      longitude: map['longitude'],
    );
  }
}

class ReportFormPage extends StatefulWidget {
  const ReportFormPage({super.key});

  @override
  State<ReportFormPage> createState() => _ReportFormPageState();
}

class _ReportFormPageState extends State<ReportFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _loading = false;

  List<Report> _reports = [];

  @override
  void initState() {
    super.initState();
    _loadReports(); // load reports on startup
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('reports') ?? [];
    setState(() {
      _reports = data.map((r) => Report.fromMap(jsonDecode(r))).toList();
    });
  }

  Future<void> _openMap(double lat, double lng) async {
    final url = Uri.parse(
      "https://www.google.com/maps/search/?api=1&query=$lat,$lng",
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open Google Maps")),
      );
    }
  }

  Future<void> _saveReports() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _reports.map((r) => jsonEncode(r.toMap())).toList();
    await prefs.setStringList('reports', data);
  }

  Future<void> _deleteReport(int index) async {
    setState(() {
      _reports.removeAt(index);
    });
    await _saveReports(); // persist changes
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      // 1. Check & request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception("Location permission denied");
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception("Location permission permanently denied");
      }

      // 2. Get current location
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 3. Save report locally
      final newReport = Report(
        title: _titleCtrl.text,
        description: _descCtrl.text,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );

      setState(() {
        _reports.add(newReport);
      });
      await _saveReports(); // persist

      // 4. Clear form
      _titleCtrl.clear();
      _descCtrl.clear();

      // 5. (Optional) Launch Google Maps
      final url = Uri.parse(
        "https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}",
      );
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Incident Report")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Report form
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(labelText: "Title"),
                    validator: (val) =>
                        val == null || val.isEmpty ? "Enter a title" : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: "Description"),
                    maxLines: 3,
                    validator: (val) => val == null || val.isEmpty
                        ? "Enter a description"
                        : null,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loading ? null : _submitForm,
                    child: _loading
                        ? const CircularProgressIndicator()
                        : const Text("Submit Report"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Display saved reports
            if (_reports.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Submitted Reports:",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _reports.length,
                    itemBuilder: (context, index) {
                      final r = _reports[index];
                      return Card(
                        child: ListTile(
                          title: Text(r.title),
                          subtitle: Text(
                            "${r.description}\n(${r.latitude}, ${r.longitude})",
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.map,
                                  color: Colors.indigo,
                                ),
                                onPressed: () =>
                                    _openMap(r.latitude, r.longitude),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  _deleteReport(index);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Report deleted"),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
