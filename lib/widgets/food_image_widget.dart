import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/services/image_storage_service.dart';
import 'package:meal_of_record/services/emoji_service.dart';

/// Widget for displaying food images with fallbacks.
///
/// Priority:
/// 1. Local image (user uploaded, `local:` prefix)
/// 2. Network thumbnail (URL)
/// 3. Custom emoji (user-selected, excluding default '🍴')
/// 4. Smart emoji (auto-generated from food name via [emojiForFoodName])
/// 5. Default emoji ('🍴')
///
/// Usage with a Food object:
/// ```dart
/// FoodImageWidget(food: myFood, size: 40)
/// ```
///
/// Usage with individual parameters (e.g., during editing):
/// ```dart
/// FoodImageWidget(thumbnail: 'local:abc123', emoji: '🍎', name: 'Apple', size: 80)
/// ```
class FoodImageWidget extends StatelessWidget {
  final Food? food;
  final String? thumbnail;
  final String? emoji;
  final String? name;
  final double? size;
  final VoidCallback? onTap;

  const FoodImageWidget({
    super.key,
    this.food,
    this.thumbnail,
    this.emoji,
    this.name,
    this.size,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Use provided food if available, otherwise use individual parameters
    final displayThumbnail = food?.thumbnail ?? thumbnail;
    final displayEmoji = food?.emoji ?? emoji;
    final displayName = food?.name ?? name;

    // Priority: local image > network thumbnail > custom emoji (not default) > smart emoji > default emoji
    if (displayThumbnail != null &&
        displayThumbnail.startsWith(ImageStorageService.localPrefix)) {
      return _buildLocalImage(context, displayThumbnail, displayName);
    } else if (displayThumbnail != null && displayThumbnail.isNotEmpty) {
      return _buildNetworkImage(context, displayThumbnail, displayName);
    } else if (displayEmoji != null &&
        displayEmoji.isNotEmpty &&
        displayEmoji != '🍴') {
      return _buildEmoji(context, displayEmoji);
    } else {
      return _buildFallbackEmoji(context, displayName);
    }
  }

  Widget _buildLocalImage(
    BuildContext context,
    String thumbnail,
    String? displayName,
  ) {
    final guid = thumbnail.replaceFirst(ImageStorageService.localPrefix, '');
    if (guid.isEmpty) {
      return _buildFallbackEmoji(context, displayName);
    }

    return FutureBuilder<String>(
      future: ImageStorageService.instance.getImagePath(guid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _buildFallbackEmoji(context, displayName);
        }

        final imagePath = snapshot.data!;
        final imageFile = File(imagePath);

        return GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                imageFile,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildFallbackEmoji(context, displayName);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNetworkImage(
    BuildContext context,
    String thumbnail,
    String? displayName,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: thumbnail,
            fit: BoxFit.cover,
            placeholder: (context, url) =>
                _buildFallbackEmoji(context, displayName),
            errorWidget: (context, url, error) =>
                _buildFallbackEmoji(context, displayName),
          ),
        ),
      ),
    );
  }

  Widget _buildEmoji(BuildContext context, String emoji) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            emoji,
            style: TextStyle(fontSize: size != null ? size! * 0.6 : 32),
          ),
        ),
      ),
    );
  }

  /// Builds a fallback emoji display.
  /// Priority: smart emoji from name > default emoji '🍴'
  Widget _buildFallbackEmoji(BuildContext context, String? displayName) {
    final emoji = displayName != null && displayName.isNotEmpty
        ? emojiForFoodName(displayName)
        : '🍴';
    return _buildEmoji(context, emoji);
  }
}
