// Packages needed:  flutter pub add http google_fonts
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'api_service.dart';

/// Name shown under the title. Change it when you know where the sensor goes.
const sensorLabel = 'Sensor 01';

/// Range of the meter and chart (dB).
/// For a 200 dB scale use dbMin = 40.0 and dbMax = 200.0.
const dbMin = 30.0;
const dbMax = 150.0;

/// Light by default: easier to read outdoors. Switch in Settings.
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

void main() => runApp(const SoundApp());

// ───────────────────────── COLOURS ─────────────────────────

class Pal {
  final Color bg, card, line, ink, mut, acc, ok, amb, ambText, red;

  const Pal({
    required this.bg,
    required this.card,
    required this.line,
    required this.ink,
    required this.mut,
    required this.acc,
    required this.ok,
    required this.amb,
    required this.ambText,
    required this.red,
  });

  static const light = Pal(
    bg: Color(0xFFF4F1EA),
    card: Color(0xFFFFFFFF),
    line: Color(0xFFDDD8CC),
    ink: Color(0xFF1E1B16),
    mut: Color(0xFF6B655A),
    acc: Color(0xFFE8590C),
    ok: Color(0xFF2F7D4F),
    amb: Color(0xFFD99A00),
    ambText: Color(0xFF946600),
    red: Color(0xFFC8371F),
  );

  static const dark = Pal(
    bg: Color(0xFF151412),
    card: Color(0xFF1F1D1A),
    line: Color(0xFF37332C),
    ink: Color(0xFFF1EDE4),
    mut: Color(0xFF9A9488),
    acc: Color(0xFFFF7A2F),
    ok: Color(0xFF4CAF77),
    amb: Color(0xFFE0A62A),
    ambText: Color(0xFFE0A62A),
    red: Color(0xFFF0624A),
  );

  static Pal of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? dark : light;
}

/// Big numerals: Barlow Condensed, the road-sign look.
TextStyle numStyle(double size, Color color, {FontWeight w = FontWeight.w600}) =>
    GoogleFonts.barlowCondensed(
      fontSize: size,
      fontWeight: w,
      color: color,
      height: 1.0,
      letterSpacing: -0.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

ThemeData buildTheme(Pal p, Brightness b) {
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: p.acc, brightness: b)
        .copyWith(surface: p.bg),
  );
  return base.copyWith(
    textTheme: GoogleFonts.barlowTextTheme(base.textTheme)
        .apply(bodyColor: p.ink, displayColor: p.ink),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : p.mut),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.acc : p.line),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}

// ───────────────────────── HELPERS ─────────────────────────

String fmt(dynamic v) => v == null ? '--' : (v as num).toStringAsFixed(1);

/// "2026-10-24 16:44:20"  ->  "24 Oct 16:44"
String fmtWhen(String? raw) {
  if (raw == null) return '--';
  final t = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  if (t == null) return raw;
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String p2(int v) => v.toString().padLeft(2, '0');
  return '${t.day} ${m[t.month - 1]} ${p2(t.hour)}:${p2(t.minute)}';
}

String ageText(Duration a) {
  if (a.inSeconds < 5) return 'just now';
  if (a.inSeconds < 60) return '${a.inSeconds} s ago';
  if (a.inMinutes < 60) return '${a.inMinutes} min ago';
  return '${a.inHours} h ago';
}

void drawText(Canvas canvas, String s, Offset at, TextStyle style,
    {bool right = false, bool centerY = false, bool centerX = false}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  var dx = at.dx;
  if (right) dx -= tp.width;
  if (centerX) dx -= tp.width / 2;
  tp.paint(canvas, Offset(dx, centerY ? at.dy - tp.height / 2 : at.dy));
}

// ───────────────────────── APP ─────────────────────────

class SoundApp extends StatelessWidget {
  const SoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Site noise',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: buildTheme(Pal.light, Brightness.light),
        darkTheme: buildTheme(Pal.dark, Brightness.dark),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final api = ApiService();
  Timer? poller;

  int tab = 0;
  bool online = false;
  bool seeded = false;
  String lastKey = '';

  Dashboard? dash;
  Map<String, dynamic>? stats;
  final List<double> recent = []; // last 60 readings seen
  List<Map<String, dynamic>> readings = [];
  List<Map<String, dynamic>> alerts = [];

  @override
  void initState() {
    super.initState();
    refresh();
    poller = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  @override
  void dispose() {
    poller?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final d = await api.dashboard();
      Map<String, dynamic>? st;
      try {
        st = await api.statistics();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        dash = d;
        online = true;
        if (st != null) stats = st;
        final v = d.latestNoiseLevel;
        if (v != null) {
          final key = '${d.recordedAt}|$v';
          if (key != lastKey) {
            recent.add(v);
            if (recent.length > 60) recent.removeAt(0);
            lastKey = key;
          }
        }
      });
      if (!seeded) seedRecent();
      if (tab == 1) loadHistory();
    } catch (e, st) {
      debugPrint('DASHBOARD ERROR: $e');
      debugPrintStack(stackTrace: st);
      if (mounted) setState(() => online = false);
    }
  }

  /// Fill the chart with saved readings the first time we connect.
  Future<void> seedRecent() async {
    seeded = true;
    try {
      final r = await api.readings();
      if (!mounted) return;
      setState(() {
        recent
          ..clear()
          ..addAll(r
              .take(60)
              .map((x) => (x['noise_level'] as num).toDouble())
              .toList()
              .reversed);
      });
    } catch (_) {
      seeded = false;
    }
  }

  Future<void> loadHistory() async {
    try {
      final r = await api.readings();
      final st = await api.statistics();
      final a = await api.alerts();
      if (!mounted) return;
      setState(() {
        readings = r;
        stats = st;
        alerts = a;
      });
    } catch (_) {}
  }

  Future<void> changeLimit(double value) async {
    final d = dash;
    if (d == null) return;
    setState(() {
      dash = Dashboard(
        latestNoiseLevel: d.latestNoiseLevel,
        threshold: value,
        status: d.status,
        recordedAt: d.recordedAt,
      );
    });
    try {
      await api.setThreshold(value);
    } catch (_) {}
    refresh();
  }

  Duration? lastAge() {
    final raw = dash?.recordedAt;
    if (raw == null) return null;
    final t = DateTime.tryParse('${raw.replaceFirst(' ', 'T')}Z');
    if (t == null) return null;
    final a = DateTime.now().toUtc().difference(t);
    if (a.isNegative) return Duration.zero;
    if (a.inHours > 12) return null;
    return a;
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final pages = [buildNow(p), buildHistory(p), buildSettings(p)];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]),
        ),
      ),
      bottomNavigationBar: BottomNav(
        index: tab,
        onTap: (i) {
          HapticFeedback.selectionClick();
          setState(() => tab = i);
          if (i == 1) loadHistory();
        },
      ),
    );
  }

  // ───────────────────────── NOW ─────────────────────────

  Widget pageHeader(Pal p, String caption, String title, {bool showLive = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(caption, style: TextStyle(fontSize: 13, color: p.mut)),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: GoogleFonts.barlow(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          if (showLive)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: online ? p.ok : p.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    online ? 'Connected' : 'Offline',
                    style: TextStyle(fontSize: 13, color: p.mut),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget buildNow(Pal p) {
    final v = dash?.latestNoiseLevel;
    final limit = dash?.threshold ?? 70.0;

    final String state = !online
        ? 'offline'
        : v == null
            ? 'empty'
            : v > limit
                ? 'over'
                : v > limit - 10
                    ? 'near'
                    : 'ok';

    final Color sc = switch (state) {
      'over' => p.red,
      'near' => p.ambText,
      'ok' => p.ok,
      _ => p.mut,
    };
    final label = switch (state) {
      'over' => 'Over limit',
      'near' => 'Near limit',
      'ok' => 'Within limit',
      'offline' => 'Offline',
      _ => 'No data',
    };
    final message = switch (state) {
      'over' => 'Over the limit by ${(v! - limit).toStringAsFixed(1)} dB.',
      'near' => 'Close to the limit, ${(limit - v!).toStringAsFixed(1)} dB to spare.',
      'ok' => 'Comfortably under the limit.',
      'offline' => 'Cannot reach the server. Check that app.py is running.',
      _ => 'Waiting for the first reading from the sensor.',
    };

    final age = lastAge();
    final stale = age != null && age.inSeconds > 60;
    final peak = recent.isEmpty ? null : recent.reduce(math.max);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        pageHeader(p, sensorLabel, 'Site noise'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    age == null ? 'Now' : 'Last reading ${ageText(age)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: stale ? p.ambText : p.mut,
                      fontWeight: stale ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: sc),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: v ?? 0),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, x, _) => Text(
                      v == null ? '--' : x.toStringAsFixed(1),
                      style: numStyle(92, p.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('dB', style: TextStyle(fontSize: 22, color: p.mut)),
                ],
              ),
              const SizedBox(height: 14),
              TweenAnimationBuilder<double>(
                tween: Tween(end: v ?? MeterPainter.lo),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, x, _) => SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: MeterPainter(
                      value: x,
                      active: v != null,
                      limit: limit,
                      peak: peak,
                      p: p,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: sc, width: 3)),
                ),
                child: Text(message, style: const TextStyle(fontSize: 15, height: 1.35)),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Panel(
                child: StatBlock(label: 'Average', value: fmt(stats?['average_noise'])),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Panel(
                child: StatBlock(label: 'Highest recorded', value: fmt(stats?['maximum_noise'])),
              ),
            ),
          ],
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Last ${recent.length} readings',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text('dB', style: TextStyle(fontSize: 13, color: p.mut)),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 150,
                width: double.infinity,
                child: recent.length < 2
                    ? Center(
                        child: Text('The chart appears after two readings.',
                            style: TextStyle(color: p.mut)),
                      )
                    : CustomPaint(painter: ChartPainter(data: recent, limit: limit, p: p)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ───────────────────────── HISTORY ─────────────────────────

  Widget buildHistory(Pal p) {
    final limit = dash?.threshold ?? 70.0;
    final subtitle = !online
        ? 'Cannot reach the server.'
        : readings.isEmpty
            ? 'Nothing saved yet.'
            : '${stats?['total_readings'] ?? readings.length} readings saved';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        pageHeader(p, subtitle, 'History', showLive: false),
        if (readings.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Expanded(child: StatBlock(label: 'Lowest', value: fmt(stats?['minimum_noise']))),
                Expanded(child: StatBlock(label: 'Average', value: fmt(stats?['average_noise']), divider: true)),
                Expanded(child: StatBlock(label: 'Highest', value: fmt(stats?['maximum_noise']), divider: true)),
              ],
            ),
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Alerts', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text('Noise stayed over the limit', style: TextStyle(fontSize: 13, color: p.mut)),
                const SizedBox(height: 4),
                if (alerts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('No alerts so far.', style: TextStyle(color: p.mut)),
                  )
                else
                  for (int i = 0; i < math.min(alerts.length, 8); i++)
                    LedgerRow(
                      first: fmtWhen(alerts[i]['recorded_at'] as String?),
                      second: '${fmt(alerts[i]['noise_level'])} dB',
                      third: 'limit ${fmt(alerts[i]['threshold'])}',
                      topLine: i > 0,
                    ),
              ],
            ),
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recent readings',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text('Newest first', style: TextStyle(fontSize: 13, color: p.mut)),
                const SizedBox(height: 4),
                for (int i = 0; i < math.min(readings.length, 12); i++)
                  LedgerRow(
                    first: fmtWhen(readings[i]['recorded_at'] as String?),
                    second: '${fmt(readings[i]['noise_level'])} dB',
                    third: (readings[i]['noise_level'] as num) > limit ? 'over' : 'ok',
                    thirdColor: (readings[i]['noise_level'] as num) > limit ? p.red : null,
                    topLine: i > 0,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ───────────────────────── SETTINGS ─────────────────────────

  Widget buildSettings(Pal p) {
    final limit = dash?.threshold;
    final dark = themeMode.value == ThemeMode.dark;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        pageHeader(p, 'How the app behaves', 'Settings', showLive: false),
        Panel(
          child: Column(
            children: [
              SettingRow(
                label: 'Alert limit',
                note: 'Noise above this counts as too loud',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StepButton(
                      icon: Icons.remove,
                      onTap: limit == null || limit <= 40 ? null : () => changeLimit(limit - 1),
                    ),
                    SizedBox(
                      width: 62,
                      child: Text(
                        limit == null ? '--' : '${limit.round()} dB',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    StepButton(
                      icon: Icons.add,
                      onTap: limit == null || limit >= dbMax ? null : () => changeLimit(limit + 1),
                    ),
                  ],
                ),
              ),
              SettingRow(
                label: 'Alert rules',
                note: 'How long noise must stay high, and the quiet period after an alert',
                trailing: Text('Set in app.py', style: TextStyle(color: p.mut)),
                topLine: true,
              ),
              SettingRow(
                label: 'Dark mode',
                trailing: Switch(
                  value: dark,
                  onChanged: (v) => themeMode.value = v ? ThemeMode.dark : ThemeMode.light,
                ),
                topLine: true,
              ),
              SettingRow(
                label: 'Server',
                note: backendUrl,
                trailing: Text(
                  online ? 'Connected' : 'Offline',
                  style: TextStyle(color: online ? p.ok : p.red, fontWeight: FontWeight.w600),
                ),
                topLine: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── PAINTERS ─────────────────────────

/// Segmented level meter, like a real sound-level meter.
class MeterPainter extends CustomPainter {
  final double value;
  final bool active;
  final double limit;
  final double? peak;
  final Pal p;

  MeterPainter({
    required this.value,
    required this.active,
    required this.limit,
    required this.peak,
    required this.p,
  });

  static const lo = dbMin;
  static const hi = dbMax;
  static const n = 48;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 2.0;
    const top = 24.0;
    const h = 30.0;
    final segW = (size.width - gap * (n - 1)) / n;
    final half = (hi - lo) / n / 2;

    for (int i = 0; i < n; i++) {
      final db = lo + (i + 1) * (hi - lo) / n;
      final c = db > limit ? p.red : (db > limit - 10 ? p.amb : p.ok);
      final lit = active && db <= value + half;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * (segW + gap), top, segW, h),
          const Radius.circular(1.5),
        ),
        Paint()..color = c.withValues(alpha: lit ? 1.0 : 0.16),
      );
    }

    // limit marker
    final fx = ((limit - lo) / (hi - lo)).clamp(0.0, 1.0).toDouble() * size.width;
    canvas.drawRect(Rect.fromLTWH(fx - 1, 17, 2, h + 14), Paint()..color = p.ink);
    final label = GoogleFonts.barlow(fontSize: 12, color: p.ink, fontWeight: FontWeight.w600);
    final tp = TextPainter(
      text: TextSpan(text: 'Limit ${limit.round()}', style: label),
      textDirection: TextDirection.ltr,
    )..layout();
    final lx = (fx - tp.width / 2).clamp(0.0, size.width - tp.width).toDouble();
    tp.paint(canvas, Offset(lx, 0));

    // peak-hold marker
    if (peak != null) {
      final px = ((peak! - lo) / (hi - lo)).clamp(0.0, 1.0).toDouble() * size.width;
      final path = Path()
        ..moveTo(px, top + h + 2)
        ..lineTo(px - 4, top + h + 8)
        ..lineTo(px + 4, top + h + 8)
        ..close();
      canvas.drawPath(path, Paint()..color = p.mut);
    }

    // scale
    final st = GoogleFonts.barlow(fontSize: 12, color: p.mut);
    for (int k = 0; k < 5; k++) {
      final v = lo + k * (hi - lo) / 4;
      final x = size.width * k / 4;
      final tp2 = TextPainter(
        text: TextSpan(text: '${v.round()}', style: st),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = k == 0 ? 0.0 : (k == 4 ? size.width - tp2.width : x - tp2.width / 2);
      tp2.paint(canvas, Offset(dx, top + h + 10));
    }
  }

  @override
  bool shouldRepaint(covariant MeterPainter old) =>
      old.value != value ||
      old.limit != limit ||
      old.peak != peak ||
      old.active != active ||
      old.p != p;
}

/// Plain line chart; parts above the limit are drawn in red.
class ChartPainter extends CustomPainter {
  final List<double> data;
  final double limit;
  final Pal p;

  ChartPainter({required this.data, required this.limit, required this.p});

  static const lo = dbMin;
  static const hi = dbMax;
  static const left = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    const topPad = 6.0;
    const botPad = 8.0;
    final pw = size.width - left;
    final ph = size.height - topPad - botPad;

    double yFor(double v) {
      final c = v.clamp(lo, hi).toDouble();
      return topPad + ph * (1 - (c - lo) / (hi - lo));
    }
    double xFor(int i) => left + pw * i / (data.length - 1);

    final label = GoogleFonts.barlow(fontSize: 11, color: p.mut);
    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (int k = 0; k <= 4; k++) {
      final v = lo + k * (hi - lo) / 4;
      final y = yFor(v);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      drawText(canvas, '${v.round()}', Offset(left - 6, y), label, right: true, centerY: true);
    }

    // limit line
    final ly = yFor(limit);
    final dash = Paint()
      ..color = p.red
      ..strokeWidth = 1.3;
    for (double x = left; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, ly), Offset(math.min(x + 4, size.width), ly), dash);
    }

    for (int i = 1; i < data.length; i++) {
      final over = (data[i] + data[i - 1]) / 2 > limit;
      canvas.drawLine(
        Offset(xFor(i - 1), yFor(data[i - 1])),
        Offset(xFor(i), yFor(data[i])),
        Paint()
          ..color = over ? p.red : p.ink
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawCircle(
      Offset(xFor(data.length - 1), yFor(data.last)),
      4,
      Paint()..color = p.acc,
    );
  }

  @override
  bool shouldRepaint(covariant ChartPainter old) => true;
}

// ───────────────────────── WIDGETS ─────────────────────────

class Panel extends StatelessWidget {
  final Widget child;

  const Panel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
      ),
      child: child,
    );
  }
}

class StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final bool divider;

  const StatBlock({super.key, required this.label, required this.value, this.divider = false});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: EdgeInsets.only(left: divider ? 14 : 0),
      decoration: divider
          ? BoxDecoration(border: Border(left: BorderSide(color: p.line)))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: p.mut)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: numStyle(34, p.ink)),
              const SizedBox(width: 4),
              Text('dB', style: TextStyle(fontSize: 13, color: p.mut)),
            ],
          ),
        ],
      ),
    );
  }
}

class LedgerRow extends StatelessWidget {
  final String first;
  final String second;
  final String third;
  final Color? thirdColor;
  final bool topLine;

  const LedgerRow({
    super.key,
    required this.first,
    required this.second,
    required this.third,
    this.thirdColor,
    this.topLine = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: topLine ? Border(top: BorderSide(color: p.line)) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(first,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 80,
            child: Text(second,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(third,
                style: TextStyle(fontSize: 14, color: thirdColor ?? p.mut)),
          ),
        ],
      ),
    );
  }
}

class SettingRow extends StatelessWidget {
  final String label;
  final String? note;
  final Widget trailing;
  final bool topLine;

  const SettingRow({
    super.key,
    required this.label,
    this.note,
    required this.trailing,
    this.topLine = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: topLine ? Border(top: BorderSide(color: p.line)) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                if (note != null) ...[
                  const SizedBox(height: 2),
                  Text(note!, style: TextStyle(fontSize: 13, color: p.mut, height: 1.3)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const StepButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.line),
        ),
        child: Icon(icon, size: 18, color: onTap == null ? p.line : p.ink),
      ),
    );
  }
}

class BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const BottomNav({super.key, required this.index, required this.onTap});

  static const items = [
    (Icons.speed, 'Now'),
    (Icons.history, 'History'),
    (Icons.tune, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Container(
                    padding: const EdgeInsets.only(top: 9, bottom: 10),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: i == index ? p.acc : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(items[i].$1, size: 24, color: i == index ? p.acc : p.mut),
                        const SizedBox(height: 2),
                        Text(
                          items[i].$2,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                            color: i == index ? p.acc : p.mut,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
