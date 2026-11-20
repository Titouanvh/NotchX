const notch = document.querySelector('.notch-button');

notch.addEventListener('click', () => {
  const open = notch.getAttribute('aria-expanded') !== 'true';
  notch.setAttribute('aria-expanded', String(open));
  notch.setAttribute('aria-label', open ? 'Replier l’encoche' : 'Ouvrir l’encoche');
  document.getElementById(notch.getAttribute('aria-controls')).inert = !open;
});

const list = document.querySelector('[role="tablist"]');
const tabs = [...list.querySelectorAll('[role="tab"]')];
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const stackedFeatures = window.matchMedia('(max-width: 720px)');

function updateTabOrientation() {
  list.setAttribute('aria-orientation', stackedFeatures.matches ? 'horizontal' : 'vertical');
}

stackedFeatures.addEventListener('change', updateTabOrientation);
updateTabOrientation();


function selectTab(selected, focus = false) {
  if (selected.getAttribute('aria-selected') === 'true') return;

  for (const tab of tabs) {
    const active = tab === selected;
    const view = document.getElementById(tab.getAttribute('aria-controls'));
    tab.setAttribute('aria-selected', String(active));
    tab.tabIndex = active ? 0 : -1;
    view.hidden = !active;

    if (active && !reducedMotion.matches) {
      view.animate(
        [{ opacity: 0, transform: 'translateY(7px)' }, { opacity: 1, transform: 'translateY(0)' }],
        { duration: 275, easing: 'cubic-bezier(.22,.8,.26,1)' },
      );
    }
  }

  if (focus) selected.focus();
}

for (const tab of tabs) {
  tab.addEventListener('click', () => selectTab(tab));
}

list.addEventListener('keydown', (event) => {
  const index = tabs.indexOf(event.target);
  if (index === -1) return;

  const next = {
    ArrowDown: (index + 1) % tabs.length,
    ArrowRight: (index + 1) % tabs.length,
    ArrowUp: (index + tabs.length - 1) % tabs.length,
    ArrowLeft: (index + tabs.length - 1) % tabs.length,
    Home: 0,
    End: tabs.length - 1,
  }[event.key];

  if (next === undefined) return;
  event.preventDefault();
  selectTab(tabs[next], true);
});

const film = document.querySelector('[data-film]');
const dialog = document.querySelector('.film-dialog');
const video = dialog.querySelector('video');

film.addEventListener('click', (event) => {
  if (typeof dialog.showModal !== 'function' || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  event.preventDefault();
  if (!video.src) video.src = film.href;
  dialog.showModal();
  video.play().catch(() => {});
});

dialog.addEventListener('close', () => {
  video.pause();
  film.focus();
});

dialog.addEventListener('click', (event) => {
  if (event.target !== dialog) return;
  const box = dialog.getBoundingClientRect();
  if (event.clientX < box.left || event.clientX > box.right ||
      event.clientY < box.top || event.clientY > box.bottom) dialog.close();
});
