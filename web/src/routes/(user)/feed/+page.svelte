<script lang="ts">
  import empty2Url from '$lib/assets/empty-2.svg';
  import UserPageLayout from '$lib/components/layouts/UserPageLayout.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/EmptyPlaceholder.svelte';
  import UserAvatar from '$lib/components/shared-components/UserAvatar.svelte';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { Route } from '$lib/route';
  import { getAlbumsActions } from '$lib/services/album.service';
  import { locale } from '$lib/stores/preferences.store';
  import { getAssetMediaUrl } from '$lib/utils';
  import { formatChatTime } from '$lib/utils/feed';
  import { AssetMediaSize } from '@immich/sdk';
  import { Icon } from '@immich/ui';
  import { mdiImageMultiple } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  type Props = {
    data: PageData;
  };

  let { data }: Props = $props();

  const { Create: CreateAlbum } = $derived(getAlbumsActions($t));

  const previewFor = (chat: PageData['chats'][number]) => {
    if (chat.lastActivity?.comment) {
      const author = chat.lastActivity.user.id === authManager.user.id ? $t('you') : chat.lastActivity.user.name;
      return `${author}: ${chat.lastActivity.comment}`;
    }
    return $t('feed_photos_count', { values: { count: chat.album.assetCount } });
  };

  const membersFor = (chat: PageData['chats'][number]) =>
    chat.album.albumUsers
      .map(({ user }) => (user.id === authManager.user.id ? $t('you') : user.name))
      .join(', ');
</script>

<UserPageLayout title={data.meta.title} actions={[CreateAlbum]}>
  {#if data.chats.length === 0}
    <EmptyPlaceholder text={$t('feed_empty_description')} src={empty2Url} />
  {:else}
    <ul class="mx-auto flex w-full max-w-3xl flex-col">
      {#each data.chats as chat (chat.album.id)}
        <li>
          <a
            href={Route.viewFeed({ id: chat.album.id })}
            class="flex items-center gap-4 rounded-2xl px-3 py-3 transition-colors hover:bg-light-100"
          >
            <div class="relative size-14 shrink-0 overflow-hidden rounded-full bg-light-200">
              {#if chat.album.albumThumbnailAssetId}
                <img
                  src={getAssetMediaUrl({ id: chat.album.albumThumbnailAssetId, size: AssetMediaSize.Thumbnail })}
                  alt={chat.album.albumName}
                  class="size-full object-cover"
                  loading="lazy"
                />
              {:else}
                <div class="flex size-full items-center justify-center text-primary">
                  <Icon icon={mdiImageMultiple} size="28" />
                </div>
              {/if}
            </div>

            <div class="min-w-0 flex-1 border-b border-light-200 pb-3">
              <div class="flex items-baseline justify-between gap-2">
                <p class="truncate font-medium text-dark">{chat.album.albumName}</p>
                <p class="shrink-0 text-xs text-light-600">
                  {formatChatTime(chat.lastAt, $locale, { yesterday: $t('feed_yesterday') })}
                </p>
              </div>
              <p class="truncate text-sm text-light-600">{previewFor(chat)}</p>
              <div class="mt-1 flex items-center gap-1">
                <div class="flex -space-x-2">
                  {#each chat.album.albumUsers.slice(0, 4) as { user } (user.id)}
                    <div class="rounded-full ring-2 ring-light">
                      <UserAvatar {user} size="sm" noTitle />
                    </div>
                  {/each}
                </div>
                <p class="ms-1 truncate text-xs text-light-500">{membersFor(chat)}</p>
              </div>
            </div>
          </a>
        </li>
      {/each}
    </ul>
  {/if}
</UserPageLayout>
