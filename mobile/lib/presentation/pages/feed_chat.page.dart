import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/data/store.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/domain/utils/feed_builder.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/datetime_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/models/activities/activity.model.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/widgets/common/user_circle_avatar.dart';

const Duration _kRefreshInterval = Duration(seconds: 15);
const int _kMaxTiles = 4;

@RoutePage()
class FeedChatPage extends ConsumerStatefulWidget {
  final RemoteAlbum album;

  const FeedChatPage({super.key, required this.album});

  @override
  ConsumerState<FeedChatPage> createState() => _FeedChatPageState();
}

class _FeedChatPageState extends ConsumerState<FeedChatPage> {
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  Timer? _timer;
  List<RemoteAsset> _assets = const [];
  List<UserDto> _members = const [];
  RemoteAsset? _replyTo;
  bool _isSending = false;

  RemoteAlbum get _album => widget.album;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(() => setState(() {}));
    unawaited(_loadAssets());
    unawaited(_loadMembers());
    _timer = Timer.periodic(_kRefreshInterval, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    final assets = await ref.read(remoteAlbumServiceProvider).getAssets(_album.id);
    if (mounted) {
      setState(() => _assets = assets);
    }
  }

  Future<void> _loadMembers() async {
    final members = await ref.read(remoteAlbumServiceProvider).getSharedUsers(_album.id);
    if (mounted) {
      setState(() => _members = members);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(Store.activity.list(_album.id));
    await _loadAssets();
  }

  Future<void> _send() async {
    final comment = _inputController.text.trim();
    if (comment.isEmpty || _isSending) {
      return;
    }
    setState(() => _isSending = true);
    try {
      await ref.read(Store.activity).addComment(_album.id, comment, assetId: _replyTo?.id);
      _inputController.clear();
      setState(() => _replyTo = null);
    } catch (_) {
      if (mounted) {
        ImmichToast.show(context: context, msg: context.t.errors.feed_unable_to_update, toastType: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _addPhotos() async {
    final notifier = ref.read(remoteAlbumProvider.notifier);
    final newAssets = await context.pushRoute<Set<BaseAsset>>(
      AssetSelectionTimelineRoute(lockedSelectionAssets: _assets.toSet()),
    );
    if (newAssets == null || newAssets.isEmpty) {
      return;
    }
    await notifier.addAssetsToAlbum(_album.id, newAssets);
    await _loadAssets();
  }

  Future<void> _toggleLike(FeedPhotoGroupItem group, String? me) async {
    final mutations = ref.read(Store.activity);
    final existing = group.likes.where((like) => like.user.id == me).firstOrNull;
    try {
      if (existing != null) {
        await mutations.remove(existing);
      } else {
        await mutations.addLike(_album.id, assetId: group.assets.first.id);
      }
    } catch (_) {
      if (mounted) {
        ImmichToast.show(context: context, msg: context.t.errors.feed_unable_to_update, toastType: ToastType.error);
      }
    }
  }

  Future<void> _deleteComment(Activity activity) async {
    try {
      await ref.read(Store.activity).remove(activity);
    } catch (_) {
      if (mounted) {
        ImmichToast.show(context: context, msg: context.t.errors.feed_unable_to_update, toastType: ToastType.error);
      }
    }
  }

  void _startReply(RemoteAsset asset) {
    setState(() => _replyTo = asset);
    _inputFocus.requestFocus();
  }

  void _openAlbum() {
    unawaited(context.pushRoute(RemoteAlbumRoute(album: _album)));
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final activities = ref.watch(Store.activity.list(_album.id)).valueOrNull ?? const <Activity>[];
    final items = buildFeedItems(_assets, activities);

    final usersById = <String, UserDto>{
      for (final user in _members) user.id: user,
      for (final activity in activities) activity.user.id: activity.user,
      if (me != null) me.id: me,
    };
    final memberNames = [
      if (_album.ownerId != me?.id) _album.ownerName,
      ..._members.where((user) => user.id != me?.id).map((user) => user.name),
      context.t.you,
    ].join(', ');

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              memberNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.photo_library_outlined), tooltip: context.t.view_album, onPressed: _openAlbum),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ColoredBox(
                color: context.colorScheme.surfaceContainerLowest,
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            context.t.feed_no_messages,
                            textAlign: TextAlign.center,
                            style: context.textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[items.length - 1 - index];
                            return switch (item) {
                              final FeedDayItem day => _DayChip(date: day.createdAt),
                              final FeedPhotoGroupItem group => _PhotoBubble(
                                group: group,
                                owner: usersById[group.ownerId],
                                ownerName:
                                    usersById[group.ownerId]?.name ??
                                    (group.ownerId == _album.ownerId ? _album.ownerName : ''),
                                isMine: group.ownerId == me?.id,
                                isLiked: group.likes.any((like) => like.user.id == me?.id),
                                canInteract: _album.isActivityEnabled,
                                onOpen: _openAlbum,
                                onLike: () => unawaited(_toggleLike(group, me?.id)),
                                onReply: () => _startReply(group.assets.first),
                              ),
                              final FeedCommentItem comment => _CommentBubble(
                                item: comment,
                                isMine: comment.activity.user.id == me?.id,
                                canDelete: comment.activity.user.id == me?.id || _album.ownerId == me?.id,
                                onDelete: () => unawaited(_deleteComment(comment.activity)),
                              ),
                            };
                          },
                        ),
                      ),
              ),
            ),
            if (_album.isActivityEnabled)
              _Composer(
                controller: _inputController,
                focusNode: _inputFocus,
                replyTo: _replyTo,
                isSending: _isSending,
                onCancelReply: () => setState(() => _replyTo = null),
                onAddPhotos: () => unawaited(_addPhotos()),
                onSend: () => unawaited(_send()),
              )
            else
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(context.t.comments_are_disabled, style: context.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

String _time(DateTime value) => DateFormat.jm(resolvedDateTimeLocale()).format(value.toLocal());

class _DayChip extends StatelessWidget {
  final DateTime date;

  const _DayChip({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final locale = resolvedDateTimeLocale();
    final String label;
    if (isSameFeedDay(date, now)) {
      label = context.t.feed_today;
    } else if (isSameFeedDay(date, now.subtract(const Duration(days: 1)))) {
      label = context.t.feed_yesterday;
    } else if (date.year == now.year) {
      label = DateFormat.MMMMd(locale).format(date);
    } else {
      label = DateFormat.yMMMMd(locale).format(date);
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Text(label, style: context.textTheme.labelSmall),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool isMine;
  final Widget child;
  final EdgeInsets padding;

  const _Bubble({required this.isMine, required this.child, this.padding = const EdgeInsets.all(4)});

  @override
  Widget build(BuildContext context) {
    final color = isMine ? context.colorScheme.primaryContainer : context.colorScheme.surfaceContainer;
    return Container(
      constraints: BoxConstraints(maxWidth: context.width * 0.78),
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 18),
        ),
      ),
      child: child,
    );
  }
}

class _MessageRow extends StatelessWidget {
  final bool isMine;
  final UserDto? author;
  final Widget bubble;
  final Widget? trailing;

  const _MessageRow({required this.isMine, required this.author, required this.bubble, this.trailing});

  @override
  Widget build(BuildContext context) {
    final avatar = author;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            avatar != null ? UserCircleAvatar(user: avatar, size: 28) : const SizedBox(width: 28),
            const SizedBox(width: 6),
          ],
          if (isMine && trailing != null) trailing!,
          Flexible(child: bubble),
          if (!isMine && trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _PhotoBubble extends StatelessWidget {
  final FeedPhotoGroupItem group;
  final UserDto? owner;
  final String ownerName;
  final bool isMine;
  final bool isLiked;
  final bool canInteract;
  final VoidCallback onOpen;
  final VoidCallback onLike;
  final VoidCallback onReply;

  const _PhotoBubble({
    required this.group,
    required this.owner,
    required this.ownerName,
    required this.isMine,
    required this.isLiked,
    required this.canInteract,
    required this.onOpen,
    required this.onLike,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = group.assets.take(_kMaxTiles).toList();
    final extra = group.assets.length - _kMaxTiles;
    final single = tiles.length == 1;

    Widget tile(RemoteAsset asset, int index) {
      return ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Thumbnail.fromAsset(asset: asset),
            if (asset.isVideo)
              const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 36)),
            if (index == _kMaxTiles - 1 && extra > 0)
              ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Text(
                    '+$extra',
                    style: context.textTheme.headlineSmall?.copyWith(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return _MessageRow(
      isMine: isMine,
      author: owner,
      bubble: _Bubble(
        isMine: isMine,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine && ownerName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Text(
                  ownerName,
                  style: context.textTheme.labelMedium?.copyWith(color: context.primaryColor),
                ),
              ),
            GestureDetector(
              onTap: onOpen,
              child: single
                  ? AspectRatio(aspectRatio: _aspectRatio(tiles.first), child: tile(tiles.first, 0))
                  : GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [for (var i = 0; i < tiles.length; i++) tile(tiles[i], i)],
                    ),
            ),
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isLiked ? Colors.red : null,
                    size: 20,
                  ),
                  tooltip: context.t.like,
                  onPressed: canInteract ? onLike : null,
                ),
                if (group.likes.isNotEmpty) Text('${group.likes.length}', style: context.textTheme.labelSmall),
                if (canInteract)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.reply_rounded, size: 20),
                    tooltip: context.t.feed_reply,
                    onPressed: onReply,
                  ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${context.t.feed_photos_count(count: group.assets.length)} · ${_time(group.createdAt)}',
                    style: context.textTheme.labelSmall?.copyWith(color: context.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _aspectRatio(RemoteAsset asset) {
    final width = asset.width;
    final height = asset.height;
    if (width == null || height == null || width == 0 || height == 0) {
      return 1;
    }
    return (width / height).clamp(0.6, 1.8).toDouble();
  }
}

class _CommentBubble extends StatelessWidget {
  final FeedCommentItem item;
  final bool isMine;
  final bool canDelete;
  final VoidCallback onDelete;

  const _CommentBubble({required this.item, required this.isMine, required this.canDelete, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final replyTo = item.replyTo;
    final author = item.activity.user;

    return GestureDetector(
      onLongPress: canDelete
          ? () => showModalBottomSheet<void>(
              context: context,
              builder: (sheetContext) => SafeArea(
                child: ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(context.t.delete),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onDelete();
                  },
                ),
              ),
            )
          : null,
      child: _MessageRow(
        isMine: isMine,
        author: author,
        bubble: _Bubble(
          isMine: isMine,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMine)
                Text(author.name, style: context.textTheme.labelMedium?.copyWith(color: context.primaryColor)),
              if (replyTo != null)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: context.colorScheme.onSurface.withValues(alpha: 0.05),
                    border: Border(left: BorderSide(color: context.primaryColor, width: 3)),
                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.all(Radius.circular(4)),
                          child: Thumbnail.fromAsset(asset: replyTo),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(context.t.feed_replied_to_photo, style: context.textTheme.labelSmall)),
                    ],
                  ),
                ),
              Text(item.activity.comment ?? '', style: context.textTheme.bodyMedium),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _time(item.createdAt),
                  style: context.textTheme.labelSmall?.copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final RemoteAsset? replyTo;
  final bool isSending;
  final VoidCallback onCancelReply;
  final VoidCallback onAddPhotos;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.replyTo,
    required this.isSending,
    required this.onCancelReply,
    required this.onAddPhotos,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final reply = replyTo;
    final canSend = controller.text.trim().isNotEmpty && !isSending;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reply != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: context.colorScheme.surfaceContainerHigh,
                border: Border(left: BorderSide(color: context.primaryColor, width: 3)),
                borderRadius: const BorderRadius.all(Radius.circular(8)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                      child: Thumbnail.fromAsset(asset: reply),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(context.t.feed_replying_to_photo, style: context.textTheme.labelMedium)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: context.t.cancel,
                    onPressed: onCancelReply,
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                tooltip: context.t.add_photos,
                onPressed: onAddPhotos,
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: context.t.say_something,
                    filled: true,
                    fillColor: context.colorScheme.surfaceContainerHigh,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                icon: isSending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                tooltip: context.t.send_message,
                onPressed: canSend ? onSend : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
