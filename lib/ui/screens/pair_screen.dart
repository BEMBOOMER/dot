import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/sync_engine.dart';
import '../../core/settings_store.dart';
import '../../core/models.dart';
import '../widgets/dot_widgets.dart';
import '../dots/dots_stage.dart';
import '../theme/dot_theme.dart';

class PairScreen extends StatefulWidget {
  const PairScreen({super.key});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  // Variables for host (macOS)
  PairingOffer? _offer;
  bool _isLoading = false;
  StreamSubscription<SyncEvent>? _eventSubscription;
  Timer? _countdownTimer;
  Duration _timeLeft = Duration.zero;

  // Variables for client (Android)
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  MobileScannerController? _scannerController;
  PairingPreview? _preview;
  String? _clientError;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    final engine = context.read<SyncEngine>();
    if (engine.isHost) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _initHostMode(engine);
      });
    } else {
      _scannerController = MobileScannerController();
    }
    _listenToEngineEvents(engine);
  }

  Future<void> _initHostMode(SyncEngine engine) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final offer = await engine.createPairingOffer();
      if (!mounted) return;
      setState(() {
        _offer = offer;
        _isLoading = false;
        _timeLeft = offer.expiresAt.difference(DateTime.now());
      });
      _startCountdown(offer.expiresAt);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showError('Een koppelcode maken lukt nog niet. Probeer opnieuw.');
    }
  }

  void _startCountdown(DateTime expiresAt) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = expiresAt.difference(DateTime.now());
      if (remaining.isNegative) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _timeLeft = Duration.zero;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _timeLeft = remaining;
          });
        }
      }
    });
  }

  void _listenToEngineEvents(SyncEngine engine) {
    _eventSubscription = engine.events.listen((event) {
      if (!mounted) return;
      if (event is PairRequestEvent) {
        _showPairConfirmDialog(event.request);
      } else if (event is PairedEvent) {
        _finishPairing();
      } else if (event is PairingFailedEvent) {
        if (engine.isHost) {
          _showError('Koppelen lukt nog niet. Probeer opnieuw.');
        } else {
          setState(() {
            _isLoading = false;
            _clientError =
                'Koppelen lukt nog niet. Controleer je Mac en probeer opnieuw.';
          });
        }
      }
    });
  }

  void _finishPairing() {
    if (!mounted || _completed) return;
    _completed = true;
    context.read<SettingsStore>().onboarded = true;
    Navigator.pushReplacementNamed(context, '/workspace');
  }

  void _showPairConfirmDialog(PairingRequest request) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Bevestig koppeling',
          style: TextStyle(fontFamily: 'Inter'),
        ),
        content: Text('Wil je verbinden met ${request.deviceName}?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<SyncEngine>().respondToPairRequest(
                request.requestId,
                false,
              );
            },
            child: const Text('Annuleren'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<SyncEngine>().respondToPairRequest(
                request.requestId,
                true,
              );
            },
            child: const Text('Bevestig koppeling'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _countdownTimer?.cancel();
    _hostController.dispose();
    _codeController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _previewPairingClient(String payload) async {
    if (_isLoading) return;
    final engine = context.read<SyncEngine>();
    setState(() {
      _clientError = null;
      _isLoading = true;
    });
    try {
      final preview = await engine.previewPairing(payload);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      setState(
        () => _clientError =
            'De code klopt niet of je Mac is niet bereikbaar. Probeer opnieuw.',
      );
    }
  }

  Future<void> _confirmPairingClient() async {
    if (_preview == null) return;
    if (_isLoading) return;
    final engine = context.read<SyncEngine>();
    setState(() {
      _clientError = null;
      _isLoading = true;
    });
    try {
      await engine.confirmPairing(_preview!);
      if (!mounted) return;
      _finishPairing();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      setState(
        () => _clientError =
            'Koppelen lukt nog niet. Controleer je Mac en probeer opnieuw.',
      );
    }
  }

  Widget _buildHostView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_offer == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Geen koppelverzoek beschikbaar'),
            const SizedBox(height: 16),
            DotButton(
              onPressed: () => _initHostMode(context.read<SyncEngine>()),
              label: 'Opnieuw proberen',
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final minutes = _timeLeft.inMinutes;
    final seconds = (_timeLeft.inSeconds % 60).toString().padLeft(2, '0');

    final expired = _timeLeft <= Duration.zero;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              SizedBox(
                height: 150,
                child: DotsStage(
                  status: ConnectionStatus.pairing,
                  reducedMotion: context.watch<SettingsStore>().reducedMotion,
                ),
              ),
              const Text(
                'Scan deze QR-code met DOT op je telefoon',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data: _offer!.qrPayload,
                  version: QrVersions.auto,
                  size: 240,
                ),
              ),
              const SizedBox(height: 20),
              const Text('Handmatig verbinden'),
              const SizedBox(height: 12),
              const Text('Adres'),
              SelectableText(
                '${_offer!.host}:${_offer!.port}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 8),
              const Text('Code'),
              SelectableText(
                _offer!.manualCode,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 28,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                expired
                    ? 'Deze code is verlopen'
                    : 'Nog $minutes:$seconds geldig',
              ),
              const SizedBox(height: 12),
              if (expired)
                DotButton(
                  label: 'Nieuwe code',
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: () => _initHostMode(context.read<SyncEngine>()),
                )
              else
                const Text('Wacht op je telefoon…'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClientView() {
    if (_preview != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DotCard(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Verbinden met ${_preview!.peerName} op ${_preview!.host}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 24),
                        DotButton(
                          onPressed: _isLoading ? null : _confirmPairingClient,
                          label: 'Bevestig koppeling',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        DotButton(
                          onPressed: _isLoading
                              ? null
                              : () => setState(() {
                                  _preview = null;
                                  _clientError = null;
                                }),
                          label: 'Annuleren',
                        ),
                        if (_isLoading) ...[
                          const SizedBox(height: 16),
                          const Center(child: CircularProgressIndicator()),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_clientError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _clientError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Scan QR-code',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 260,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
            clipBehavior: Clip.hardEdge,
            child: MobileScanner(
              controller: _scannerController,
              errorBuilder: (context, error) => ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: const EmptyState(
                  icon: Icons.camera_alt_outlined,
                  message: 'Camera niet beschikbaar. Geef DOT cameratoegang of verbind handmatig.',
                ),
              ),
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                  final payload = barcodes.first.rawValue!;
                  _previewPairingClient(payload);
                }
              },
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Handmatig verbinden',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Adres (IP:poort)',
              hintText: '192.168.1.20:48620',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Code',
              hintText: 'ABC123',
            ),
          ),
          const SizedBox(height: 24),
          DotButton(
            onPressed: _isLoading
                ? null
                : () {
                    final host = _hostController.text.trim();
                    final code = _codeController.text.trim();
                    if (host.isEmpty || code.isEmpty) {
                      setState(
                        () =>
                            _clientError = 'Vul het adres en de koppelcode in.',
                      );
                      return;
                    }
                    final payload = '$host $code';
                    _previewPairingClient(payload);
                  },
            label: 'Verbinden',
            color: Theme.of(context).colorScheme.primary,
          ),
          if (_clientError != null) ...[
            const SizedBox(height: 16),
            Text(
              _clientError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SyncEngine>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final paperColor = isDark ? DotColors.bgDark : DotColors.bg;

    return Scaffold(
      backgroundColor: paperColor,
      appBar: AppBar(
        title: const Text(
          'Apparaat koppelen',
          style: TextStyle(fontFamily: 'Inter'),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ScreenContent(
        child: SafeArea(
          child: engine.isHost ? _buildHostView() : _buildClientView(),
        ),
      ),
    );
  }
}
