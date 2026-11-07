import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/data/store.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/utils/feed_builder.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/datetime_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/models/activities/activity.model.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';

final feedAlbumsProvider = FutureProvider.autoDispose<List<RemoteAlbum>>((ref) async {
  final albums = await ref.watch(remoteAlbumServiceProvider).getAll();
  return albums.where((album) => album.isShared).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
});

String formatFeedChatTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final locale = resolvedDateTimeLocale();
  if (isSameFeedDay(local, now)) {
    return DateFormat.jm(locale).format(local);
  }
  if (isSameFeedDay(local, now.subtract(const Duration(days: 1)))) {
    return context.t.feed_yesterday;
  }
  return DateFormat.MMMd(locale).format(local);
}

@RoutePage()
class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(feedAlbumsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.t.feed), centerTitle: false),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(feedAlbumsProvider.future),
        child: albums.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            children: [
              Padding(padding: const EdgeInsets.all(32), child: Text(context.t.errors.feed_unable_to_load)),
            ],
          ),
          data: (data) {
            if (data.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(48),
                    child: Text(
                      context.t.feed_empty_description,
                      textAlign: TextAlign.center,
                      style: context.textTheme.bodyMedium,
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: data.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 84),
              itemBuilder: (context, index) => _FeedChatTile(album: data[index]),
            );
          },
        ),
      ),
    );
  }
}

class _FeedChatTile extends ConsumerWidget {
  final RemoteAlbum album;

  const _FeedChatTile({required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider)?.id;
    final activities = ref.watch(Store.activity.list(album.id)).valueOrNull ?? const <Activity>[];
    final comments = activities.where((activity) => activity.type == ActivityType.comment).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final lastComment = comments.isEmpty ? null : comments.last;

    final lastAt = lastComment != null && lastComment.createdAt.isAfter(album.updatedAt)
        ? lastComment.createdAt
        : album.updatedAt;

    final String preview;
    if (lastComment != null) {
      final author = lastComment.user.id == me ? context.t.you : lastComment.user.name;
      preview = '$author: ${lastComment.comment ?? ''}';
    } else {
      preview = context.t.feed_photos_count(count: album.assetCount);
    }

    final thumbnailAssetId = album.thumbnailAssetId;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: ClipOval(
        child: SizedBox(
          width: 52,
          height: 52,
          child: thumbnailAssetId != null
              ? Thumbnail.remote(remoteId: thumbnailAssetId, thumbhash: '')
              : ColoredBox(
                  color: context.colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.photo_library_outlined, color: context.primaryColor),
                ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textTheme.titleSmall),
          ),
          const SizedBox(width: 8),
          Text(
            formatFeedChatTime(context, lastAt),
            style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant),
      ),
      onTap: () => unawaited(context.pushRoute(FeedChatRoute(album: album))),
    );
  }
}
