import 'package:flutter/material.dart';
import '../utils/responsive.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? Theme.of(context).colorScheme.primary;
    final compact = Responsive.isCompact(context);
    final padding = compact ? 10.0 : 14.0;
    final hasValue = value.trim().isNotEmpty;

    final content = Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(compact ? 8 : 10),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: cardColor, size: compact ? 20 : 24),
              ),
              const Spacer(),
              if (onTap != null)
                Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
                ),
            ],
          ),
          const Spacer(),
          if (hasValue) ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: (compact
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineSmall)
                    ?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cardColor,
                ),
                maxLines: 1,
              ),
            ),
            SizedBox(height: compact ? 2 : 4),
          ],
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: compact ? 11 : 12,
                  height: 1.2,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
            maxLines: hasValue ? 2 : 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    return Material(
      color: Theme.of(context).cardColor,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              mouseCursor: SystemMouseCursors.click,
              child: content,
            ),
    );
  }
}
