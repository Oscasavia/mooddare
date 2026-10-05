import {$, text, number} from './dom.js';

const count = value => Number.isSafeInteger(value) && value >= 0;
const validLabel = value => typeof value === 'string' && value.trim().length > 0 && value.length <= 300;
const validDate = value => typeof value === 'string' && Number.isFinite(Date.parse(value));
export function validateSnapshot(data, rangeDays) {
  if (data?.status === 'not-connected') return data;
  const metrics = data?.metrics;
  if (data?.status !== 'ready' || ![1, 2].includes(data.schemaVersion) || data.rangeDays !== rangeDays ||
      ![7, 30].includes(rangeDays) || !validDate(data.generatedAt) ||
      !validDate(data.startDate) || !validDate(data.endDate) ||
      Date.parse(data.endDate) - Date.parse(data.startDate) !== rangeDays * 86400000 ||
      !metrics || !['moodSelections', 'communityParticipants', 'communityMoments'].every(k => count(metrics[k])) ||
      !Array.isArray(data.moods) || !Array.isArray(data.communityDares) || data.moods.length > 500 || data.communityDares.length > 500 ||
      !data.moods.every(r => validLabel(r.id) && validLabel(r.name) && count(r.selections)) ||
      !data.communityDares.every(r => validLabel(r.id) && validLabel(r.title) && count(r.participants) && count(r.moments)) ||
      new Set(data.moods.map(r => r.id)).size !== data.moods.length ||
      new Set(data.communityDares.map(r => r.id)).size !== data.communityDares.length) {
    throw Error('Analytics data could not be read. Please try refreshing.');
  }
  if (data.moods.reduce((sum, r) => sum + r.selections, 0) !== metrics.moodSelections ||
      data.communityDares.reduce((sum, r) => sum + r.moments, 0) !== metrics.communityMoments ||
      data.communityDares.some(r => r.participants > r.moments || r.participants > metrics.communityParticipants) ||
      metrics.communityParticipants > data.communityDares.reduce((sum, r) => sum + r.participants, 0)) {
    throw Error('Analytics totals are inconsistent. Please try refreshing.');
  }
  if (data.schemaVersion === 2 && (!validDate(data.trackingStartedAt) ||
      Date.parse(data.trackingStartedAt) > Date.parse(data.generatedAt) ||
      !['signups','accountDeletions','currentProfiles','posts','creators','likes'].every(k=>count(metrics[k])) || metrics.creators > metrics.posts)) {
    throw Error('Analytics coverage or totals are invalid.');
  }
  return data;
}

function empty(target, symbol, title, description) {
  const box = text('div', '', 'empty');
  const icon = text('span', symbol, 'empty-symbol');
  icon.setAttribute('aria-hidden', 'true');
  box.append(icon, text('h2', title), text('p', description));
  $(target).replaceChildren(box);
}

export function renderAnalytics(data, {loading = false, error = false} = {}) {
  const ready = data?.status === 'ready';
  const badge = $('analytics-state');
  badge.textContent = loading ? 'Loading insights' : error ? 'Unavailable' : ready ? 'Connected' : 'Not connected';
  badge.className = ready ? 'badge resolved' : 'badge';
  $('analytics-updated').textContent = loading ? 'Fetching community activity…' : error ? 'Refresh to try again.' : ready
    ? `${new Date(data.startDate).toLocaleDateString(undefined, {month:'short', day:'numeric', timeZone:'UTC'})} – ${new Date(Date.parse(data.endDate)-1).toLocaleDateString(undefined, {month:'short', day:'numeric', year:'numeric', timeZone:'UTC'})} · Updated ${new Date(data.generatedAt).toLocaleTimeString(undefined, {hour:'2-digit', minute:'2-digit', timeZone:'UTC'})} UTC`
    : 'Activity tracking has not been enabled.';
  for (const [id, key] of [['selections', 'moodSelections'], ['participants', 'communityParticipants'], ['moments', 'communityMoments']]) {
    $('analytics-' + id).textContent = ready ? number(data.metrics[key]) : '—';
  }
  for (const key of ['signups','accountDeletions','currentProfiles','posts','creators','likes']) {
    $('analytics-' + key).textContent = ready && data.schemaVersion === 2 ? number(data.metrics[key]) : '—';
  }
  $('analytics-coverage').hidden = !ready || data.schemaVersion !== 2;
  $('analytics-coverage').textContent = ready && data.schemaVersion === 2
    ? `Mood selections, signups and account deletions are measured from ${new Date(data.trackingStartedAt).toLocaleString(undefined,{timeZone:'UTC'})} UTC. Earlier activity is not available. Mood counts require the updated app and a successful connection. Signups count newly created profiles; deletions count removed registered sign-in accounts, including admin removals. Current profiles is today's total. Post, creator, like and community totals use posts created in the selected period that still exist; deleted or moderated-away posts are excluded. Likes are the current likes on those posts, not new likes during the period. Staff and test accounts are included.` : '';
  $('analytics-notice').hidden = ready || loading || error;
  $('mood-sort').disabled = !ready || !data.moods.length;
  if (!ready) {
    const title = loading ? 'Gathering insights…' : error ? 'Insights are unavailable' : 'Your community, in focus';
    empty('mood-results', '◒', title, loading ? 'This will only take a moment.' : error ? 'Use Refresh to try again.' : 'Mood selection counts will appear here once tracking is connected.');
    empty('community-results', '↗', loading ? 'Gathering participation…' : error ? 'Participation is unavailable' : 'Make participation visible', loading ? 'Loading community-dare activity.' : error ? 'Use Refresh to try again.' : 'See how many people turn each community dare into a moment.');
    return;
  }
  if (!data.moods.length) empty('mood-results', '◒', 'No mood data in this period', 'Try another date range.');
  else {
    const sorted = [...data.moods].sort((a,b) => ($('mood-sort').value === 'least' ? a.selections-b.selections : b.selections-a.selections) || a.name.localeCompare(b.name));
    const max = Math.max(1, ...sorted.map(r => r.selections));
    const list = text('ol', '', 'mood-list');
    for (const row of sorted) {
      const item = text('li', ''), heading = text('div', '', 'mood-row-head');
      heading.append(text('span', row.name), text('strong', number(row.selections)));
      const bar = document.createElement('progress');
      bar.className = 'mood-meter'; bar.max = max; bar.value = row.selections;
      bar.setAttribute('aria-label', `${row.name}: ${number(row.selections)} selections`);
      item.append(heading, bar); list.append(item);
    }
    $('mood-results').replaceChildren(list);
  }
  if (!data.communityDares.length) empty('community-results', '↗', 'No community dares in this period', 'Participation will appear when community dares are available.');
  else {
    const wrap = text('div', '', 'table-wrap'), table = text('table', '');
    table.append(text('caption', 'People and published moments by community dare'));
    const head = text('thead', ''), headers = text('tr', '');
    for (const title of ['Dare', 'People', 'Moments']) { const th = text('th', title); th.scope = 'col'; headers.append(th); }
    head.append(headers); table.append(head);
    const body = text('tbody', '');
    for (const row of data.communityDares) {
      const tr = text('tr', ''); tr.append(text('td', row.title), text('td', number(row.participants)), text('td', number(row.moments))); body.append(tr);
    }
    table.append(body); wrap.append(table); $('community-results').replaceChildren(wrap);
  }
}
