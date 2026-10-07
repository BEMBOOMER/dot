import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/sync_engine.dart';
import '../theme/dot_theme.dart';

String itemOriginLabel(BuildContext context, DotItem item) {
  final engine = context.watch<SyncEngine?>();
  if (item.originDeviceId == engine?.localDeviceId) {
    return Platform.isMacOS ? 'Van deze Mac' : 'Van deze telefoon';
  }
  return 'Van ${item.originName}';
}

class DotCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  const DotCard({super.key, required this.child, this.onTap, this.color});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      boxShadow: Theme.of(context).brightness == Brightness.dark
          ? []
          : const [
              BoxShadow(
                color: Color(0x0A000000),
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
              BoxShadow(
                color: Color(0x0F000000),
                offset: Offset(0, 6),
                blurRadius: 20,
              ),
            ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    ),
  );
}

enum DotButtonStyle { primary, secondary, ghost }

class DotButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final DotButtonStyle variant;
  const DotButton({
    super.key,
    String? label,
    String? text,
    this.onPressed,
    this.icon,
    Color? color,
    Color? backgroundColor,
    Color? foregroundColor,
    this.variant = DotButtonStyle.primary,
  }) : label = label ?? text ?? '',
       color = color ?? backgroundColor;
  @override
  State<DotButton> createState() => _DotButtonState();
}

class _DotButtonState extends State<DotButton> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = widget.variant == DotButtonStyle.primary;
    final foreground = primary
        ? Colors.white
        : widget.variant == DotButtonStyle.ghost
        ? widget.color ?? scheme.primary
        : scheme.onSurface;
    final background = primary
        ? widget.color ?? scheme.primary
        : widget.variant == DotButtonStyle.secondary
        ? DotColors.muted(context)
        : Colors.transparent;
    return AnimatedScale(
      scale: pressed ? .98 : 1,
      duration: const Duration(milliseconds: 120),
      child: Listener(
        onPointerDown: widget.onPressed == null
            ? null
            : (_) => setState(() => pressed = true),
        onPointerUp: (_) => setState(() => pressed = false),
        onPointerCancel: (_) => setState(() => pressed = false),
        child: TextButton(
          onPressed: widget.onPressed,
          style: TextButton.styleFrom(
            backgroundColor: pressed
                ? Color.lerp(background, Colors.black, .08)
                : background,
            foregroundColor: foreground,
            minimumSize: Size(
              0,
              MediaQuery.sizeOf(context).width > 800 ? 44 : 52,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 20, color: foreground),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(widget.label)),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const StatusPill({super.key, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    ],
  );
}

class StatusLine extends StatelessWidget {
  final ConnectionStatus? status;
  final String? peerName;
  const StatusLine({super.key, this.status, this.peerName});
  @override
  Widget build(BuildContext context) {
    SyncEngine? engine;
    try {
      engine = Provider.of<SyncEngine?>(context);
    } catch (_) {}
    final resolved = status ?? engine?.status ?? ConnectionStatus.unpaired;
    final color = switch (resolved) {
      ConnectionStatus.connected => DotColors.success(context),
      ConnectionStatus.failed => Theme.of(context).colorScheme.error,
      ConnectionStatus.searching ||
      ConnectionStatus.pairing ||
      ConnectionStatus.syncing => DotColors.warning(context),
      _ => DotColors.secondary(context),
    };
    return StatusPill(
      label: statusLabel(resolved, peerName: peerName ?? engine?.peerName),
      color: color,
    );
  }
}

class ItemCard extends StatelessWidget {
  final DotItem item;
  final VoidCallback? onTap;
  const ItemCard({super.key, required this.item, this.onTap});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (item.syncState) {
      SyncState.received => DotColors.success(context),
      SyncState.failed => theme.colorScheme.error,
      SyncState.sending => theme.colorScheme.primary,
      SyncState.waiting => DotColors.warning(context),
      _ => DotColors.secondary(context),
    };
    final icon = switch (item.type) {
      ItemType.file => Icons.insert_drive_file_outlined,
      ItemType.text => Icons.text_snippet_outlined,
      ItemType.link => Icons.link_outlined,
      ItemType.note => Icons.note_outlined,
    };
    final elapsed = DateTime.now().difference(item.updatedAt);
    final time = elapsed.inMinutes < 1
        ? 'Zojuist'
        : elapsed.inHours < 1
        ? '${elapsed.inMinutes} min geleden'
        : elapsed.inDays < 1
        ? '${elapsed.inHours} uur geleden'
        : '${elapsed.inDays} dagen geleden';
    return DotCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Text(
                  itemTypeLabel(item.type),
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: StatusPill(
                      label: syncStateLabel(item.syncState),
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              item.title,
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  itemOriginLabel(context, item),
                  style: theme.textTheme.bodySmall,
                ),
                Text(time, style: theme.textTheme.bodySmall),
              ],
            ),
            if (item.type == ItemType.file &&
                item.syncState == SyncState.sending) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: item.progress,
                minHeight: 3,
                color: theme.colorScheme.primary,
                backgroundColor: DotColors.muted(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyState({super.key, required this.icon, required this.message});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class ScreenContent extends StatelessWidget {
  final Widget child;
  const ScreenContent({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: child,
    ),
  );
}
