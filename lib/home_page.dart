import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'assistant_controller.dart';
import 'breeze_channel.dart';
import 'contact_matcher.dart';
import 'mic_button.dart';
import 'phone_actions.dart';
import 'recording_controller.dart';
import 'speech_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.recording, this.assistant, this.model});

  /// Injected by tests and previews; the device versions are used otherwise.
  final RecordingController? recording;
  final AssistantController? assistant;
  final SpeechModelController? model;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  BreezeChannel? _breeze;
  late final RecordingController _recording;
  late final AssistantController _assistant;
  late final SpeechModelController _model;
  bool _deferred = false;

  @override
  void initState() {
    super.initState();
    _assistant = widget.assistant ?? AssistantController(DevicePhoneActions());
    _recording = widget.recording ?? _deviceRecording();
    _model = widget.model ?? SpeechModelController(_breeze);
    _recording.onTranscript = _assistant.handle;
    _recording.addListener(_refresh);
    _assistant.addListener(_refresh);
    _model.addListener(_modelChanged);
    unawaited(_model.refresh());
    WidgetsBinding.instance.addObserver(this);
  }

  RecordingController _deviceRecording() {
    final transcribes =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    final breeze = transcribes ? BreezeChannel() : null;
    breeze?.downloadPercent.addListener(_refresh);
    _breeze = breeze;
    final recording = RecordingController(DeviceRecordingBackend());
    unawaited(recording.initialize());
    return recording;
  }

  void _modelChanged() {
    if (_breeze != null) {
      _recording.transcribe = _model.phase == ModelPhase.ready
          ? _breeze!.transcribe
          : null;
    }
    _refresh();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission dialogs cause "inactive"; only stop when actually backgrounded.
    if (state == AppLifecycleState.resumed) {
      unawaited(_recording.setForeground(true));
      // The model may have been installed or Wi-Fi joined in the meantime.
      unawaited(_model.refresh());
      // The flashlight may have been switched from the control centre.
      unawaited(_assistant.syncTorch());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_recording.setForeground(false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recording.removeListener(_refresh);
    _assistant.removeListener(_refresh);
    _model.removeListener(_modelChanged);
    _recording.onTranscript = null;
    if (widget.recording == null) _recording.dispose();
    if (widget.assistant == null) _assistant.dispose();
    if (widget.model == null) _model.dispose();
    _breeze?.downloadPercent.removeListener(_refresh);
    _breeze?.dispose();
    super.dispose();
  }

  bool get _busy => _recording.recognizing || _assistant.working;

  void _tapMic() {
    unawaited(HapticFeedback.mediumImpact());
    if (!_recording.isRecording) _assistant.clear();
    unawaited(_recording.toggle());
  }

  (String, String) get _headline {
    if (_recording.isRecording) {
      return ('正在聽…', '${_recording.durationLabel} / 01:00 · 講完再點一下');
    }
    if (_recording.recognizing) {
      final percent = _breeze?.downloadPercent.value;
      return percent == null
          ? ('辨識中…', '請等一下')
          : ('準備中…', '第一次使用，下載語音模型 $percent%');
    }
    if (_assistant.working) return ('處理中…', '請等一下');
    final again = _assistant.outcome != null || _recording.transcript != null;
    return ('有啥物需要幫忙？', again ? '點一下，再講一次' : '點一下，用台語講');
  }

  @override
  Widget build(BuildContext context) {
    if (!_deferred && _model.phase != ModelPhase.ready) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: _model.phase == ModelPhase.checking
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _modelPanel(),
                          if (_model.phase != ModelPhase.downloading)
                            TextButton(
                              onPressed: () => setState(() => _deferred = true),
                              child: const Text('稍後下載，先使用錄音'),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
    }
    final (title, subtitle) = _headline;
    final micState = _recording.isRecording
        ? MicState.recording
        : _busy
        ? MicState.busy
        : MicState.ready;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.paleYellow, AppColors.sand],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: LayoutBuilder(
              builder: (context, box) {
                final height = box.maxHeight;
                final micSize = ((height - 52 - height * 0.3 - 120) / 1.22)
                    .clamp(120.0, 196.0);
                return Column(
                  children: [
                    const _TopBar(),
                    if (_deferred &&
                        _model.phase != ModelPhase.ready &&
                        !_recording.isRecording)
                      TextButton(
                        onPressed: _recording.busy || _recording.isPlaying
                            ? null
                            : () => setState(() => _deferred = false),
                        child: const Text('下載語音模型以啟用辨識'),
                      ),
                    // Everything scales down instead of scrolling on small
                    // screens or with large system text.
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: box.maxWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _Headline(title: title, subtitle: subtitle),
                                SizedBox(height: micSize * 0.2 + 16),
                                MicButton(
                                  backend: _recording.backend,
                                  size: micSize,
                                  state: micState,
                                  onPressed: _recording.busy || _busy
                                      ? null
                                      : _tapMic,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: height * 0.42),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          width: box.maxWidth,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: _panel(),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel() {
    final recording = _recording;
    if (recording.error case final error?) {
      final denied = recording.micDenied;
      return ResultCard(
        key: const ValueKey('error'),
        tone: OutcomeTone.problem,
        icon: denied ? Icons.mic_off_rounded : Icons.error_outline_rounded,
        title: denied ? '需要麥克風權限' : '錄音出了問題',
        detail: denied ? '請到設定打開麥克風' : error,
        children: [
          if (denied)
            _CardButton(
              icon: Icons.settings_rounded,
              label: '打開設定',
              onPressed: _assistant.actions.openSettings,
            ),
        ],
      );
    }
    if (_assistant.outcome case final outcome?) {
      // When choosing a contact, the choices are all that matter.
      final choosing = outcome.choices.isNotEmpty;
      return ResultCard(
        key: ObjectKey(outcome),
        tone: outcome.tone,
        icon: outcome.icon,
        title: outcome.title,
        detail: outcome.detail,
        heard: choosing ? null : outcome.heard,
        trailing: choosing ? null : _replayButton(),
        gap: choosing ? 8 : 12,
        children: [
          if (outcome.showExamples) const _Examples(),
          for (final contact in outcome.choices)
            _ContactButton(
              contact: contact,
              onPressed: () => _assistant.call(contact),
            ),
          if (outcome.action case final action?)
            _CardButton(
              icon: switch (action) {
                OutcomeAction.torchOff => Icons.flashlight_off_rounded,
                OutcomeAction.openSettings => Icons.settings_rounded,
              },
              label: switch (action) {
                OutcomeAction.torchOff => '關掉手電筒',
                OutcomeAction.openSettings => '打開設定',
              },
              onPressed: () => _assistant.runAction(action),
            ),
        ],
      );
    }
    final canRetry =
        recording.speechError != null &&
        recording.lastPath != null &&
        !recording.isRecording &&
        !recording.recognizing;
    if (canRetry) {
      return ResultCard(
        key: const ValueKey('speech-error'),
        tone: OutcomeTone.problem,
        icon: Icons.hearing_disabled_rounded,
        title: '沒有聽清楚',
        detail: recording.speechError,
        trailing: _replayButton(),
        children: [
          _CardButton(
            icon: Icons.refresh_rounded,
            label: '再試一次',
            onPressed: recording.recognizeLatest,
          ),
        ],
      );
    }
    if (recording.lastPath != null &&
        !recording.isRecording &&
        !recording.recognizing &&
        recording.transcript == null) {
      return ResultCard(
        key: const ValueKey('saved'),
        tone: OutcomeTone.done,
        icon: Icons.check_rounded,
        title: '錄好了',
        trailing: _replayButton(),
        children: [
          if (recording.transcribe != null)
            _CardButton(
              icon: Icons.hearing_rounded,
              label: '辨識這段錄音',
              onPressed: recording.recognizeLatest,
            ),
        ],
      );
    }
    // The light stays on after its card is gone, so its off button stays too.
    if (_assistant.torchOn) {
      return ResultCard(
        key: const ValueKey('torch'),
        tone: OutcomeTone.done,
        icon: Icons.flashlight_on_rounded,
        title: '手電筒開著',
        children: [
          _CardButton(
            icon: Icons.flashlight_off_rounded,
            label: '關掉手電筒',
            onPressed: () => _assistant.runAction(OutcomeAction.torchOff),
          ),
        ],
      );
    }
    return const HintsCard(key: ValueKey('hints'));
  }

  /// Asks before the large speech model download, then shows its progress.
  Widget _modelPanel() {
    final model = _model;
    final status = model.status;
    final size = status?.sizeLabel ?? '';
    switch (model.phase) {
      case ModelPhase.downloading:
        return ResultCard(
          key: const ValueKey('model-downloading'),
          tone: OutcomeTone.info,
          icon: Icons.downloading_rounded,
          title: model.verifying ? '檢查檔案中' : '下載中 ${model.percent}%',
          detail: model.verifying ? '快好了' : '$size，只要下載一次',
          children: [
            _DownloadBar(value: model.verifying ? null : model.percent / 100),
          ],
        );
      case ModelPhase.failed:
        return ResultCard(
          key: const ValueKey('model-failed'),
          tone: OutcomeTone.problem,
          icon: Icons.cloud_off_rounded,
          title: '下載沒有成功',
          detail: (model.error ?? '請再試一次').replaceFirst(RegExp(r'。$'), ''),
          children: [
            _CardButton(
              icon: Icons.refresh_rounded,
              label: '再試一次',
              onPressed: model.download,
            ),
          ],
        );
      case ModelPhase.checking || ModelPhase.ready || ModelPhase.missing:
        final continues = (status?.downloadedBytes ?? 0) > 0;
        final network = status?.network ?? ModelNetwork.unmetered;
        return ResultCard(
          key: const ValueKey('model-missing'),
          tone: network == ModelNetwork.unmetered
              ? OutcomeTone.info
              : OutcomeTone.problem,
          icon: network == ModelNetwork.none
              ? Icons.wifi_off_rounded
              : Icons.download_rounded,
          title: continues ? '繼續下載語音模型' : '先下載語音模型',
          detail: switch (network) {
            ModelNetwork.none => '現在沒有網路',
            ModelNetwork.metered => '$size，現在不是 Wi-Fi',
            ModelNetwork.unmetered =>
              continues ? '已經下載 ${status?.percent ?? 0}%' : '$size，只要下載一次',
          },
          children: [
            _CardButton(
              icon: Icons.download_rounded,
              label: network == ModelNetwork.metered
                  ? '用行動數據下載'
                  : continues
                  ? '繼續下載'
                  : '開始下載',
              onPressed: model.download,
            ),
          ],
        );
    }
  }

  Widget? _replayButton() {
    final recording = _recording;
    if (recording.lastPath == null || recording.isRecording) return null;
    return IconButton.filledTonal(
      tooltip: recording.isPlaying ? '停止播放' : '播放剛才的錄音',
      iconSize: 28,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.green,
        minimumSize: const Size.square(52),
      ),
      onPressed: recording.busy ? null : recording.togglePlayback,
      icon: Icon(
        recording.isPlaying ? Icons.stop_rounded : Icons.volume_up_rounded,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.spa_rounded, color: AppColors.green),
        ),
        const SizedBox(width: 10),
        const Text(
          '安心BAN',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );
}

class _Headline extends StatelessWidget {
  const _Headline({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            title,
            key: ValueKey(title),
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 33,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w500,
            color: AppColors.ink.withValues(alpha: 0.72),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: AppColors.freshGreen.withValues(alpha: 0.35)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A3D5A1E),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

/// What can be said, shown before the first request.
class HintsCard extends StatelessWidget {
  const HintsCard({super.key});

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '可以這樣講',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.ink.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),
        const _Examples(),
      ],
    ),
  );
}

class _Examples extends StatelessWidget {
  const _Examples();

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Expanded(child: _Hint(Icons.call_rounded, '打予阿明')),
          SizedBox(width: 10),
          Expanded(child: _Hint(Icons.chat_rounded, '開 LINE')),
        ],
      ),
      SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _Hint(Icons.flashlight_on_rounded, '開手電筒')),
          SizedBox(width: 10),
          Expanded(child: _Hint(Icons.near_me_rounded, '帶我去車站')),
        ],
      ),
    ],
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: AppColors.cream,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 21, color: AppColors.green),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ),
    ],
  );
}

/// The result of a request: what was done, what was heard, and follow-ups.
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    this.detail,
    this.heard,
    this.trailing,
    this.children = const [],
    this.gap = 12,
  });

  final OutcomeTone tone;
  final IconData icon;
  final String title;
  final String? detail;
  final String? heard;
  final Widget? trailing;
  final List<Widget> children;

  /// Space above each of [children].
  final double gap;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      OutcomeTone.done => AppColors.green,
      OutcomeTone.info => AppColors.leaf,
      OutcomeTone.problem => AppColors.coral,
    };
    final detail = this.detail;
    final heard = this.heard;
    final trailing = this.trailing;
    return Semantics(
      liveRegion: true,
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          height: 1.25,
                        ),
                      ),
                      if (detail != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              color: AppColors.ink.withValues(alpha: 0.72),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
            ),
            if (heard != null && heard.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, left: 4),
                child: Text(
                  '「$heard」',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.ink.withValues(alpha: 0.55),
                  ),
                ),
              ),
            for (final child in children)
              Padding(
                padding: EdgeInsets.only(top: gap),
                child: child,
              ),
          ],
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 24),
    label: Text(
      label,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
    ),
  );
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({required this.contact, required this.onPressed});
  final ContactEntry contact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(58),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      side: BorderSide(color: AppColors.freshGreen.withValues(alpha: 0.8)),
      foregroundColor: AppColors.ink,
    ),
    child: Row(
      children: [
        const Icon(Icons.call_rounded, color: AppColors.green),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                contact.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                contact.number,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.ink.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DownloadBar extends StatelessWidget {
  const _DownloadBar({required this.value});

  /// 0..1, or null while the amount of work left is unknown.
  final double? value;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: LinearProgressIndicator(
      value: value,
      minHeight: 14,
      color: AppColors.green,
      backgroundColor: AppColors.cream,
    ),
  );
}
