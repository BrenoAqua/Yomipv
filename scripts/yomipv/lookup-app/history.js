const { ipcRenderer } = require('electron');

const listContainer = document.getElementById('history-list');
const scrollClip = document.getElementById('history-scroll-clip');
const headerTitle = document.getElementById('header-title');
const animToggle = document.getElementById('anim-toggle');
const clearBtn = document.getElementById('clear-history');

let isAppending = false;
let canExpand = false;
let autoScroll = true;
let prevIsAppending = false;

const container = document.getElementById('history-container');

container.addEventListener('pointerenter', () => {
  ipcRenderer.send('history-set-ignore-mouse', false);
});
container.addEventListener('pointerleave', () => {
  ipcRenderer.send('history-set-ignore-mouse', true);
});

document.addEventListener('selectionchange', () => {
  if (window.getSelection().toString().trim()) {
    autoScroll = false;
  }
});

const handleCopy = () => {
  const selection = window.getSelection().toString();
  if (selection) {
    require('electron').clipboard.writeText(selection);
    window.getSelection().removeAllRanges();
  }
};

document.addEventListener('copy', (e) => {
  handleCopy();
  e.preventDefault();
});

ipcRenderer.on('copy-selection', () => {
  handleCopy();
});

scrollClip.addEventListener('scroll', () => {
  const isAtBottom = scrollClip.scrollHeight - scrollClip.scrollTop - scrollClip.clientHeight < 10;
  autoScroll = isAtBottom;
});

function makeItem(entry, config) {
  const itemEl = document.createElement('div');
  itemEl.className = 'history-item';

  const priEl = document.createElement('div');
  priEl.className = 'primary-text';
  priEl.textContent = entry.primary_sid || '';
  itemEl.appendChild(priEl);

  if (config && config.history_show_secondary !== false && entry.secondary_sid) {
    const secEl = document.createElement('div');
    secEl.className = 'secondary-text';
    const lines = entry.secondary_sid.split(/[\r\n]+/).map(s => s.trim()).filter(Boolean);
    secEl.textContent = [...new Set(lines)].join('\n');
    itemEl.appendChild(secEl);
  }

  itemEl.addEventListener('click', () => {
    if (window.getSelection().toString().trim().length > 0) return;
    if (canExpand) {
      ipcRenderer.send('history-expand', entry);
    } else if (entry.start !== undefined && entry.start >= 0) {
      ipcRenderer.send('history-jump', entry.start);
    }
  });

  return itemEl;
}

ipcRenderer.on('update-history', (event, payload) => {
  const { entries, config, is_appending, can_expand } = payload;

  isAppending = is_appending;
  canExpand = !!can_expand;
  headerTitle.textContent = isAppending ? 'SELECTED' : 'HISTORY';

  if (config) {
    animToggle.textContent = config.picture_animated ? 'GIF: ON' : 'GIF: OFF';
    animToggle.classList.toggle('active', config.picture_animated);
    if (config.history_accent_color) {
      document.documentElement.style.setProperty('--accent-color', '#' + config.history_accent_color);
      document.documentElement.style.setProperty('--header-bg', '#' + config.history_accent_color);
    }
  }

  const entriesArray = Array.isArray(entries) ? entries : [];
  const currentCount = listContainer.children.length;
  const modeChanged = isAppending !== prevIsAppending;
  prevIsAppending = isAppending;

  if (modeChanged || entriesArray.length < currentCount) {
    // Full rebuild when mode switches or items were removed (e.g. clear)
    listContainer.innerHTML = '';
    entriesArray.forEach(entry => listContainer.appendChild(makeItem(entry, config)));
  } else {
    // Patch text of existing items (monitor can merge primary and secondary text after initial render)
    const existingItems = listContainer.children;
    for (let i = 0; i < currentCount && i < entriesArray.length; i++) {
      const entry = entriesArray[i];
      const item = existingItems[i];
      
      const priEl = item.querySelector('.primary-text');
      if (priEl && priEl.textContent !== (entry.primary_sid || '')) {
        priEl.textContent = entry.primary_sid || '';
      }

      let secEl = item.querySelector('.secondary-text');
      const newSec = entry.secondary_sid
        ? [...new Set(entry.secondary_sid.split(/[\r\n]+/).map(s => s.trim()).filter(Boolean))].join('\n')
        : '';

      if (newSec) {
        if (!secEl && config && config.history_show_secondary !== false) {
          secEl = document.createElement('div');
          secEl.className = 'secondary-text';
          secEl.textContent = newSec;
          item.appendChild(secEl);
        } else if (secEl && secEl.textContent !== newSec) {
          secEl.textContent = newSec;
        }
      } else if (secEl) {
        secEl.remove();
      }
    }

    // Append genuinely new entries
    for (let i = currentCount; i < entriesArray.length; i++) {
      listContainer.appendChild(makeItem(entriesArray[i], config));
    }
  }

  if (autoScroll) {
    scrollClip.scrollTop = scrollClip.scrollHeight;
  }
});

ipcRenderer.on('show-history', () => {
  document.body.classList.add('visible');
  if (autoScroll) {
    scrollClip.scrollTop = scrollClip.scrollHeight;
  }
});

ipcRenderer.on('hide-history', () => {
  document.body.classList.remove('visible');
});

animToggle.addEventListener('click', () => {
  ipcRenderer.send('history-toggle-anim');
});

clearBtn.addEventListener('click', () => {
  ipcRenderer.send('history-clear');
});
