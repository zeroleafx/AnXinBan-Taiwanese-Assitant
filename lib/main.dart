import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'recording_controller.dart';

// Palette: https://colorhunt.co/palette/2a7c1376c457fff8cffbe6c2
abstract final class AppColors {
  static const green = Color(0xFF2A7C13);
  static const freshGreen = Color(0xFF76C457);
  static const cream = Color(0xFFFBE6C2);
  static const paleYellow = Color(0xFFFFF8CF);
  // Darker companion shade for readable text on the palette's light surfaces.
  static const ink = Color(0xFF293526);
}

void main() => runApp(const AnXinBanApp());

class AnXinBanApp extends StatelessWidget {
  const AnXinBanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '安心BAN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.green).copyWith(
          primary: AppColors.green,
          onPrimary: Colors.white,
          secondary: AppColors.freshGreen,
          onSecondary: AppColors.ink,
          surface: AppColors.paleYellow,
          onSurface: AppColors.ink,
          outline: AppColors.green,
        ),
        scaffoldBackgroundColor: AppColors.paleYellow,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final RecordingController _recording;
  static const _green = AppColors.green;
  bool get _isRecording => _recording.isRecording;
  bool get _hasStopped => _recording.lastPath != null;
  static const _breeze = MethodChannel('anxinban/breeze');
  int? _modelDownload;

  @override
  void initState() {
    super.initState();
    _recording = RecordingController(
      DeviceRecordingBackend(),
      transcribe:
          !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.android)
          ? (path) async =>
                (await _breeze.invokeMethod<String>('transcribe', path))!
          : null,
    );
    // Android downloads the speech model on first use and reports progress.
    _breeze.setMethodCallHandler((call) async {
      if (call.method == 'downloadProgress' && mounted) {
        setState(() => _modelDownload = call.arguments as int?);
      }
    });
    _recording.addListener(_refresh);
    unawaited(_recording.initialize());
    WidgetsBinding.instance.addObserver(this);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission dialogs cause "inactive"; only stop when actually backgrounded.
    if (state == AppLifecycleState.resumed) {
      unawaited(_recording.setForeground(true));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_recording.setForeground(false));
    }
  }

  @override
  void dispose() {
    _breeze.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    _recording.removeListener(_refresh);
    _recording.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _isRecording ? AppColors.ink : _green;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.cream,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.spa_outlined,
                                color: _green,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '安心BAN',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                                Text(
                                  '你的台語小幫手',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Column(
                            children: [
                              const Text(
                                '有啥物需要幫忙？',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '按一下麥克風，用台語慢慢講',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 36),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.cream.withValues(
                                    alpha: 0.65,
                                  ),
                                  border: Border.all(
                                    color: AppColors.freshGreen,
                                  ),
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.freshGreen,
                                  ),
                                  child: SizedBox(
                                    width: 160,
                                    height: 160,
                                    child: Semantics(
                                      label: _isRecording ? '停止錄音' : '開始錄音',
                                      button: true,
                                      child: ExcludeSemantics(
                                        child: FilledButton(
                                          onPressed: _recording.busy
                                              ? null
                                              : _recording.toggle,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: activeColor,
                                            shape: const CircleBorder(),
                                            padding: EdgeInsets.zero,
                                            elevation: 0,
                                          ),
                                          child: Icon(
                                            _isRecording
                                                ? Icons.stop_rounded
                                                : Icons.mic_rounded,
                                            size: 70,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _isRecording
                                      ? '錄音中 ${_recording.durationLabel}\n再按一下，結束錄音'
                                      : _recording.recognizing &&
                                            _modelDownload != null
                                      ? '第一次使用，正在下載語音模型 $_modelDownload%'
                                      : _recording.recognizing
                                      ? '正在辨識台語…'
                                      : _hasStopped
                                      ? '已儲存錄音，按一下重新開始'
                                      : '點一下，開始說話',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                '只保留最新一段錄音 · 不會上傳',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.ink,
                                ),
                              ),
                              if (!_isRecording &&
                                  _recording.transcribe != null &&
                                  _hasStopped) ...[
                                const SizedBox(height: 16),
                                if (_recording.recognizing)
                                  const CircularProgressIndicator()
                                else if (_recording.transcript != null)
                                  Semantics(
                                    liveRegion: true,
                                    child: SelectableText(
                                      _recording.transcript!,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                  )
                                else ...[
                                  if (_recording.speechError != null)
                                    Text(_recording.speechError!),
                                  TextButton(
                                    onPressed:
                                        _recording.busy || _recording.isPlaying
                                        ? null
                                        : _recording.recognizeLatest,
                                    child: const Text('辨識這段錄音'),
                                  ),
                                ],
                              ],
                              if (_recording.error != null) ...[
                                const SizedBox(height: 16),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _recording.error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFAD493D),
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                              if (_hasStopped && !_isRecording) ...[
                                const SizedBox(height: 18),
                                OutlinedButton.icon(
                                  onPressed: _recording.busy
                                      ? null
                                      : _recording.togglePlayback,
                                  icon: Icon(
                                    _recording.isPlaying
                                        ? Icons.stop_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                  label: Text(
                                    _recording.isPlaying ? '停止播放' : '播放剛才的錄音',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(200, 52),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: AppColors.cream,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AppColors.freshGreen),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '不知道怎麼開始？試著說…',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: AppColors.ink,
                                ),
                              ),
                              SizedBox(height: 18),
                              _Example(
                                icon: Icons.call_outlined,
                                text: '「幫我打電話予阿明」',
                              ),
                              SizedBox(height: 16),
                              _Example(
                                icon: Icons.apps_rounded,
                                text: '「幫我開 LINE」',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Example extends StatelessWidget {
  const _Example({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: _HomePageState._green, size: 22),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, color: AppColors.ink),
        ),
      ),
    ],
  );
}
