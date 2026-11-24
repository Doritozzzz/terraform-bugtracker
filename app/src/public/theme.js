// Runs before the page paints, so there is no flash of the wrong theme.
// Light is the default; dark only when the user picked it with the toggle.
try {
  document.documentElement.dataset.theme = localStorage.getItem('theme') === 'dark' ? 'dark' : 'light';
} catch {
  document.documentElement.dataset.theme = 'light';
}
