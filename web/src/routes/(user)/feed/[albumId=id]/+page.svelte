<script lang="ts">
  import { shortcut } from '$lib/actions/shortcut';
  import UserPageLayout from '$lib/components/layouts/UserPageLayout.svelte';
  import UserAvatar from '$lib/components/shared-components/UserAvatar.svelte';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { Route } from '$lib/route';
  import { locale } from '$lib/stores/preferences.store';
  import { getAssetMediaUrl } from '$lib/utils';
  import {
    buildFeed,
    formatFeedDay,
    formatFeedTime,
    loadAlbumActivities,
    loadAlbumAssets,
    type FeedComment,
    type FeedPhotoGroup,
  } from '$lib/utils/feed';
  import { openFileUploadDialog } from '$lib/utils/file-uploader';
  import { handleError } from '$lib/utils/handle-error';
  import {
    AssetMediaSize,
    AssetTypeEnum,
    createActivity,
    deleteActivity,
    ReactionType,
    type AssetResponseDto,
  } from '@immich/sdk';
  import { Button, Icon, IconButton, Textarea } from '@immich/ui';
  import {
    mdiArrowLeft,
    mdiClose,
    mdiHeart,
    mdiHeartOutline,
    mdiImagePlusOutline,
    mdiPlay,
    mdiReply,
    mdiSend,
    mdiTrashCanOutline,
  } from '@mdi/js';
  import { onDestroy, onMount, tick } from 'svelte';
  import { t } from 'svelte-i18n';
  import { fromAction } from 'svelte/attachments';
  import type { PageData } from './$types';

  type Props = {
    data: PageData;
  };

  let { data }: Props = $props();

  const REFRESH_INTERVAL_MS = 15_000;
  const MAX_TILES = 4;

  const album = $derived(data.album);
  let items = $derived(data.items);
  let message = $state('');
  let replyTo = $state<AssetResponseDto | undefined>();
  let isSending = $state(false);
  let isUploading = $state(false);
  let scroller = $state<HTMLDivElement>();
  let refreshTimer: ReturnType<typeof setInterval> | undefined;

  const me = $derived(authManager.user.id);
  const isOwner = $derived(album.albumUsers[0]?.user.id === me);
  const users = $derived(album.albumUsers.map(({ user }) => user));
  const usersById = $derived(new Map(users.map((user) => [user.id, user])));
  const nameColors = ['text-sky-700', 'text-emerald-700', 'text-rose-700', 'text-amber-700', 'text-violet-700'];
  const nameColorFor = (userId: string) => {
    const index = Math.max(
      0,
      users.findIndex((user) => user.id === userId),
    );
    return nameColors[index % nameColors.length];
  };

  const isNearBottom = () => {
    if (!scroller) {
      return true;
    }
    return scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 200;
  };

  const scrollToBottom = async () => {
    await tick();
    scroller?.scrollTo({ top: scroller.scrollHeight });
  };

  const refresh = async (forceScroll = false) => {
    const stickToBottom = forceScroll || isNearBottom();
    try {
      const [assets, activities] = await Promise.all([loadAlbumAssets(album.id), loadAlbumActivities(album.id)]);
      items = buildFeed(assets, activities, users);
      if (stickToBottom) {
        await scrollToBottom();
      }
    } catch (error) {
      handleError(error, $t('errors.feed_unable_to_load'));
    }
  };

  const sendMessage = async () => {
    const comment = message.trim();
    if (!comment || isSending) {
      return;
    }
    isSending = true;
    try {
      await createActivity({
        activityCreateDto: { albumId: album.id, assetId: replyTo?.id, type: ReactionType.Comment, comment },
      });
      message = '';
      replyTo = undefined;
      await refresh(true);
    } catch (error) {
      handleError(error, $t('errors.unable_to_add_comment'));
    } finally {
      isSending = false;
    }
  };

  const addPhotos = async () => {
    isUploading = true;
    try {
      const ids = await openFileUploadDialog({ albumId: album.id });
      if (ids.length > 0) {
        await refresh(true);
      }
    } finally {
      isUploading = false;
    }
  };

  const myLike = (group: FeedPhotoGroup) => group.likes.find((like) => like.user.id === me);

  const toggleLike = async (group: FeedPhotoGroup) => {
    const existing = myLike(group);
    try {
      await (existing
        ? deleteActivity({ id: existing.id })
        : createActivity({
            activityCreateDto: { albumId: album.id, assetId: group.assets[0].id, type: ReactionType.Like },
          }));
      await refresh();
    } catch (error) {
      handleError(error, $t('errors.feed_unable_to_update'));
    }
  };

  const removeComment = async (item: FeedComment) => {
    try {
      await deleteActivity({ id: item.activity.id });
      await refresh();
    } catch (error) {
      handleError(error, $t('errors.feed_unable_to_update'));
    }
  };

  const startReply = (asset: AssetResponseDto) => {
    replyTo = asset;
    document.querySelector<HTMLTextAreaElement>('#feed-composer textarea')?.focus();
  };

  const thumbnail = (asset: AssetResponseDto) =>
    getAssetMediaUrl({ id: asset.id, cacheKey: asset.thumbhash, size: AssetMediaSize.Thumbnail });

  const tileGrid = (count: number) => (count === 1 ? 'grid-cols-1' : 'grid-cols-2');

  const ownerName = (group: FeedPhotoGroup) => group.owner?.name ?? usersById.get(group.ownerId)?.name ?? $t('unknown');

  onMount(() => {
    void scrollToBottom();
    refreshTimer = setInterval(() => void refresh(), REFRESH_INTERVAL_MS);
  });

  onDestroy(() => {
    clearInterval(refreshTimer);
  });
</script>

<UserPageLayout scrollbar={false}>
  <div class="flex h-full flex-col">
    <div class="flex items-center gap-3 border-b border-light-200 px-2 pb-2">
      <IconButton
        shape="round"
        variant="ghost"
        color="secondary"
        icon={mdiArrowLeft}
        aria-label={$t('back')}
        href={Route.feed()}
      />
      <div class="min-w-0 flex-1">
        <p class="truncate font-medium text-dark">{album.albumName}</p>
        <p class="truncate text-xs text-light-600">
          {users.map((user) => (user.id === me ? $t('you') : user.name)).join(', ')}
        </p>
      </div>
      <Button size="small" variant="ghost" href={Route.viewAlbum(album)}>{$t('view_album')}</Button>
    </div>

    <div
      bind:this={scroller}
      class="flex-1 immich-scrollbar overflow-y-auto bg-light-50 px-2 py-4 sm:px-6"
      data-testid="feed-messages"
    >
      {#if items.length === 0}
        <p class="mt-16 text-center text-sm text-light-600">{$t('feed_no_messages')}</p>
      {/if}

      <div class="mx-auto flex max-w-3xl flex-col gap-1">
        {#each items as item (item.id)}
          {#if item.kind === 'day'}
            <div class="my-3 flex justify-center">
              <span class="rounded-full bg-light-200 px-3 py-1 text-xs text-light-700">
                {formatFeedDay(item.createdAt, $locale, {
                  today: $t('feed_today'),
                  yesterday: $t('feed_yesterday'),
                })}
              </span>
            </div>
          {:else if item.kind === 'photos'}
            {@const mine = item.ownerId === me}
            {@const liked = myLike(item)}
            <div class="group flex items-end gap-2 {mine ? 'flex-row-reverse' : ''}">
              {#if !mine && item.owner}
                <UserAvatar user={item.owner} size="sm" noTitle />
              {/if}
              <div
                class="max-w-[85%] rounded-2xl p-1 shadow-sm sm:max-w-sm {mine
                  ? 'rounded-br-sm bg-primary-100'
                  : 'rounded-bl-sm bg-light'}"
              >
                {#if !mine}
                  <p class="px-2 pt-1 text-xs font-medium {nameColorFor(item.ownerId)}">{ownerName(item)}</p>
                {/if}
                <div class="grid gap-1 {tileGrid(item.assets.length)}">
                  {#each item.assets.slice(0, MAX_TILES) as asset, index (asset.id)}
                    <a
                      href={Route.viewAlbumAsset({ albumId: album.id, assetId: asset.id })}
                      class="relative block overflow-hidden rounded-xl bg-light-200 {item.assets.length === 1
                        ? 'aspect-auto'
                        : 'aspect-square'}"
                    >
                      <img
                        src={thumbnail(asset)}
                        alt={asset.originalFileName}
                        loading="lazy"
                        class="size-full object-cover {item.assets.length === 1 ? 'max-h-96' : ''}"
                      />
                      {#if asset.type === AssetTypeEnum.Video}
                        <span class="absolute inset-0 flex items-center justify-center">
                          <span class="rounded-full bg-black/50 p-2 text-white"><Icon icon={mdiPlay} size="24" /></span>
                        </span>
                      {/if}
                      {#if index === MAX_TILES - 1 && item.assets.length > MAX_TILES}
                        <span
                          class="absolute inset-0 flex items-center justify-center bg-black/50 text-2xl font-medium text-white"
                        >
                          +{item.assets.length - MAX_TILES}
                        </span>
                      {/if}
                    </a>
                  {/each}
                </div>
                <div class="flex items-center justify-between gap-2 px-1 pt-1">
                  <div class="flex items-center">
                    <IconButton
                      shape="round"
                      variant="ghost"
                      color={liked ? 'danger' : 'secondary'}
                      size="small"
                      icon={liked ? mdiHeart : mdiHeartOutline}
                      aria-label={$t('like')}
                      disabled={!album.isActivityEnabled}
                      onclick={() => toggleLike(item)}
                    />
                    {#if item.likes.length > 0}
                      <span class="text-xs text-light-600" title={item.likes.map((like) => like.user.name).join(', ')}>
                        {item.likes.length}
                      </span>
                    {/if}
                    {#if album.isActivityEnabled}
                      <IconButton
                        shape="round"
                        variant="ghost"
                        color="secondary"
                        size="small"
                        icon={mdiReply}
                        aria-label={$t('feed_reply')}
                        onclick={() => startReply(item.assets[0])}
                      />
                    {/if}
                  </div>
                  <span class="text-[11px] text-light-600">
                    {$t('feed_photos_count', { values: { count: item.assets.length } })} · {formatFeedTime(
                      item.createdAt,
                      $locale,
                    )}
                  </span>
                </div>
              </div>
            </div>
          {:else}
            {@const author = item.activity.user}
            {@const mine = author.id === me}
            <div class="group flex items-end gap-2 {mine ? 'flex-row-reverse' : ''}">
              {#if !mine}
                <UserAvatar user={author} size="sm" noTitle />
              {/if}
              <div
                class="max-w-[85%] rounded-2xl px-3 py-2 shadow-sm sm:max-w-md {mine
                  ? 'rounded-br-sm bg-primary-100'
                  : 'rounded-bl-sm bg-light'}"
              >
                {#if !mine}
                  <p class="text-xs font-medium {nameColorFor(author.id)}">{author.name}</p>
                {/if}
                {#if item.replyTo}
                  <a
                    href={Route.viewAlbumAsset({ albumId: album.id, assetId: item.replyTo.id })}
                    class="my-1 flex items-center gap-2 rounded-lg border-s-4 border-primary bg-black/5 p-1 dark:bg-white/5"
                  >
                    <img src={thumbnail(item.replyTo)} alt="" class="size-10 rounded-sm object-cover" loading="lazy" />
                    <span class="text-xs text-light-600">{$t('feed_replied_to_photo')}</span>
                  </a>
                {/if}
                <p class="text-sm wrap-break-word whitespace-pre-wrap text-dark">{item.activity.comment}</p>
                <p class="mt-0.5 text-end text-[11px] text-light-600">{formatFeedTime(item.createdAt, $locale)}</p>
              </div>
              {#if mine || isOwner}
                <div class="opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
                  <IconButton
                    shape="round"
                    variant="ghost"
                    color="secondary"
                    size="small"
                    icon={mdiTrashCanOutline}
                    aria-label={$t('delete')}
                    onclick={() => removeComment(item)}
                  />
                </div>
              {/if}
            </div>
          {/if}
        {/each}
      </div>
    </div>

    <div id="feed-composer" class="border-t border-light-200 px-2 pt-2">
      {#if album.isActivityEnabled}
        <div class="mx-auto max-w-3xl">
          {#if replyTo}
            <div class="mb-2 flex items-center gap-2 rounded-xl border-s-4 border-primary bg-light-100 p-2">
              <img src={thumbnail(replyTo)} alt="" class="size-10 rounded-sm object-cover" />
              <p class="flex-1 text-xs text-light-600">{$t('feed_replying_to_photo')}</p>
              <IconButton
                shape="round"
                variant="ghost"
                color="secondary"
                size="small"
                icon={mdiClose}
                aria-label={$t('cancel')}
                onclick={() => (replyTo = undefined)}
              />
            </div>
          {/if}
          <form
            class="flex items-end gap-2"
            onsubmit={(event) => {
              event.preventDefault();
              void sendMessage();
            }}
          >
            <IconButton
              shape="round"
              variant="ghost"
              color="secondary"
              icon={mdiImagePlusOutline}
              aria-label={$t('add_photos')}
              loading={isUploading}
              onclick={() => addPhotos()}
            />
            <div class="flex-1 rounded-3xl bg-light-100 px-3 py-1">
              <Textarea
                bind:value={message}
                rows={1}
                grow
                placeholder={$t('say_something')}
                {@attach fromAction(shortcut, () => ({
                  shortcut: { key: 'Enter' },
                  onShortcut: () => void sendMessage(),
                }))}
                class="max-h-40 w-full resize-none bg-transparent ring-0! outline-none"
              />
            </div>
            <IconButton
              shape="round"
              color="primary"
              icon={mdiSend}
              aria-label={$t('send_message')}
              loading={isSending}
              disabled={!message.trim()}
              type="submit"
            />
          </form>
        </div>
      {:else}
        <p class="py-2 text-center text-sm text-light-600">{$t('comments_are_disabled')}</p>
      {/if}
    </div>
  </div>
</UserPageLayout>
