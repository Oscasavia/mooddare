import {initializeApp} from 'firebase/app';
import {getAuth, GoogleAuthProvider, signInWithPopup, signOut, setPersistence, browserSessionPersistence, onAuthStateChanged} from 'firebase/auth';
import {config} from './firebase-config.js';
import {$, text, number} from './dom.js';
import {loadAnalytics} from './analytics-source.js';
import {renderAnalytics, validateSnapshot} from './analytics-view.js';

const auth = getAuth(initializeApp(config));
await setPersistence(auth, browserSessionPersistence);
let rows = [], cursor = null, mode = 'reports', selected = null, blob = null;
let sessionGeneration = 0, viewGeneration = 0, detailGeneration = 0;
let loading = false, acting = false, authorized = false, snapshot = null;
const date = v => v ? new Date((v._seconds ?? v.seconds) * 1000).toLocaleString() : 'Date unavailable';
const labels = {remove:'Remove content', restore:'Restore content', dismiss:'Dismiss report', suspend:'Suspend for 7 days', ban:'Ban account', reinstate:'Lift restriction'};
function status(message) { $('status').textContent = message; $('status').hidden = !message; }
async function api(route, body) {
  const user = auth.currentUser;
  const token = await user?.getIdToken();
  if (!token || user !== auth.currentUser) throw Error('Please sign in.');
  const response = await fetch(`/admin-api/${route}`, {
    method: body ? 'POST' : 'GET',
    headers: {Authorization:`Bearer ${token}`, ...(body ? {'Content-Type':'application/json'} : {})},
    ...(body ? {body:JSON.stringify(body)} : {}),
  });
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw Error(error.error || 'Unable to complete the request. Please try again.');
  }
  return route.startsWith('media?') ? response.blob() : response.json();
}
function controls() {
  $('refresh').disabled = loading || acting;
  $('more').disabled = loading || acting;
  $('analytics-range').disabled = acting;
  for (const tab of ['reports', 'history', 'analytics']) $(tab).disabled = acting;
}
function clearMedia() { if (blob) URL.revokeObjectURL(blob); blob = null; }
function emptyDetail() {
  clearMedia(); ++detailGeneration; selected = null;
  $('review-layout').classList.remove('is-reviewing'); $('moderation-view').classList.remove('reviewing');
  const box = text('div', '', 'empty');
  const icon = document.createElement('img'); icon.src = '/assets/mood-wink.svg'; icon.width = 64; icon.height = 64; icon.alt = '';
  box.append(icon, text('h2', 'A little context goes a long way.'), text('p', 'Choose a report to review the moment, understand the concern, and decide what happens next.'));
  $('detail').replaceChildren(box);
}
function backButton() {
  const button = text('button', '← Back to results', 'back-to-queue secondary');
  button.onclick = () => {
    const id = selected; emptyDetail(); render();
    [...$('queue').querySelectorAll('.card')].find(card => card.dataset.reportId === id)?.focus();
  };
  return button;
}
$('signin').onclick = async () => {
  $('signin').disabled = true; status('');
  try { await signInWithPopup(auth, new GoogleAuthProvider()); }
  catch { status('Sign-in did not finish. Please try again.'); }
  finally { $('signin').disabled = false; }
};
$('signout').onclick = async () => { try { await signOut(auth); } catch { status('Could not sign out. Please try again.'); } };
onAuthStateChanged(auth, async user => {
  const current = ++sessionGeneration; ++viewGeneration;
  authorized = false; loading = false; acting = false; rows = []; cursor = null; snapshot = null;
  if ($('confirm').open) $('confirm').close('cancel');
  emptyDetail(); $('queue').replaceChildren(); renderAnalytics(null);
  $('workspace').hidden = true; $('navigation').hidden = true; $('login').hidden = false; $('signout').hidden = !user;
  $('nav-count').hidden = true; status(''); controls();
  if (!user) return;
  try {
    await api('session'); if (current !== sessionGeneration) return;
    authorized = true; $('workspace').hidden = false; $('navigation').hidden = false; $('login').hidden = true;
    changeMode('reports');
  } catch (e) { if (current === sessionGeneration) status(e.message); }
});
function summary() {
  const history = mode === 'history';
  const pending = history ? rows.filter(r => ['pending', 'processing', 'retry'].includes(r.status)).length : rows.filter(r => r.review?.status !== 'resolved').length;
  const done = history ? rows.filter(r => r.status === 'done').length : rows.filter(r => r.review?.status === 'resolved').length;
  const values = [pending, done, rows.length];
  const titles = history ? ['Incomplete actions', 'Completed', 'Actions loaded'] : ['Needs review', 'Resolved', 'Reports loaded'];
  const notes = history ? ['Check progress or retry', 'Decisions applied', 'A record of your community care'] : ['Waiting for a decision', 'Reviewed by your team', 'Every concern deserves attention'];
  for (let i = 1; i <= 3; i++) {
    $('metric-value-' + i).textContent = number(values[i - 1]);
    $('metric-label-' + i).textContent = titles[i - 1];
    $('metric-note-' + i).textContent = notes[i - 1];
  }
  $('scope-note').textContent = history ? 'Loaded actions only' : 'Loaded reports only';
  if (!history) { $('nav-count').textContent = number(pending); $('nav-count').hidden = pending === 0; }
}
async function load(more = false, {quiet = false} = {}) {
  if (!authorized || loading || acting) return;
  const current = ++viewGeneration, session = sessionGeneration, tab = mode;
  loading = true; controls(); if (!quiet) status(tab === 'analytics' ? 'Loading insights…' : 'Loading results…');
  if (tab === 'analytics') { snapshot = null; renderAnalytics(null, {loading:true}); }
  try {
    if (tab === 'analytics') {
      const rangeDays = Number($('analytics-range').value);
      const result = await loadAnalytics({rangeDays, api});
      if (current !== viewGeneration || session !== sessionGeneration) return;
      snapshot = validateSnapshot(result, rangeDays); renderAnalytics(snapshot);
    } else {
      const data = await api(`${tab}${more && cursor ? '?cursor=' + encodeURIComponent(cursor) : ''}`);
      if (current !== viewGeneration || session !== sessionGeneration) return;
      rows = [...new Map((more ? [...rows, ...data.items] : data.items).map(r => [r.id, r])).values()];
      cursor = data.cursor; render();
    }
    if (!quiet) status('');
  } catch (e) {
    if (current === viewGeneration && session === sessionGeneration) {
      status(e.message);
      if (tab === 'analytics') renderAnalytics(null, {error:true});
    }
  } finally { if (current === viewGeneration && session === sessionGeneration) { loading = false; controls(); } }
}
function render() {
  const q = $('search').value.trim().toLowerCase(), filter = $('filter').value;
  const list = rows.filter(r => JSON.stringify(r).toLowerCase().includes(q) && (mode === 'history' || filter === 'all' || (r.review?.status || 'pending') === filter));
  $('queue').replaceChildren(); summary(); $('result-count').textContent = `${number(list.length)} shown`;
  for (const row of list) {
    const reportId = row.reportId || row.id;
    const card = text('button', '', 'card'); card.dataset.reportId = reportId;
    card.setAttribute('aria-pressed', String(selected === reportId));
    const heading = text('div', '', 'card-head');
    const state = mode === 'history' ? row.status : row.review?.status || 'pending';
    const kind = mode === 'history' ? labels[row.action] || row.action : row.commentId ? (row.isReply ? 'Reply report' : 'Comment report') : row.userId ? 'Account report' : 'Moment report';
    const badge = text('span', state === 'pending' && mode === 'reports' ? 'Needs review' : state === 'resolved' ? 'Resolved' : state === 'done' ? 'Completed' : state, 'badge');
    if (['pending','resolved','done','retry'].includes(state)) badge.classList.add(state);
    heading.append(text('span', kind, 'card-title'), badge);
    const meta = text('div', '', 'card-meta');
    meta.append(text('span', date(row.createdAt)), text('span', mode === 'history' ? `Staff · ${row.staff || 'Unknown'}` : `ID · ${row.userId || row.postId || row.id}`));
    card.append(heading, text('span', row.reason || 'No reason provided', 'card-reason'), meta);
    card.onclick = () => { if (!acting) open(reportId); }; card.disabled = acting;
    $('queue').append(card);
    if (mode === 'history' && ['retry','processing','pending'].includes(row.status)) {
      const retry = text('button', 'Retry incomplete action', 'retry-action secondary');
      retry.disabled = acting; retry.onclick = () => retryAction(row.id); $('queue').append(retry);
    }
  }
  if (!list.length) {
    const box = text('div', '', 'empty queue-empty');
    box.append(text('h3', q || filter !== 'all' ? 'No matching results' : mode === 'history' ? 'No actions yet' : 'No reports to show.'), text('p', q || filter !== 'all' ? 'Try another search or status filter.' : mode === 'history' ? 'Your moderation decisions will appear here.' : 'New concerns will appear in this inbox.'));
    $('queue').append(box);
  }
  $('more').hidden = !cursor;
}
async function retryAction(operationId) {
  if (acting) return;
  const session = sessionGeneration;
  acting = true; controls(); render(); status('Retrying action…');
  try {
    const result = await api('retry', {operationId}); if (session !== sessionGeneration) return;
    status(result.status === 'done' ? 'Decision saved.' : 'Action is processing. Refresh Action history to check progress.');
  } catch (e) { if (session === sessionGeneration) status(e.message); }
  finally { if (session === sessionGeneration) { acting = false; controls(); await load(false, {quiet:true}); } }
}
async function open(reportId, {focus = true} = {}) {
  const current = ++detailGeneration, session = sessionGeneration;
  selected = reportId; clearMedia(); $('review-layout').classList.add('is-reviewing'); $('moderation-view').classList.add('reviewing');
  $('detail').replaceChildren(backButton(), text('p', 'Loading report…', 'muted')); render();
  if (focus && matchMedia('(max-width: 850px)').matches) { $('detail').scrollIntoView({block:'start'}); $('detail').focus({preventScroll:true}); }
  try {
    const data = await api(`detail?id=${encodeURIComponent(reportId)}`);
    if (current !== detailGeneration || session !== sessionGeneration) return;
    const area = $('detail'), top = text('div', '', 'detail-top');
    top.append(text('p', 'REPORT DETAILS', 'detail-kicker'), text('span', data.removed ? 'Content removed' : data.review.status === 'resolved' ? 'Reviewed' : 'Needs review', 'badge'));
    area.replaceChildren(backButton(), top, text('h2', data.author?.username ? `@${data.author.username}` : 'Reported content'), text('p', `Reported for: ${data.report.reason || 'No reason provided'}`, 'report-reason'));
    if (data.content) {
      area.append(text('h3', 'Content in context'), text('p', data.content.text || data.content.dareText || data.content.bio || 'Account report', 'content'));
      if (data.path.startsWith('posts/') && data.path.split('/').length === 2) {
        const button = text('button', 'Load reported media', 'media-load');
        button.onclick = async () => {
          button.disabled = true; button.textContent = 'Loading media…';
          try {
            const file = await api(`media?id=${encodeURIComponent(reportId)}`);
            if (current !== detailGeneration || session !== sessionGeneration) return;
            clearMedia(); blob = URL.createObjectURL(file);
            const el = document.createElement(data.content.mediaType === 'video' ? 'video' : 'img');
            el.className = 'media'; el.src = blob;
            if (el.tagName === 'VIDEO') { el.controls = true; el.preload = 'metadata'; } else el.alt = 'Reported moment';
            button.replaceWith(el);
          } catch (e) { if (current === detailGeneration && session === sessionGeneration) { status(e.message); button.disabled = false; button.textContent = 'Retry loading media'; } }
        }; area.append(button);
      }
    } else area.append(text('p', 'This content is no longer available.', 'muted'));
    const info = text('dl', '', 'detail-info');
    for (const [key,value] of [['Report ID',reportId], ['Reported',date(data.report.createdAt)], ['Account',data.restriction.status && data.restriction.status !== 'active' ? `${data.restriction.status}${data.restriction.until ? ' until ' + date(data.restriction.until) : ''}` : 'No active restriction'], ...(data.review.reason ? [['Last decision',data.review.reason]] : [])]) {
      info.append(text('dt',key), text('dd',value));
    }
    area.append(info);
    const decision = text('div', '', 'detail-actions'); decision.append(text('h3', 'Make a decision'), text('p', 'Every action includes a reason and is saved to history.', 'muted'));
    const actions = text('div', '', 'actions');
    const add = (target, action) => { const b = text('button', labels[action], ['remove','ban'].includes(action) ? 'danger' : 'secondary'); b.onclick = () => confirmAction(action, reportId); b.disabled = acting; target.append(b); };
    if (!data.path.startsWith('users/') && data.content) add(actions, data.removed ? 'restore' : 'remove');
    add(actions,'dismiss'); decision.append(actions);
    if (data.author) {
      const account = text('details', '', 'account-actions');
      account.append(text('summary','Account restrictions'), text('p','Restrict access to MoodDare. Existing posts must be reviewed separately.'));
      const accountActions = text('div', '', 'actions');
      for (const action of ['suspend','ban','reinstate']) add(accountActions,action);
      account.append(accountActions); decision.append(account);
    }
    area.append(decision);
    if (focus && matchMedia('(max-width: 850px)').matches) $('detail').scrollIntoView({block:'start'});
  } catch (e) {
    if (current === detailGeneration && session === sessionGeneration) {
      const retry = text('button', 'Try again', 'secondary'); retry.onclick = () => open(reportId);
      $('detail').replaceChildren(backButton(), text('h2','Could not load this report'),text('p', e.message, 'muted'),retry); status(e.message);
    }
  }
}
function confirmAction(action, reportId) {
  if (acting || !authorized) return;
  const session = sessionGeneration;
  $('confirm-title').textContent = labels[action]; $('reason').value = '';
  $('confirm-description').textContent = action === 'remove' ? 'Content will become unavailable in MoodDare. It can be restored after review.' : action === 'ban' ? 'This prevents this account from using MoodDare until you lift the restriction. Existing content is reviewed separately.' : action === 'suspend' ? 'This account will be restricted for seven days. The reason will be visible to its owner.' : 'Your decision and reason will be saved in the action history.';
  const dialog = $('confirm'); dialog.returnValue = ''; dialog.showModal();
  dialog.onclose = async () => {
    if (dialog.returnValue !== 'confirm' || session !== sessionGeneration || acting) return;
    const reason = $('reason').value.trim();
    if (reason.length < 5) { status('Please provide a reason of at least five characters.'); return; }
    const operationId = crypto.randomUUID(); acting = true; controls(); render();
    $('detail').querySelectorAll('button').forEach(b => b.disabled = true); status('Applying action…');
    try {
      const result = await api('action', {operationId, reportId, action, reason});
      if (session !== sessionGeneration) return;
      status(result.status === 'done' ? 'Decision saved.' : 'Action is processing. Check Action history.');
    } catch (e) { if (session === sessionGeneration) status(e.message); }
    finally {
      if (session === sessionGeneration) { acting = false; controls(); await open(reportId,{focus:false}); await load(false,{quiet:true}); }
    }
  };
}
function changeMode(tab) {
  if (!authorized || acting) return;
  ++viewGeneration; loading = false; mode = tab; cursor = null; rows = []; snapshot = null; status(''); emptyDetail();
  for (const name of ['reports','history','analytics']) $(name).setAttribute('aria-pressed', String(name === tab));
  const analytics = tab === 'analytics', history = tab === 'history';
  $('moderation-view').hidden = analytics; $('analytics-view').hidden = !analytics;
  $('page-title').textContent = analytics ? 'Community insights' : history ? 'A record of care.' : 'Community care';
  $('page-description').textContent = analytics ? 'Understand what brings your community together.' : history ? 'Clear decisions. A thoughtful trail to follow.' : 'A thoughtful decision starts with a little context.';
  $('queue-title').textContent = history ? 'Action history' : 'Report inbox';
  $('summary-title').textContent = history ? 'Decisions at a glance' : 'Queue at a glance';
  $('filter').disabled = history; $('filter-label').hidden = history;
  $('search').value = ''; $('filter').value = 'all';
  if (!analytics) render(); controls(); load();
}
$('refresh').onclick = async () => { await load(); if (selected && mode !== 'analytics') await open(selected,{focus:false}); };
$('more').onclick = () => load(true);
$('search').oninput = render; $('filter').onchange = render;
$('analytics-range').onchange = () => { ++viewGeneration; loading = false; load(); };
$('mood-sort').onchange = () => renderAnalytics(snapshot);
for (const tab of ['reports','history','analytics']) $(tab).onclick = () => changeMode(tab);
