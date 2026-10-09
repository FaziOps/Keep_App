import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/theme.dart';
import '../../../../core/widgets/common.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/services/protection_rules.dart';

class CategoryStyle {
  const CategoryStyle(this.icon, this.color);
  final IconData icon;
  final Color color;

  static CategoryStyle of(Category c) => switch (c) {
    Category.electronics => const CategoryStyle(Icons.devices_rounded, Color(0xFF6366F1)),
    Category.appliances => const CategoryStyle(Icons.kitchen_rounded, Color(0xFF0EA5E9)),
    Category.furniture => const CategoryStyle(Icons.chair_rounded, Color(0xFFA16207)),
    Category.clothing => const CategoryStyle(Icons.checkroom_rounded, Color(0xFFDB2777)),
    Category.groceries => const CategoryStyle(Icons.shopping_basket_rounded, Color(0xFF16A34A)),
    Category.health => const CategoryStyle(Icons.medical_services_rounded, Color(0xFFDC2626)),
    Category.home => const CategoryStyle(Icons.home_rounded, Color(0xFF0D9488)),
    Category.travel => const CategoryStyle(Icons.flight_rounded, Color(0xFF7C3AED)),
    Category.dining => const CategoryStyle(Icons.restaurant_rounded, Color(0xFFEA580C)),
    Category.other => const CategoryStyle(Icons.category_rounded, Color(0xFF64748B)),
  };
}

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar(this.category, {super.key, this.size = 48});
  final Category category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = CategoryStyle.of(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(style.icon, color: style.color, size: size * 0.5),
    );
  }
}

/// Thumbnail of a receipt image, falling back to the category avatar.
class ReceiptThumbnail extends ConsumerWidget {
  const ReceiptThumbnail({super.key, required this.attachment, required this.category, this.size = 56});
  final Attachment? attachment;
  final Category category;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = attachment;
    if (a == null) return CategoryAvatar(category, size: size);
    final bytes = ref.watch(attachmentBytesProvider(a)).value;
    if (bytes == null) return CategoryAvatar(category, size: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}

class WarrantyBadge extends StatelessWidget {
  const WarrantyBadge(this.status, {super.key, this.dense = true});
  final WarrantyStatus status;
  final bool dense;

  static (String, Color, IconData)? describe(WarrantyStatus status) => switch (status) {
    WarrantyStatus.active => ('Protected', KeeprColors.success, Icons.verified_user_rounded),
    WarrantyStatus.expiringSoon => ('Expiring soon', KeeprColors.amber, Icons.timelapse_rounded),
    WarrantyStatus.expired => ('Expired', const Color(0xFF94A3B8), Icons.shield_outlined),
    WarrantyStatus.none => null,
  };

  @override
  Widget build(BuildContext context) {
    final d = describe(status);
    if (d == null) return const SizedBox.shrink();
    return Pill(label: d.$1, color: d.$2, icon: d.$3, dense: dense);
  }
}

class ReceiptStatusBadge extends StatelessWidget {
  const ReceiptStatusBadge({super.key, required this.status, required this.syncState});
  final ReceiptStatus status;
  final SyncState syncState;

  @override
  Widget build(BuildContext context) {
    final draft = switch (status) {
      ReceiptStatus.queuedOffline => ('Waiting for AI', KeeprColors.sky, Icons.hourglass_top_rounded),
      ReceiptStatus.needsReview => ('Needs review', KeeprColors.amber, Icons.rate_review_rounded),
      ReceiptStatus.extractionFailed ||
      ReceiptStatus.manualEntry => ('Draft', KeeprColors.amber, Icons.edit_note_rounded),
      ReceiptStatus.archived => ('Archived', const Color(0xFF94A3B8), Icons.archive_rounded),
      _ => null,
    };
    if (draft != null) return Pill(label: draft.$1, color: draft.$2, icon: draft.$3, dense: true);
    if (syncState == SyncState.pending) {
      return const Pill(label: 'Syncing', color: KeeprColors.sky, icon: Icons.cloud_upload_rounded, dense: true);
    }
    if (syncState == SyncState.failed) {
      return const Pill(label: 'Sync failed', color: KeeprColors.danger, icon: Icons.cloud_off_rounded, dense: true);
    }
    return const SizedBox.shrink();
  }
}
