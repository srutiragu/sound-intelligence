import 'dart:convert';
import 'package:http/http.dart' as http;

/// Where the Flask backend (app.py) is running.
///   Android emulator : http://10.0.2.2:5000
///   iOS simulator    : http://localhost:5000
///   Real phone       : http://<your PC's Wi-Fi IP>:5000   (same Wi-Fi!)
const backendUrl = 'https://sound-intelligence.onrender.com';

/// Response of GET /dashboard
class Dashboard {
  final double? latestNoiseLevel; // null until the first reading arrives
  final double threshold;
  final String status; // NORMAL | HIGH | NO_DATA
  final String? recordedAt;

  Dashboard({
    required this.latestNoiseLevel,
    required this.threshold,
    required this.status,
    required this.recordedAt,
  });

  factory Dashboard.fromJson(Map<String, dynamic> j) => Dashboard(
        latestNoiseLevel: (j['latest_noise_level'] as num?)?.toDouble(),
        threshold: (j['threshold'] as num).toDouble(),
        status: j['status'] as String,
        recordedAt: j['recorded_at'] as String?,
      );
}

class ApiService {
  final String baseUrl;
  ApiService([this.baseUrl = backendUrl]);

  static const _timeout = Duration(seconds: 3);

  /// Latest reading + threshold + status. Throws if the backend is unreachable.
  Future<Dashboard> dashboard() async {
    final res = await http.get(Uri.parse('$baseUrl/dashboard')).timeout(_timeout);
    if (res.statusCode != 200) throw Exception('dashboard ${res.statusCode}');
    return Dashboard.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// GET /noise : all readings, newest first (id, noise_level, recorded_at).
  Future<List<Map<String, dynamic>>> readings() async {
    final res = await http.get(Uri.parse('$baseUrl/noise')).timeout(_timeout);
    if (res.statusCode != 200) throw Exception('noise ${res.statusCode}');
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  /// GET /noise/statistics : total_readings, average_noise, maximum_noise, minimum_noise.
  Future<Map<String, dynamic>> statistics() async {
    final res = await http.get(Uri.parse('$baseUrl/noise/statistics')).timeout(_timeout);
    if (res.statusCode != 200) throw Exception('statistics ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// GET /alerts : high-noise alerts, newest first.
  Future<List<Map<String, dynamic>>> alerts() async {
    final res = await http.get(Uri.parse('$baseUrl/alerts')).timeout(_timeout);
    if (res.statusCode != 200) throw Exception('alerts ${res.statusCode}');
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  /// PUT /threshold
  Future<void> setThreshold(double value) async {
    final res = await http
        .put(
          Uri.parse('$baseUrl/threshold'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'threshold': value}),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('threshold ${res.statusCode}');
  }

  /// POST /noise : used for testing from the app; the ESP32 normally sends this.
  Future<void> sendReading(double noiseLevel) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/noise'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'noise_level': noiseLevel}),
        )
        .timeout(_timeout);
    if (res.statusCode != 201) throw Exception('send ${res.statusCode}');
  }
}
