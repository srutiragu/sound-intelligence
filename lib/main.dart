// Needs one package:  flutter pub add flutter_animate
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'api_service.dart';

void main() => runApp(const SoundApp());

// ───────────────────────── DESIGN TOKENS ─────────────────────────

const bg = Color(0xFF07090F);
const cyan = Color(0xFF35E7FF);
const violet = Color(0xFF8B5CF6);
const pink = Color(0xFFFF4FCB);
const green = Color(0xFF72F7B2);
const danger = Color(0xFFFF5470);
const muted = Color(0xFFA6A0C0);

const tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);


/// Staggered entrance used on every card.
Widget reveal(Widget w, int i) => w
    .animate(delay: Duration(milliseconds: 80 * i))
    .fadeIn(duration: 550.ms, curve: Curves.easeOut)
    .slideY(begin: 0.12, end: 0, duration: 550.ms, curve: Curves.easeOutCubic);

String fmt(dynamic v) => v == null ? '--' : (v as num).toStringAsFixed(1);

// ───────────────────────── APP ─────────────────────────

class SoundApp extends StatelessWidget {
  const SoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sound Intelligence',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(primary: cyan, surface: bg),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const MonitorScreen(),
    );
  }
}

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen>
    with TickerProviderStateMixin {
  late final AnimationController fast; // waves, bars, pulses
  late final AnimationController slow; // aurora, particles, ring rotation
  final List<double> caps = List<double>.filled(48, 0); // spectrum peak-hold
  int tab = 0;

  // ── backend connection ──
  final api = ApiService();
  Timer? poller;
  Dashboard? dash; // latest /dashboard response
  bool online = false;

  // ── history data (loaded when the History tab is open) ──
  List<Map<String, dynamic>> readings = [];
  List<Map<String, dynamic>> alerts = [];
  Map<String, dynamic>? stats;

  @override
  void initState() {
    super.initState();
    fast = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    slow = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    refresh();
    poller = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  /// Ask the Flask backend for the latest reading.
  Future<void> refresh() async {
    try {
      final d = await api.dashboard();
      if (mounted) {
        setState(() {
          dash = d;
          online = true;
        });
        if (tab == 1) loadHistory();
      }
    } catch (_) {
      if (mounted && online) setState(() => online = false);
    }
  }

  /// Load saved readings, statistics and alerts for the History tab.
  Future<void> loadHistory() async {
    try {
      final r = await api.readings();
      final st = await api.statistics();
      final a = await api.alerts();
      if (mounted) {
        setState(() {
          readings = r;
          stats = st;
          alerts = a;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    poller?.cancel();
    fast.dispose();
    slow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget Function()>[buildMonitor, buildHistory, buildSettings];

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: AuroraPainter(slow)),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                buildHeader(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.05, 0),
                          end: Offset.zero,
                        ).animate(a),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(tab),
                      child: tabs[tab](),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 14),
              child: GlassNav(
                index: tab,
                onTap: (i) {
                  HapticFeedback.selectionClick();
                  setState(() => tab = i);
                  if (i == 1) loadHistory();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── HEADER ─────────────────────────

  Widget buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(
                colors: [cyan, violet, pink],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: violet.withValues(alpha: 0.55),
                  blurRadius: 22,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Center(
              child: CustomPaint(
                size: const Size(24, 24),
                painter: MiniEqPainter(fast),
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: -1.5, end: 1.5, duration: 1800.ms, curve: Curves.easeInOut),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SOUND INTELLIGENCE',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 15.5,
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .shimmer(
                      delay: 1400.ms,
                      duration: 1800.ms,
                      color: cyan.withValues(alpha: 0.9),
                    ),
                const SizedBox(height: 3),
                const Text(
                  'ENVIRONMENTAL AUDIO ANALYTICS',
                  style: TextStyle(fontSize: 9, color: muted, letterSpacing: 1.3),
                ),
              ],
            ),
          ),
          const StatusChip(label: 'DEMO', color: green, dot: true),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 600.ms)
        .slideY(begin: -0.3, end: 0, duration: 600.ms, curve: Curves.easeOutCubic);
  }

  // ───────────────────────── MONITOR TAB ─────────────────────────

  Widget buildMonitor() {
    final db = dash?.latestNoiseLevel;
    final hasData = db != null;
    final threshold = dash?.threshold ?? 70.0;
    final status = !online ? 'OFFLINE' : (dash?.status ?? 'NO_DATA');
    final Color sc = switch (status) {
      'NORMAL' => green,
      'HIGH' => danger,
      'OFFLINE' => danger,
      _ => const Color(0xFFFFB84D),
    };
    final chipLabel = switch (status) {
      'NORMAL' => 'MONITORING',
      'HIGH' => 'ALERT',
      'OFFLINE' => 'OFFLINE',
      _ => 'WAITING FOR DATA',
    };
    final headline = switch (status) {
      'NORMAL' => 'Below configured threshold',
      'HIGH' => 'Above threshold',
      'OFFLINE' => 'Backend not reachable',
      _ => 'Waiting for first reading',
    };
    final statusIcon = switch (status) {
      'NORMAL' => Icons.shield_outlined,
      'HIGH' => Icons.warning_amber_rounded,
      'OFFLINE' => Icons.cloud_off,
      _ => Icons.hourglass_empty,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        reveal(
          Panel(
            title: 'Environmental noise',
            icon: Icons.radar,
            glow: violet,
            trailing: StatusChip(label: chipLabel, color: sc, dot: true),
            child: Column(
              children: [
                HeroGauge(
                  fast: fast,
                  slow: slow,
                  db: db ?? 0,
                  threshold: threshold,
                  hasData: hasData,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: sc.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: sc.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(statusIcon, color: sc, size: 22),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              headline,
                              style: TextStyle(
                                color: sc,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Limit: ${threshold.round()} dB',
                              style: const TextStyle(color: muted, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, color: sc, size: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
          0,
        ),
        const SizedBox(height: 14),
        reveal(
          const Row(
            children: [
              Expanded(
                child: InsightTile(
                  icon: Icons.graphic_eq,
                  label: 'DOMINANT FREQ.',
                  value: '-- Hz',
                  color: cyan,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: InsightTile(
                  icon: Icons.surround_sound,
                  label: 'SOUND CLASS',
                  value: 'Pending',
                  color: pink,
                ),
              ),
            ],
          ),
          1,
        ),
        const SizedBox(height: 14),
        reveal(
          Panel(
            title: 'Sound waveform',
            subtitle: 'Amplitude over time',
            icon: Icons.multitrack_audio,
            trailing: const StatusChip(label: 'LIVE SIMULATION', color: cyan, dot: true),
            child: Column(
              children: [
                SizedBox(
                  height: 125,
                  width: double.infinity,
                  child: CustomPaint(painter: WavePainter(fast)),
                ),
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AxisLabel('−1.0'),
                    AxisLabel('−0.5'),
                    AxisLabel('0'),
                    AxisLabel('0.5'),
                    AxisLabel('1.0'),
                  ],
                ),
              ],
            ),
          ),
          2,
        ),
        const SizedBox(height: 14),
        reveal(
          Panel(
            title: 'Frequency spectrum',
            subtitle: 'Relative energy by frequency',
            icon: Icons.equalizer,
            child: Column(
              children: [
                SizedBox(
                  height: 135,
                  width: double.infinity,
                  child: CustomPaint(painter: SpectrumPainter(fast, caps)),
                ),
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AxisLabel('0 Hz'),
                    AxisLabel('2.5 kHz'),
                    AxisLabel('5 kHz'),
                    AxisLabel('7.5 kHz'),
                    AxisLabel('10 kHz'),
                  ],
                ),
              ],
            ),
          ),
          3,
        ),
        const SizedBox(height: 14),
        reveal(
          Panel(
            title: 'System connections',
            subtitle: 'Status',
            icon: Icons.hub_outlined,
            child: Column(
              children: [
                ConnectionRow(
                  icon: Icons.memory,
                  title: 'Sensor data',
                  detail: hasData
                      ? 'Last reading: ${dash?.recordedAt ?? '-'}'
                      : 'No readings received yet',
                  color: hasData ? green : pink,
                ),
                const Divider(color: Color(0x22FFFFFF), height: 26),
                ConnectionRow(
                  icon: Icons.cloud_outlined,
                  title: 'Backend server',
                  detail: online
                      ? 'Connected to $backendUrl'
                      : 'Not reachable at $backendUrl',
                  color: online ? green : danger,
                ),
              ],
            ),
          ),
          4,
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            !online
                ? 'BACKEND OFFLINE • START app.py'
                : hasData
                    ? 'LIVE • DATA FROM BACKEND'
                    : 'BACKEND CONNECTED • WAITING FOR READINGS',
            style: const TextStyle(fontSize: 9, letterSpacing: 1.4, color: muted),
          ),
        ),
      ],
    );
  }

  // ───────────────────────── HISTORY TAB (blank) ─────────────────────────

  Widget buildHistory() {
    final hasReadings = readings.isNotEmpty;
    final threshold = dash?.threshold ?? 70.0;
    final chartData = readings
        .take(60)
        .map((r) => (r['noise_level'] as num).toDouble())
        .toList()
        .reversed
        .toList();
    final total = stats?['total_readings'] ?? readings.length;
    final subtitle = !online
        ? 'Backend not reachable. Start app.py to see saved readings.'
        : hasReadings
            ? '$total readings saved in the database.'
            : 'No readings saved yet. Send one to the backend to see it here.';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        reveal(
          const Text(
            'Noise history',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
          ),
          0,
        ),
        const SizedBox(height: 8),
        reveal(
          Text(subtitle, style: const TextStyle(color: muted, height: 1.5)),
          1,
        ),
        const SizedBox(height: 20),
        if (!hasReadings)
          reveal(
            Glass(
              glow: violet,
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              child: Column(
                children: [
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(150, 150),
                          painter: PulseRingsPainter(fast),
                        ),
                        const Icon(Icons.query_stats, size: 48, color: violet)
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .moveY(
                              begin: -5,
                              end: 5,
                              duration: 1600.ms,
                              curve: Curves.easeInOut,
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No recordings yet',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    online
                        ? 'Send a reading to the backend and it will appear here.'
                        : 'Start the backend server to load saved readings.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
            2,
          )
        else ...[
          reveal(
            Row(
              children: [
                Expanded(
                  child: StatTile(label: 'MIN', value: fmt(stats?['minimum_noise']), color: green),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(label: 'AVG', value: fmt(stats?['average_noise']), color: cyan),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(label: 'MAX', value: fmt(stats?['maximum_noise']), color: pink),
                ),
              ],
            ),
            2,
          ),
          const SizedBox(height: 14),
          reveal(
            Panel(
              title: 'Noise level',
              subtitle: 'Last ${chartData.length} readings (dB)',
              icon: Icons.show_chart,
              trailing: StatusChip(label: 'LIMIT ${threshold.round()} dB', color: danger),
              child: Column(
                children: [
                  SizedBox(
                    height: 190,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: LinePainter(chartData, threshold, fast),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.only(left: 30),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [AxisLabel('Older'), AxisLabel('Latest')],
                    ),
                  ),
                ],
              ),
            ),
            3,
          ),
          const SizedBox(height: 14),
          reveal(
            Panel(
              title: 'Alerts',
              subtitle: alerts.isEmpty ? 'No alerts yet' : '${alerts.length} recorded',
              icon: Icons.warning_amber_rounded,
              child: alerts.isEmpty
                  ? const Row(
                      children: [
                        Icon(Icons.verified_outlined, color: green, size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Noise has not stayed above the limit long enough to raise an alert.',
                            style: TextStyle(color: muted, fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        for (int i = 0; i < math.min(alerts.length, 8); i++) ...[
                          if (i > 0) const Divider(color: Color(0x22FFFFFF), height: 22),
                          ConnectionRow(
                            icon: Icons.warning_amber_rounded,
                            title: '${fmt(alerts[i]['noise_level'])} dB',
                            detail:
                                '${alerts[i]['recorded_at']} • limit ${fmt(alerts[i]['threshold'])} dB',
                            color: danger,
                          ),
                        ],
                      ],
                    ),
            ),
            4,
          ),
          const SizedBox(height: 14),
          reveal(
            Panel(
              title: 'Recent readings',
              subtitle: 'Newest first',
              icon: Icons.history,
              child: Column(
                children: [
                  for (int i = 0; i < math.min(readings.length, 8); i++) ...[
                    if (i > 0) const Divider(color: Color(0x22FFFFFF), height: 22),
                    ConnectionRow(
                      icon: Icons.graphic_eq,
                      title: '${fmt(readings[i]['noise_level'])} dB',
                      detail: '${readings[i]['recorded_at']}',
                      color: ((readings[i]['noise_level'] as num) > threshold) ? danger : cyan,
                    ),
                  ],
                ],
              ),
            ),
            5,
          ),
        ],
      ],
    );
  }

  // ───────────────────────── SETTINGS TAB ─────────────────────────

  Widget buildSettings() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        reveal(
          const Text(
            'Settings',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
          ),
          0,
        ),
        const SizedBox(height: 8),
        reveal(
          const Text('Configure monitoring preferences.', style: TextStyle(color: muted)),
          1,
        ),
        const SizedBox(height: 24),
        reveal(
          Glass(
            child: Column(
              children: [
                ConnectionRow(
                  icon: Icons.notifications_active_outlined,
                  title: 'Noise alert threshold',
                  detail: dash == null
                      ? 'Waiting for backend'
                      : '${dash!.threshold.round()} dB • from backend',
                  color: cyan,
                ),
                Divider(color: Color(0x22FFFFFF), height: 28),
                ConnectionRow(
                  icon: Icons.mic_none,
                  title: 'Audio input',
                  detail: 'No microphone configured',
                  color: violet,
                ),
                Divider(color: Color(0x22FFFFFF), height: 28),
                ConnectionRow(
                  icon: Icons.storage_outlined,
                  title: 'Data storage',
                  detail: online ? 'Backend database connected' : 'Backend not reachable',
                  color: pink,
                ),
              ],
            ),
          ),
          2,
        ),
      ],
    );
  }
}

// ───────────────────────── HERO GAUGE ─────────────────────────

class HeroGauge extends StatelessWidget {
  final Animation<double> fast;
  final Animation<double> slow;
  final double db;
  final double threshold;
  final bool hasData;

  const HeroGauge({
    super.key,
    required this.fast,
    required this.slow,
    required this.db,
    required this.threshold,
    required this.hasData,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(280, 280),
            painter: RadialBarsPainter(fast, slow),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: db),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(280, 280),
                    painter: GaugePainter(v, threshold, fast),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.graphic_eq, color: cyan, size: 26)
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .fade(begin: 0.55, end: 1, duration: 1100.ms),
                      const SizedBox(height: 2),
                      ShaderMask(
                        shaderCallback: (r) => const LinearGradient(
                          colors: [Colors.white, Color(0xFFB9C7FF)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ).createShader(r),
                        child: Text(
                          hasData ? v.toStringAsFixed(1) : '--',
                          style: tabular.copyWith(
                            fontSize: 52,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Text(
                        'DECIBELS',
                        style: TextStyle(
                          color: cyan,
                          fontSize: 10,
                          letterSpacing: 2.2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hasData ? 'LATEST READING' : 'NO DATA YET',
                        style: const TextStyle(color: muted, fontSize: 9, letterSpacing: 1),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const Positioned(left: 62, top: 208, child: AxisLabel('0')),
          const Positioned(right: 54, top: 208, child: AxisLabel('120')),
        ],
      ),
    );
  }
}

class GaugePainter extends CustomPainter {
  final double value;
  final double threshold;
  final Animation<double> anim;

  GaugePainter(this.value, this.threshold, this.anim) : super(repaint: anim);

  static const maxDb = 120.0;
  static const start = 0.75 * math.pi;
  static const sweep = 1.5 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 92.0;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );

    final frac = (value / maxDb).clamp(0.0, 1.0).toDouble();
    final shader = const SweepGradient(
      startAngle: 0,
      endAngle: sweep,
      colors: [cyan, violet, pink],
      transform: GradientRotation(start),
    ).createShader(rect);

    if (frac > 0.004) {
      // soft glow under the arc
      canvas.drawArc(
        rect,
        start,
        sweep * frac,
        false,
        Paint()
          ..shader = shader
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawArc(
        rect,
        start,
        sweep * frac,
        false,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );

      // glowing tip with pulsing halo
      final a = start + sweep * frac;
      final tip = center + Offset(math.cos(a), math.sin(a)) * radius;
      final p = anim.value;
      canvas.drawCircle(
        tip,
        8 + 8 * p,
        Paint()..color = Colors.white.withValues(alpha: (1 - p) * 0.35),
      );
      canvas.drawCircle(tip, 5, Paint()..color = Colors.white);
    }

    // scale ticks
    final tick = Paint()
      ..color = muted.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (int i = 0; i <= 24; i++) {
      final a = start + sweep * i / 24;
      final major = i % 4 == 0;
      final r1 = radius - 15;
      final r2 = r1 - (major ? 7 : 4);
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * r1,
        center + Offset(math.cos(a), math.sin(a)) * r2,
        tick,
      );
    }

    // illustrative limit marker (85 dB)
    final ta = start + sweep * (threshold / maxDb).clamp(0.0, 1.0);
    canvas.drawLine(
      center + Offset(math.cos(ta), math.sin(ta)) * (radius - 10),
      center + Offset(math.cos(ta), math.sin(ta)) * (radius + 10),
      Paint()
        ..color = danger
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant GaugePainter old) =>
      old.value != value || old.threshold != threshold;
}

/// Audio-visualizer ring around the gauge.
class RadialBarsPainter extends CustomPainter {
  final Animation<double> fast;
  final Animation<double> slow;

  RadialBarsPainter(this.fast, this.slow)
      : super(repaint: Listenable.merge([fast, slow]));

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const baseR = 112.0;
    const n = 72;
    final phase = fast.value * 2 * math.pi;
    final rect = Rect.fromCircle(center: center, radius: baseR + 24);

    // ambient glow
    canvas.drawCircle(
      center,
      baseR + 28,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            violet.withValues(alpha: 0.20),
            Colors.transparent,
          ],
          stops: const [0.55, 0.82, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: baseR + 28)),
    );

    final paint = Paint()
      ..shader = SweepGradient(
        colors: const [cyan, violet, pink, violet, cyan],
        transform: GradientRotation(slow.value * 2 * math.pi),
      ).createShader(rect)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < n; i++) {
      final a = 2 * math.pi * i / n - math.pi / 2;
      final noise = (math.sin(i * 0.9 + phase * 2) * math.cos(i * 0.37 - phase)).abs();
      final h = 3 + 20 * (0.2 + 0.8 * noise);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * baseR, center + dir * (baseR + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant RadialBarsPainter old) => false;
}

// ───────────────────────── BACKGROUND ─────────────────────────

class AuroraPainter extends CustomPainter {
  final Animation<double> t;

  AuroraPainter(this.t) : super(repaint: t);

  static final List<List<double>> seeds = List.generate(30, (i) {
    final r = math.Random(i * 7 + 3);
    return [
      r.nextDouble(), // x
      r.nextDouble(), // y offset
      1 + (r.nextDouble() * 3).floorToDouble(), // speed (integer = seamless)
      r.nextDouble() * 6.28, // phase
      1 + r.nextDouble() * 1.8, // radius
    ];
  });

  void blob(Canvas canvas, Offset c, double r, Color color, double alpha) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);

    final p = t.value * 2 * math.pi;
    blob(canvas, Offset(w * (0.25 + 0.22 * math.sin(p)), h * (0.14 + 0.07 * math.cos(p))),
        w * 0.95, violet, 0.30);
    blob(canvas, Offset(w * (0.88 + 0.10 * math.cos(p * 2)), h * (0.45 + 0.08 * math.sin(p))),
        w * 0.85, pink, 0.17);
    blob(canvas, Offset(w * (0.15 + 0.12 * math.sin(p * 2)), h * (0.78 + 0.07 * math.cos(p))),
        w * 0.9, cyan, 0.15);

    // drifting, twinkling particles
    for (final s in seeds) {
      final x = (s[0] + 0.03 * math.sin(p * 2 + s[3])) * w;
      final y = ((1 - (t.value * s[2] + s[1]) % 1.0)) * h;
      final twinkle = 0.5 + 0.5 * math.sin(p * 3 + s[3]);
      canvas.drawCircle(
        Offset(x, y),
        s[4],
        Paint()..color = Colors.white.withValues(alpha: 0.10 + 0.30 * twinkle),
      );
    }
  }

  @override
  bool shouldRepaint(covariant AuroraPainter old) => false;
}

// ───────────────────────── CHART PAINTERS ─────────────────────────

class WavePainter extends CustomPainter {
  final Animation<double> anim;

  WavePainter(this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 0.8;
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (int i = 0; i <= 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    final phase = anim.value * 2 * math.pi;
    drawWave(canvas, size, violet, phase + 1.1, 0.25, 2.6, 2.0, false);
    drawWave(canvas, size, pink, phase + 2.3, 0.17, 3.6, 1.7, false);
    drawWave(canvas, size, cyan, phase, 0.34, 3.2, 2.3, true);
  }

  void drawWave(Canvas canvas, Size size, Color color, double phase, double amp,
      double freq, double width, bool glow) {
    final path = Path();
    final mid = size.height / 2;
    for (int i = 0; i <= 240; i++) {
      final x = size.width * i / 240;
      final t = i / 240 * freq * 2 * math.pi;
      final env = 0.22 + 0.78 * math.sin(t * 0.19 + phase).abs();
      final y = mid + math.sin(t + phase) * size.height * amp * env;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // fade both ends of the line
    final shader = LinearGradient(
      colors: [color.withValues(alpha: 0), color, color, color.withValues(alpha: 0)],
      stops: const [0, 0.14, 0.86, 1],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    if (glow) {
      canvas.drawPath(
        path,
        Paint()
          ..shader = shader
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 5
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant WavePainter old) => false;
}

class SpectrumPainter extends CustomPainter {
  final Animation<double> anim;
  final List<double> caps;

  SpectrumPainter(this.anim, this.caps) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 0.8;
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    const count = 48;
    const gap = 3.0;
    final barW = (size.width - gap * (count - 1)) / count;
    final phase = anim.value * 2 * math.pi;

    final fill = Paint()
      ..shader = const LinearGradient(
        colors: [cyan, Color(0xFF528CFF), violet, pink],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final capPaint = Paint()..color = Colors.white.withValues(alpha: 0.9);

    for (int i = 0; i < count; i++) {
      final p1 = math.exp(-math.pow((i - 9) / 4.5, 2));
      final p2 = math.exp(-math.pow((i - 24) / 6.5, 2));
      final p3 = math.exp(-math.pow((i - 39) / 4.5, 2));
      final base = 0.10 + 0.62 * p1 + 0.45 * p2 + 0.55 * p3;

      final mod = 0.80 +
          0.14 * math.sin(i * 0.58 + phase) +
          0.10 * math.sin(i * 1.3 - phase * 2);
      final lvl = (base * mod + 0.05 * math.sin(i * 0.9 + phase * 3).abs())
          .clamp(0.05, 1.0)
          .toDouble();

      caps[i] = math.max(lvl, caps[i] - 0.009);

      final h = lvl * size.height * 0.9;
      final x = i * (barW + gap);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, size.height - h, barW, h),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        fill,
      );

      final capY = size.height - caps[i] * size.height * 0.9 - 5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, capY, barW, 2.5),
          const Radius.circular(1.5),
        ),
        capPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SpectrumPainter old) => false;
}

class MiniEqPainter extends CustomPainter {
  final Animation<double> anim;

  MiniEqPainter(this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final phase = anim.value * 2 * math.pi;
    const n = 4;
    final w = size.width / (n * 2 - 1);
    for (int i = 0; i < n; i++) {
      final h = size.height * (0.30 + 0.70 * (0.5 + 0.5 * math.sin(phase * (1 + i % 2) + i * 1.7)));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * w * 2, size.height - h, w, h),
          const Radius.circular(2),
        ),
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MiniEqPainter old) => false;
}

class PulseRingsPainter extends CustomPainter {
  final Animation<double> anim;

  PulseRingsPainter(this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    for (int k = 0; k < 3; k++) {
      final p = (anim.value + k / 3) % 1.0;
      canvas.drawCircle(
        c,
        24 + 50 * p,
        Paint()
          ..color = violet.withValues(alpha: (1 - p) * 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PulseRingsPainter old) => false;
}

// ───────────────────────── REUSABLE WIDGETS ─────────────────────────

class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? glow;

  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(17),
    this.radius = 24,
    this.glow,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: glow == null
            ? null
            : [
                BoxShadow(
                  color: glow!.withValues(alpha: 0.20),
                  blurRadius: 32,
                  spreadRadius: -6,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.white.withValues(alpha: 0.03),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class Panel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;
  final Color? glow;
  final Widget child;

  const Panel({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.trailing,
    this.glow,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      glow: glow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: LinearGradient(
                    colors: [
                      cyan.withValues(alpha: 0.28),
                      violet.withValues(alpha: 0.28),
                    ],
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: const TextStyle(fontSize: 11, color: muted)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool dot;

  const StatusChip({super.key, required this.label, required this.color, this.dot = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fade(begin: 0.3, end: 1, duration: 800.ms),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class InsightTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const InsightTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.30), blurRadius: 16, spreadRadius: -4)],
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 16),
          Text(label, style: const TextStyle(color: muted, fontSize: 9, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class ConnectionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Color color;

  const ConnectionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(detail, style: const TextStyle(color: muted, fontSize: 11)),
            ],
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .fade(begin: 0.3, end: 1, duration: 1100.ms),
      ],
    );
  }
}

class AxisLabel extends StatelessWidget {
  final String label;

  const AxisLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(label, style: const TextStyle(color: muted, fontSize: 9));
}

/// Floating glass navigation pill.
class GlassNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const GlassNav({super.key, required this.index, required this.onTap});

  static const items = [
    (Icons.radar, 'Monitor'),
    (Icons.show_chart, 'History'),
    (Icons.tune, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 32,
      glow: violet,
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (int i = 0; i < items.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                  horizontal: i == index ? 20 : 16,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: i == index
                      ? LinearGradient(
                          colors: [
                            cyan.withValues(alpha: 0.35),
                            violet.withValues(alpha: 0.35),
                          ],
                        )
                      : null,
                  border: i == index
                      ? Border.all(color: Colors.white.withValues(alpha: 0.25))
                      : null,
                  boxShadow: i == index
                      ? [BoxShadow(color: violet.withValues(alpha: 0.45), blurRadius: 18, spreadRadius: -4)]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      items[i].$1,
                      size: 21,
                      color: i == index ? Colors.white : muted,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      child: i == index
                          ? Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                items[i].$2,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
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


// ───────────────────────── HISTORY WIDGETS ─────────────────────────

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const StatTile({super.key, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: tabular.copyWith(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 4),
              const Text('dB', style: TextStyle(fontSize: 10, color: muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class LinePainter extends CustomPainter {
  final List<double> data;
  final double threshold;
  final Animation<double> anim;

  LinePainter(this.data, this.threshold, this.anim) : super(repaint: anim);

  static const minY = 20.0;
  static const maxY = 120.0;
  static const leftPad = 30.0;

  void label(Canvas canvas, String text, Offset at,
      {Color color = muted, bool right = false, bool centerY = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 9.5)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(right ? at.dx - tp.width : at.dx, centerY ? at.dy - tp.height / 2 : at.dy),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - leftPad;
    final plotH = size.height - 8;

    double yFor(double v) =>
        4 + plotH * (1 - ((v - minY) / (maxY - minY)).clamp(0.0, 1.0));
    double xFor(int i) =>
        data.length == 1 ? size.width - 4 : leftPad + plotW * i / (data.length - 1);

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 0.8;
    for (int v = 20; v <= 120; v += 20) {
      final y = yFor(v.toDouble());
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), grid);
      label(canvas, '$v', Offset(leftPad - 6, y), right: true, centerY: true);
    }

    if (data.isEmpty) return;

    final shader = const LinearGradient(colors: [cyan, violet, pink])
        .createShader(Rect.fromLTWH(leftPad, 0, plotW, size.height));

    if (data.length > 1) {
      final line = Path();
      for (int i = 0; i < data.length; i++) {
        final x = xFor(i);
        final y = yFor(data[i]);
        if (i == 0) {
          line.moveTo(x, y);
        } else {
          line.lineTo(x, y);
        }
      }

      final fill = Path.from(line)
        ..lineTo(size.width, 4 + plotH)
        ..lineTo(leftPad, 4 + plotH)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cyan.withValues(alpha: 0.22), cyan.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(leftPad, 0, plotW, size.height)),
      );

      canvas.drawPath(
        line,
        Paint()
          ..shader = shader
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(
        line,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    // dashed limit line
    final ty = yFor(threshold);
    final dash = Paint()
      ..color = danger.withValues(alpha: 0.9)
      ..strokeWidth = 1.2;
    for (double x = leftPad; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, ty), Offset(math.min(x + 5, size.width), ty), dash);
    }
    label(canvas, 'Limit ${threshold.round()} dB', Offset(size.width, ty - 13),
        color: danger, right: true);

    // latest reading with pulsing halo
    final last = Offset(xFor(data.length - 1), yFor(data.last));
    canvas.drawCircle(
      last,
      6 + 8 * anim.value,
      Paint()..color = Colors.white.withValues(alpha: (1 - anim.value) * 0.35),
    );
    canvas.drawCircle(last, 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant LinePainter old) => true;
}
