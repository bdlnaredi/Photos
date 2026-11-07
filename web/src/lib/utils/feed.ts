import {
  getActivities,
  getAllAlbums,
  ReactionType,
  searchAssets,
  type ActivityResponseDto,
  type AlbumResponseDto,
  type AssetResponseDto,
  type UserResponseDto,
} from '@immich/sdk';

const PHOTO_GROUP_WINDOW_MS = 10 * 60 * 1000;
const MAX_FEED_ASSETS = 5000;
const SEARCH_PAGE_SIZE = 1000;

export type FeedPhotoGroup = {
  kind: 'photos';
  id: string;
  ownerId: string;
  owner?: UserResponseDto;
  createdAt: string;
  assets: AssetResponseDto[];
  likes: ActivityResponseDto[];
  replyCount: number;
};

export type FeedComment = {
  kind: 'comment';
  id: string;
  activity: ActivityResponseDto;
  createdAt: string;
  replyTo?: AssetResponseDto;
};

export type FeedDay = {
  kind: 'day';
  id: string;
  createdAt: string;
};

export type FeedItem = FeedPhotoGroup | FeedComment | FeedDay;

export type FeedChat = {
  album: AlbumResponseDto;
  lastActivity?: ActivityResponseDto;
  lastAt: string;
};

const time = (value: string) => new Date(value).getTime();

const dayKey = (value: string) => {
  const date = new Date(value);
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
};

export const loadAlbumAssets = async (albumId: string) => {
  const assets: AssetResponseDto[] = [];
  let page: number | null = 1;
  while (page && assets.length < MAX_FEED_ASSETS) {
    const response = await searchAssets({
      metadataSearchDto: { albumIds: [albumId], page, size: SEARCH_PAGE_SIZE, withDeleted: false },
    });
    assets.push(...response.assets.items);
    page = response.assets.nextPage ? Number(response.assets.nextPage) : null;
  }
  return assets;
};

export const loadAlbumActivities = (albumId: string) => getActivities({ albumId });

export const buildFeed = (
  assets: AssetResponseDto[],
  activities: ActivityResponseDto[],
  users: UserResponseDto[],
): FeedItem[] => {
  const usersById = new Map(users.map((user) => [user.id, user]));
  const assetsById = new Map(assets.map((asset) => [asset.id, asset]));

  const sortedAssets = [...assets].sort((a, b) => time(a.createdAt) - time(b.createdAt));
  const groups: FeedPhotoGroup[] = [];
  const groupByAssetId = new Map<string, FeedPhotoGroup>();

  for (const asset of sortedAssets) {
    const last = groups.at(-1);
    const lastAsset = last?.assets.at(-1);
    const sameBatch =
      last &&
      lastAsset &&
      last.ownerId === asset.ownerId &&
      time(asset.createdAt) - time(lastAsset.createdAt) <= PHOTO_GROUP_WINDOW_MS;

    const group: FeedPhotoGroup = sameBatch
      ? last
      : {
          kind: 'photos',
          id: `photos-${asset.id}`,
          ownerId: asset.ownerId,
          owner: asset.owner ?? usersById.get(asset.ownerId),
          createdAt: asset.createdAt,
          assets: [],
          likes: [],
          replyCount: 0,
        };

    if (!sameBatch) {
      groups.push(group);
    }
    group.assets.push(asset);
    groupByAssetId.set(asset.id, group);
  }

  const comments: FeedComment[] = [];
  for (const activity of activities) {
    const group = activity.assetId ? groupByAssetId.get(activity.assetId) : undefined;
    if (activity.type === ReactionType.Like) {
      group?.likes.push(activity);
      continue;
    }
    if (group) {
      group.replyCount++;
    }
    comments.push({
      kind: 'comment',
      id: `comment-${activity.id}`,
      activity,
      createdAt: activity.createdAt,
      replyTo: activity.assetId ? assetsById.get(activity.assetId) : undefined,
    });
  }

  const merged = [...groups, ...comments].sort((a, b) => time(a.createdAt) - time(b.createdAt));

  const items: FeedItem[] = [];
  let previousDay: string | undefined;
  for (const item of merged) {
    const key = dayKey(item.createdAt);
    if (key !== previousDay) {
      items.push({ kind: 'day', id: `day-${key}`, createdAt: item.createdAt });
      previousDay = key;
    }
    items.push(item);
  }

  return items;
};

export const loadFeedChats = async (): Promise<FeedChat[]> => {
  const albums = await getAllAlbums({ isShared: true });
  const chats = await Promise.all(
    albums.map(async (album) => {
      const activities = album.isActivityEnabled ? await getActivities({ albumId: album.id }).catch(() => []) : [];
      const lastActivity = activities.findLast((activity) => activity.type === ReactionType.Comment);
      const candidates = [album.lastModifiedAssetTimestamp, lastActivity?.createdAt, album.updatedAt].filter(
        (value): value is string => !!value,
      );
      let lastAt = album.updatedAt;
      for (const value of candidates) {
        if (time(value) > time(lastAt)) {
          lastAt = value;
        }
      }
      return { album, lastActivity, lastAt };
    }),
  );
  return chats.sort((a, b) => time(b.lastAt) - time(a.lastAt));
};

export const isSameDay = (a: Date, b: Date) =>
  a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();

export const formatFeedDay = (value: string, locale: string, labels: { today: string; yesterday: string }) => {
  const date = new Date(value);
  const now = new Date();
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (isSameDay(date, now)) {
    return labels.today;
  }
  if (isSameDay(date, yesterday)) {
    return labels.yesterday;
  }
  return date.toLocaleDateString(locale, {
    day: 'numeric',
    month: 'long',
    year: date.getFullYear() === now.getFullYear() ? undefined : 'numeric',
  });
};

export const formatFeedTime = (value: string, locale: string) =>
  new Date(value).toLocaleTimeString(locale, { hour: 'numeric', minute: '2-digit' });

export const formatChatTime = (value: string, locale: string, labels: { yesterday: string }) => {
  const date = new Date(value);
  const now = new Date();
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (isSameDay(date, now)) {
    return formatFeedTime(value, locale);
  }
  if (isSameDay(date, yesterday)) {
    return labels.yesterday;
  }
  return date.toLocaleDateString(locale, { day: 'numeric', month: 'short' });
};
