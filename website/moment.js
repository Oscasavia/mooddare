const match = /^\/moment\/([a-zA-Z0-9_-]{1,128})$/.exec(location.pathname);
const button = document.querySelector('#open-app');
if (!match || location.search || location.hash) {
  document.querySelector('h1').textContent = 'This link looks incomplete.';
  document.querySelector('#message').textContent = 'Ask your friend to share the moment again, or explore MoodDare below.';
} else if (/Android/i.test(navigator.userAgent)) {
  // User-initiated Android intent, restricted to this package and HTTPS host.
  // No automatic redirects, arbitrary destinations or public post/media fetches.
  button.href = `intent://mooddare.web.app/moment/${match[1]}#Intent;scheme=https;package=com.example.mooddare;end`;
  button.hidden = false;
  document.querySelector('#availability').textContent = 'Already have the Android test app? Tap above. Otherwise, public downloads are coming soon.';
}
