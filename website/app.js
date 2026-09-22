import { release } from './config.js';

const samples = {
  creative: 'Draw your mood without lifting your pen.',
  chill: 'Find a little patch of nature and photograph it.',
  curious: 'Photograph an interesting shadow.',
  happy: 'Capture something that made you smile today.',
};

for (const button of document.querySelectorAll('[data-mood]')) {
  button.addEventListener('click', () => {
    const mood = button.dataset.mood;
    for (const option of document.querySelectorAll('[data-mood]')) {
      option.setAttribute('aria-pressed', String(option === button));
    }
    document.querySelector('#sample-mood').textContent = `YOUR ${mood.toUpperCase()} DARE`;
    document.querySelector('#sample-text').textContent = samples[mood];
    document.querySelector('.mood-playground').dataset.activeMood = mood;
  });
}

const dialog = document.querySelector('#screen-dialog');
if (dialog) {
  const image = dialog.querySelector('#screen-image');
  const caption = dialog.querySelector('#screen-caption');
  for (const button of document.querySelectorAll('[data-screen]')) {
    button.addEventListener('click', () => {
      const source = button.querySelector('img');
      image.src = source.src;
      image.alt = source.alt;
      caption.textContent = source.alt;
      document.body.classList.add('dialog-open');
      dialog.showModal();
    });
  }
  dialog.querySelector('.dialog-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => {
    const bounds = dialog.getBoundingClientRect();
    if (event.target === dialog && (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom)) dialog.close();
  });
  dialog.addEventListener('close', () => document.body.classList.remove('dialog-open'));
}

function httpsUrl(value) {
  if (typeof value !== 'string') return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password ? url.href : null;
  } catch { return null; }
}

function mediaUrl(value) {
  if (typeof value !== 'string' || !value.trim()) return null;
  try {
    const url = new URL(value, document.baseURI);
    if (url.username || url.password) return null;
    const local = url.origin === location.origin && ['http:', 'https:'].includes(url.protocol);
    return local || url.protocol === 'https:' ? url.href : null;
  } catch { return null; }
}

export function applyReleaseConfig(config) {
  let available = 0;
  for (const [platform, url] of [['android', config.androidUrl], ['ios', config.iosUrl]]) {
    const destination = httpsUrl(url);
    const button = document.getElementById(`${platform}-download`);
    if (!button || !destination) continue;
    const link = document.createElement('a');
    link.className = button.className;
    link.id = button.id;
    link.href = destination;
    link.rel = 'noopener noreferrer';
    link.append(...[...button.childNodes].map(node => node.cloneNode(true)));
    link.querySelector('small').textContent = 'Download for';
    button.replaceWith(link);
    available++;
  }
  if (available) document.querySelector('#download-status').textContent = available === 2 ? 'Choose your platform and find your next dare.' : 'One platform is ready. More download links are on their way.';
  const container = document.querySelector('#promo-container');
  const landscape = mediaUrl(config.promoVideoUrl);
  const portrait = mediaUrl(config.promoPortraitVideoUrl);
  // Choose the cut on page load. Resizing must not restart a film in progress.
  const usePortrait = matchMedia('(max-width: 600px)').matches && !!portrait;
  const videoUrl = usePortrait ? portrait : landscape;
  if (videoUrl && container) {
    container.querySelector('video')?.pause();
    const video = document.createElement('video');
    video.controls = true;
    video.playsInline = true;
    video.preload = 'none';
    video.src = videoUrl;
    const poster = mediaUrl(usePortrait ? config.promoPortraitPosterUrl : config.promoPosterUrl);
    if (poster) video.poster = poster;
    video.setAttribute('aria-label', 'MoodDare promotional film');
    video.setAttribute('aria-describedby', 'film-description');
    const captions = mediaUrl(config.promoCaptionsUrl);
    if (captions) {
      const track = document.createElement('track');
      track.kind = 'captions';
      track.src = captions;
      track.srclang = 'en';
      track.label = 'English';
      video.append(track);
    }
    const fallback = document.createElement('a');
    fallback.href = videoUrl;
    fallback.textContent = 'Watch the MoodDare film';
    video.append('Your browser does not support embedded video. ', fallback);
    container.classList.toggle('film-portrait', usePortrait);
    container.replaceChildren(video);
  }
}

applyReleaseConfig(release);
const year = document.querySelector('#year');
if (year) year.textContent = String(new Date().getFullYear());
