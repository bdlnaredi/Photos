import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/models/activities/activity.model.dart';

const Duration kFeedPhotoGroupWindow = Duration(minutes: 10);

sealed class FeedItem {
  final DateTime createdAt;

  const FeedItem(this.createdAt);
}

class FeedDayItem extends FeedItem {
  const FeedDayItem(super.createdAt);
}

class FeedPhotoGroupItem extends FeedItem {
  final String ownerId;
  final List<RemoteAsset> assets;
  final List<Activity> likes;

  FeedPhotoGroupItem({required this.ownerId, required DateTime createdAt})
    : assets = [],
      likes = [],
      super(createdAt);
}

class FeedCommentItem extends FeedItem {
  final Activity activity;
  final RemoteAsset? replyTo;

  FeedCommentItem({required this.activity, this.replyTo}) : super(activity.createdAt);
}

DateTime feedAssetTime(RemoteAsset asset) => (asset.uploadedAt ?? asset.createdAt).toLocal();

bool isSameFeedDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

List<FeedItem> buildFeedItems(List<RemoteAsset> assets, List<Activity> activities) {
  final sortedAssets = [...assets]..sort((a, b) => feedAssetTime(a).compareTo(feedAssetTime(b)));
  final assetsById = {for (final asset in assets) asset.id: asset};

  final groups = <FeedPhotoGroupItem>[];
  final groupByAssetId = <String, FeedPhotoGroupItem>{};

  for (final asset in sortedAssets) {
    final time = feedAssetTime(asset);
    FeedPhotoGroupItem? group = groups.isEmpty ? null : groups.last;
    if (group == null ||
        group.ownerId != asset.ownerId ||
        time.difference(feedAssetTime(group.assets.last)) > kFeedPhotoGroupWindow) {
      group = FeedPhotoGroupItem(ownerId: asset.ownerId, createdAt: time);
      groups.add(group);
    }
    group.assets.add(asset);
    groupByAssetId[asset.id] = group;
  }

  final comments = <FeedCommentItem>[];
  for (final activity in activities) {
    final assetId = activity.assetId;
    if (activity.type == ActivityType.like) {
      if (assetId != null) {
        groupByAssetId[assetId]?.likes.add(activity);
      }
      continue;
    }
    comments.add(FeedCommentItem(activity: activity, replyTo: assetId == null ? null : assetsById[assetId]));
  }

  final merged = <FeedItem>[...groups, ...comments]
    ..sort((a, b) => a.createdAt.toLocal().compareTo(b.createdAt.toLocal()));

  final items = <FeedItem>[];
  DateTime? previous;
  for (final item in merged) {
    final local = item.createdAt.toLocal();
    if (previous == null || !isSameFeedDay(previous, local)) {
      items.add(FeedDayItem(local));
      previous = local;
    }
    items.add(item);
  }
  return items;
}
