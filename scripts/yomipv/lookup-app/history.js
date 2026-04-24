const { ipcRenderer } = require('electron');

const listContainer = document.getElementById('history-list');
const scrollClip = document.getElementById('history-scroll-clip');
const headerTitle = document.getElementById('header-title');
const animToggle = document.getElementById('anim-toggle');
const settingsBtn = document.getElementById('open-settings');
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

document.body.addEventListener('contextmenu', (e) => {
  const hasSelection = window.getSelection().toString().length > 0;
  ipcRenderer.send('show-context-menu', hasSelection);
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
  window.getSelection().removeAllRanges();
});

const updateFades = () => {
  const isAtTop = scrollClip.scrollTop < 5;
  const isAtBottom = scrollClip.scrollHeight - scrollClip.scrollTop - scrollClip.clientHeight < 5;
  
  container.classList.toggle('hide-top-fade', isAtTop);
  container.classList.toggle('hide-bottom-fade', isAtBottom);
};

scrollClip.addEventListener('scroll', () => {
  const isAtBottom = scrollClip.scrollHeight - scrollClip.scrollTop - scrollClip.clientHeight < 10;
  autoScroll = isAtBottom;
  updateFades();
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

  itemEl.addEventListener('click', (e) => {
    const selection = window.getSelection();
    if (!selection.isCollapsed && selection.containsNode(e.target, true)) {
      return;
    }
    selection.removeAllRanges();

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
      const color = config.history_accent_color.trim();
      const lower = color.toLowerCase();
      const isColorFunc = lower.startsWith('rgb') || lower.startsWith('rgba') || lower === 'transparent' || lower === '';
      const accent = isColorFunc ? color : (color.startsWith('#') ? color : '#' + color);
      document.documentElement.style.setProperty('--accent-color', accent);
    }
    if (config.history_font_size) {
      document.documentElement.style.setProperty('--font-size-pri', config.history_font_size + 'px');
    }
    if (config.history_secondary_font_size) {
      document.documentElement.style.setProperty('--font-size-sec', config.history_secondary_font_size + 'px');
    }
    if (config.history_width) {
      document.documentElement.style.setProperty('--history-width', config.history_width + 'px');
    }
    if (config.history_max_height) {
      const val = config.history_max_height.toString();
      const hasUnit = /[a-z%]$/i.test(val);
      if (hasUnit) {
        document.documentElement.style.setProperty('--history-max-height', val);
      } else {
        const num = parseInt(val);
        document.documentElement.style.setProperty('--history-max-height', num > 0 ? num + 'px' : '60vh');
      }
    }
    if (config.history_background_opacity) {
      let alpha = 0.86;
      const op = config.history_background_opacity;
      if (typeof op === 'string') {
        if (op.endsWith('%')) {
          alpha = parseInt(op) / 100;
        } else {
          alpha = parseInt(op, 16) / 255;
        }
      }
      document.documentElement.style.setProperty('--bg-opacity', alpha);
    }
    if (config.history_font_family) {
      document.documentElement.style.setProperty('--font-sans', `${config.history_font_family}, "Hiragino Kaku Gothic ProN", "Noto Sans CJK JP", "Segoe UI", sans-serif`);
    }
    if (config.history_border_radius) {
      document.documentElement.style.setProperty('--radius', config.history_border_radius + 'px');
    }
    if (config.history_background_color) {
      const color = config.history_background_color.trim();
      const lower = color.toLowerCase();
      const isColorFunc = lower.startsWith('rgb') || lower.startsWith('rgba') || lower === 'transparent' || lower === '';
      const hbg = isColorFunc ? color : (color.startsWith('#') ? color : '#' + color);
      document.documentElement.style.setProperty('--bg-color-hex', hbg);
    }
    if (config.history_header_background_color !== undefined) {
      const hbg = (config.history_header_background_color || 'rgba(255, 255, 255, 0.1)').trim();
      const lower = hbg.toLowerCase();
      const isColorFunc = lower.startsWith('rgb') || lower.startsWith('rgba') || lower === 'transparent' || lower === '';
      const finalHbg = isColorFunc ? hbg : (hbg.startsWith('#') ? hbg : '#' + hbg);
      document.documentElement.style.setProperty('--header-bg', finalHbg);
    }
  }

  const entriesArray = Array.isArray(entries) ? entries : [];
  const currentCount = listContainer.children.length;
  const modeChanged = isAppending !== prevIsAppending;
  prevIsAppending = isAppending;

  if (modeChanged || entriesArray.length < currentCount) {
    // Rebuild on mode switch or item removal
    listContainer.innerHTML = '';
    entriesArray.forEach(entry => listContainer.appendChild(makeItem(entry, config)));
  } else {
    // Update existing items
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

    // Append remaining entries
    for (let i = currentCount; i < entriesArray.length; i++) {
      listContainer.appendChild(makeItem(entriesArray[i], config));
    }
  }

  if (autoScroll) {
    scrollClip.scrollTop = scrollClip.scrollHeight;
  }
  updateFades();
});

ipcRenderer.on('show-history', () => {
  document.body.classList.add('visible');
  if (autoScroll) {
    scrollClip.scrollTop = scrollClip.scrollHeight;
  }
  updateFades();
});

ipcRenderer.on('hide-history', () => {
  document.body.classList.remove('visible');
});

animToggle.addEventListener('click', () => {
  ipcRenderer.send('history-toggle-anim');
});

settingsBtn.addEventListener('click', () => {
  ipcRenderer.send('open-settings');
});

clearBtn.addEventListener('click', () => {
  ipcRenderer.send('history-clear');
});
