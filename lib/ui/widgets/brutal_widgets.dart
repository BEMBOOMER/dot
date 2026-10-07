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

class BrutalCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;

  const BrutalCard({super.key, required this.child, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? DotColors.paper : DotColors.ink;
    final bgColor = color ?? Theme.of(context).colorScheme.surface;

    Widget card = Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: borderColor,
            offset: const Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }

    return card;
  }
}

class BrutalButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;

  const BrutalButton({
    super.key,
    String? label,
    String? text,
    this.onPressed,
    this.icon,
    Color? color,
    Color? backgroundColor,
    Color? foregroundColor,
  }) : label = label ?? text ?? '',
       color = color ?? backgroundColor;

  @override
  State<BrutalButton> createState() => _BrutalButtonState();
}

class _BrutalButtonState extends State<BrutalButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? DotColors.paper : DotColors.ink;
    final isDisabled = widget.onPressed == null;
    final bgColor = isDisabled
        ? (isDark ? Colors.grey[800]! : Colors.grey[300]!)
        : (widget.color ?? DotColors.coral);
    final textColor = isDark ? DotColors.paper : DotColors.ink;

    return GestureDetector(
      onTapDown: isDisabled ? null : (_) => setState(() => _isPressed = true),
      onTapUp: isDisabled
          ? null
          : (_) {
              setState(() => _isPressed = false);
              widget.onPressed?.call();
            },
      onTapCancel: isDisabled ? null : () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        transform: Matrix4.translationValues(
          _isPressed && !isDisabled ? 4.0 : 0.0,
          _isPressed && !isDisabled ? 4.0 : 0.0,
          0.0,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: borderColor,
              offset: Offset(
                _isPressed && !isDisabled ? 0 : 4,
                _isPressed && !isDisabled ? 0 : 4,
              ),
              blurRadius: 0,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, color: textColor),
              const SizedBox(width: 8),
            ],
            Text(
              widget.label,
              style: TextStyle(
                fontFamily: 'ArchivoBlack',
                color: textColor,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusBar extends StatelessWidget {
  final ConnectionStatus? status;
  final String? peerName;

  const StatusBar({super.key, this.status, this.peerName});

  Color _getStatusColor(ConnectionStatus s) {
    switch (s) {
      case ConnectionStatus.unpaired:
      case ConnectionStatus.failed:
        return DotColors.coral;
      case ConnectionStatus.searching:
      case ConnectionStatus.pairing:
      case ConnectionStatus.syncing:
        return DotColors.amber;
      case ConnectionStatus.connected:
        return DotColors.lime;
      case ConnectionStatus.offline:
        return DotColors.ink;
    }
  }

  @override
  Widget build(BuildContext context) {
    SyncEngine? engine;
    try {
      engine = Provider.of<SyncEngine?>(context);
    } catch (_) {}
    final resolvedStatus =
        status ?? engine?.status ?? ConnectionStatus.unpaired;
    final resolvedPeerName = peerName ?? engine?.peerName;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _getStatusColor(resolvedStatus),
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? DotColors.paper
                  : DotColors.ink,
              width: 1.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          statusLabel(resolvedStatus, peerName: resolvedPeerName),
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class ItemCard extends StatelessWidget {
  final DotItem item;
  final VoidCallback? onTap;

  const ItemCard({super.key, required this.item, this.onTap});

  Color _getSyncStateColor() {
    switch (item.syncState) {
      case SyncState.local:
      case SyncState.waiting:
        return DotColors.amber;
      case SyncState.sending:
        return DotColors.blue;
      case SyncState.received:
        return DotColors.lime;
      case SyncState.failed:
        return DotColors.coral;
    }
  }

  IconData _getTypeIcon() {
    switch (item.type) {
      case ItemType.file:
        return Icons.insert_drive_file;
      case ItemType.text:
        return Icons.text_snippet;
      case ItemType.link:
        return Icons.link;
      case ItemType.note:
        return Icons.note;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? DotColors.paper : DotColors.ink;

    return BrutalCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getTypeIcon()),
                const SizedBox(width: 8),
                Text(
                  itemTypeLabel(item.type),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getSyncStateColor(),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 1.5),
                  ),
                  child: Text(
                    syncStateLabel(item.syncState),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? DotColors.ink : DotColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              item.title,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              itemOriginLabel(context, item),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color
                    ?.withValues(alpha: 0.7),
              ),
            ),
            if (item.type == ItemType.file &&
                item.syncState == SyncState.sending) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: item.progress,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(DotColors.blue),
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
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context).brightness == Brightness.dark
                  ? DotColors.paper.withValues(alpha: 0.5)
                  : DotColors.ink.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark
                    ? DotColors.paper.withValues(alpha: 0.7)
                    : DotColors.ink.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
