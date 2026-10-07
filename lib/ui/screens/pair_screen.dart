import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/sync_engine.dart';
import '../../core/settings_store.dart';
import '../../core/models.dart';
import '../widgets/brutal_widgets.dart';
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

  @override
  void initState() {
    super.initState();
    final engine = context.read<SyncEngine>();
    if (engine.isHost) {
      _initHostMode(engine);
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
      _showError('Fout bij maken van koppelverzoek: $e');
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
        context.read<SettingsStore>().onboarded = true;
        Navigator.pushReplacementNamed(context, '/workspace');
      } else if (event is PairingFailedEvent) {
        _showError('Koppelen mislukt: ${event.message}');
      }
    });
  }

  void _showPairConfirmDialog(PairingRequest request) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Bevestig koppeling',
          style: TextStyle(fontFamily: 'ArchivoBlack'),
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
    final engine = context.read<SyncEngine>();
    setState(() {
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
      _showError('Ongeldige code of apparaat onbereikbaar: $e');
    }
  }

  Future<void> _confirmPairingClient() async {
    if (_preview == null) return;
    final engine = context.read<SyncEngine>();
    setState(() {
      _isLoading = true;
    });
    try {
      await engine.confirmPairing(_preview!);
      if (!mounted) return;
      context.read<SettingsStore>().onboarded = true;
      Navigator.pushReplacementNamed(context, '/workspace');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showError('Koppelen mislukt: $e');
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
            BrutalButton(
              onPressed: () => _initHostMode(context.read<SyncEngine>()),
              label: 'Opnieuw proberen',
              color: DotColors.coral,
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final inkColor = theme.brightness == Brightness.dark
        ? DotColors.paper
        : DotColors.ink;
    final minutes = _timeLeft.inMinutes;
    final seconds = (_timeLeft.inSeconds % 60).toString().padLeft(2, '0');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Scan deze QR-code met je telefoon',
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'SpaceGrotesk',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: inkColor, width: 2),
              boxShadow: [
                BoxShadow(color: inkColor, offset: const Offset(4, 4)),
              ],
            ),
            child: QrImageView(
              data: _offer!.qrPayload,
              version: QrVersions.auto,
              size: 200.0,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Handmatige code: ${_offer!.manualCode}',
            style: const TextStyle(
              fontFamily: 'ArchivoBlack',
              fontSize: 22,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_offer!.host}:${_offer!.port}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Geldig nog: $minutes:$seconds',
            style: theme.textTheme.bodySmall?.copyWith(
              color: _timeLeft.inSeconds < 60 ? DotColors.coral : null,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientView() {
    if (_preview != null) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Verbinden met', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            Text(
              _preview!.peerName,
              style: const TextStyle(fontSize: 28, fontFamily: 'ArchivoBlack'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('${_preview!.host}:${_preview!.port}'),
            const SizedBox(height: 48),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BrutalButton(
                    onPressed: _confirmPairingClient,
                    label: 'Bevestig koppeling',
                    color: DotColors.lime,
                  ),
                  const SizedBox(height: 16),
                  BrutalButton(
                    onPressed: () => setState(() {
                      _preview = null;
                    }),
                    label: 'Annuleren',
                    color: DotColors.coral,
                  ),
                ],
              ),
          ],
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
            style: TextStyle(fontFamily: 'ArchivoBlack', fontSize: 24),
          ),
          const SizedBox(height: 16),
          Container(
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? DotColors.paper
                    : DotColors.ink,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.hardEdge,
            child: MobileScanner(
              controller: _scannerController,
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
            style: TextStyle(fontFamily: 'ArchivoBlack', fontSize: 24),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Host (IP:Poort)',
              hintText: '192.168.1.20:48620',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Code',
              hintText: 'ABC123',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          BrutalButton(
            onPressed: () {
              final host = _hostController.text.trim();
              final code = _codeController.text.trim();
              if (host.isEmpty || code.isEmpty) {
                _showError('Vul zowel het IP:poort als de koppelcode in.');
                return;
              }
              final payload = '$host $code';
              _previewPairingClient(payload);
            },
            label: 'Verbinden',
            color: DotColors.coral,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SyncEngine>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final paperColor = isDark ? DotColors.bgDark : DotColors.paper;

    return Scaffold(
      backgroundColor: paperColor,
      appBar: AppBar(
        title: const Text(
          'Apparaat koppelen',
          style: TextStyle(fontFamily: 'ArchivoBlack'),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: engine.isHost ? _buildHostView() : _buildClientView(),
      ),
    );
  }
}
