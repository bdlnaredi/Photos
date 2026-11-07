import { authenticate } from '$lib/utils/auth';
import { loadFeedChats } from '$lib/utils/feed';
import { getFormatter } from '$lib/utils/i18n';
import type { PageLoad } from './$types';

export const load = (async ({ url }) => {
  await authenticate(url);
  const chats = await loadFeedChats();
  const $t = await getFormatter();

  return {
    chats,
    meta: {
      title: $t('feed'),
    },
  };
}) satisfies PageLoad;
