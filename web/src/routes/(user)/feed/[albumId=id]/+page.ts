import { getAlbumInfo } from '@immich/sdk';
import { authenticate } from '$lib/utils/auth';
import { buildFeed, loadAlbumActivities, loadAlbumAssets } from '$lib/utils/feed';
import type { PageLoad } from './$types';

export const load = (async ({ params, url }) => {
  await authenticate(url);

  const [album, assets, activities] = await Promise.all([
    getAlbumInfo({ id: params.albumId }),
    loadAlbumAssets(params.albumId),
    loadAlbumActivities(params.albumId),
  ]);

  return {
    album,
    assets,
    activities,
    items: buildFeed(
      assets,
      activities,
      album.albumUsers.map(({ user }) => user),
    ),
    meta: {
      title: album.albumName,
    },
  };
}) satisfies PageLoad;
