const { ipcRenderer } = require('electron');

const glossaryEl = document.getElementById('glossary-content');
const headerEl = document.getElementById('term-header');
const entryPrev = document.getElementById('entry-prev');
const entryNext = document.getElementById('entry-next');
const entryCounter = document.getElementById('entry-counter');

let allEntries = [];
let currentEntryIndex = 0;
let currentShowFrequencies = false;

const filterDictionaryStyles = (styleEl, dictName) => {
  if (!styleEl || !styleEl.sheet || !styleEl.sheet.cssRules || styleEl.sheet.cssRules.length === 0) return '';
  try {
    const filterRules = (rules) => {
      let cssText = '';
      for (let i = 0; i < rules.length; i++) {
        const rule = rules[i];

        if (rule.type === CSSRule.STYLE_RULE) {
          const match = rule.selectorText && rule.selectorText.match(/\[data-dictionary=["']?([^\]"']+)["']?\]/);
          if (match) {
            if (match[1] === dictName) {
              cssText += rule.cssText + '\n';
            }
          } else if (rule.cssRules && rule.cssRules.length > 0) {
            const innerText = filterRules(rule.cssRules);
            if (innerText.trim().length > 0) {
              cssText += `${rule.selectorText} {\n${innerText}}\n`;
            }
          }
        } else if (rule.type === CSSRule.KEYFRAMES_RULE || rule.type === CSSRule.FONT_FACE_RULE) {
          cssText += rule.cssText + '\n';
        } else if (rule.type === CSSRule.SUPPORTS_RULE && rule.cssRules) {
          const innerText = filterRules(rule.cssRules);
          if (innerText.trim().length > 0) {
            cssText += `@supports ${rule.conditionText} {\n${innerText}}\n`;
          }
        }
      }
      return cssText;
    };
    const filteredCss = filterRules(styleEl.sheet.cssRules);
    if (!filteredCss.trim()) return '';
    return `<style>${filteredCss.replace(/\n+/g, ' ')}</style>`;
  } catch (e) {
    console.error('[UI] Failed to filter styles:', e);
    return '';
  }
};

const renderHeader = (term, reading, furigana, frequencies) => {
  const cleanTerm = (term || '').trim();

  let headerHtml = '';
  if (furigana && furigana.includes('[')) {
    headerHtml = furigana.replace(/([^\[\]]+)\[([^\[\]]+)\]/g, '<ruby>$1<rt>$2</rt></ruby>');
  } else if (reading && reading !== cleanTerm) {
    headerHtml = `<ruby>${cleanTerm}<rt>${reading}</rt></ruby>`;
  } else {
    headerHtml = `<div class="term-expression">${cleanTerm}</div>`;
  }

  let freqHtml = '';
  if (frequencies && frequencies.length > 0) {
    freqHtml = `
      <div class="frequency-badges" style="margin: 0;">
        ${frequencies.map(f => `
          <div class="frequency-badge">
            <span class="frequency-dict">${f.dictionary}</span>
            <span class="frequency-value">${f.frequency}</span>
          </div>
        `).join('')}
      </div>
    `;
  }

  headerEl.innerHTML = `
    <div class="term-display">
      ${headerHtml}
    </div>
    <div class="header-frequencies">
      ${freqHtml}
    </div>
  `;
};

const applyPitchColor = (pitchTarget) => {
  const pitchColors = {
    'atamadaka': 'var(--pitch-red)',
    'heiban': 'var(--pitch-blue)',
    'nakadaka': 'var(--pitch-orange)',
    'odaka': 'var(--pitch-green)',
    'kifuku': 'var(--pitch-purple)'
  };
  const firstPitch = pitchTarget.split(/[\s,]+/).find(p => pitchColors[p.toLowerCase()]);
  if (firstPitch) {
    headerEl.style.setProperty('--pitch-accent-color', pitchColors[firstPitch.toLowerCase()]);
  } else {
    headerEl.style.removeProperty('--pitch-accent-color');
  }
};

const buildFrequencies = (entries, targetExpression, targetReading, showFrequencies) => {
  const allFrequenciesMap = new Map();
  if (!showFrequencies || !Array.isArray(entries)) return [];

  entries.forEach(entry => {
    const eFields = entry.fields || entry;
    if (!eFields.frequencies) return;
    if (eFields.expression !== targetExpression || eFields.reading !== targetReading) return;

    let freqData = [];
    const rawValue = eFields.frequencies;

    try {
      const parsed = typeof rawValue === 'string' ? JSON.parse(rawValue) : rawValue;
      freqData = Array.isArray(parsed) ? parsed : [parsed];
    } catch (e) {
      const cleanText = rawValue.replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim();
      const pattern = /([^:,\(\)]+):\s*([^:,\(\)]+?)(?=\s+[^:,\(\)]+:|$)/g;
      const matches = Array.from(cleanText.matchAll(pattern));
      if (matches.length > 0) {
        freqData = matches.map(m => ({ dictionary: m[1].trim(), frequency: m[2].trim() }));
      } else if (cleanText.includes(':')) {
        const [dict, val] = cleanText.split(/:\s*/);
        freqData = [{ dictionary: dict.trim(), frequency: val.trim() }];
      } else if (cleanText.length > 0) {
        freqData = [{ dictionary: 'Freq', frequency: cleanText }];
      }
    }

    if (Array.isArray(freqData)) {
      freqData.forEach(f => {
        if (!f || !f.dictionary || !f.frequency) return;
        const dict = String(f.dictionary).replace(/<[^>]*>/g, '').trim();
        let freq = String(f.frequency).replace(/<[^>]*>/g, '').trim();
        if (freq.toLowerCase().endsWith(dict.toLowerCase())) {
          freq = freq.substring(0, freq.length - dict.length).trim();
        }
        [' Jiten', ' Wikipedia', ' Ranked', ' Info'].forEach(s => {
          if (freq.endsWith(s)) freq = freq.substring(0, freq.length - s.length).trim();
        });
        if (dict && freq) {
          const existing = allFrequenciesMap.get(dict);
          if (existing) {
            if (!existing.frequency.includes(freq)) existing.frequency += `, ${freq}`;
          } else {
            allFrequenciesMap.set(dict, { dictionary: dict, frequency: freq });
          }
        }
      });
    }
  });

  return Array.from(allFrequenciesMap.values());
};

const renderEntry = (index, rawEntries, showFrequencies) => {
  const entry = rawEntries[index];
  if (!entry) return;

  const fields = entry.fields || entry;
  const term = fields.expression || '';
  const furigana = fields.furigana || '';
  let reading = fields.reading || '';
  const pitchAccents = fields['pitch-accents'] || '';

  if (pitchAccents) {
    const tempPitch = document.createElement('div');
    tempPitch.innerHTML = pitchAccents;
    const firstPitch = tempPitch.querySelector('li');
    if (firstPitch) reading = firstPitch.innerHTML;
  }

  const frequencies = buildFrequencies(rawEntries, fields.expression, fields.reading, showFrequencies);
  renderHeader(term, reading, furigana, frequencies);
  applyPitchColor(fields['pitch-accent-categories'] || '');

  if (fields.glossary || fields.definition) {
    let content = fields.glossary || fields.definition;
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = content;
    tempDiv.querySelectorAll('img').forEach(img => img.remove());

    tempDiv.querySelectorAll('[data-dictionary*="Jitendex"]').forEach(dictEl => {
      dictEl.querySelectorAll('[data-sc-content="glossary"]').forEach(gl => {
        Array.from(gl.childNodes).forEach(node => {
          const isText = node.nodeType === Node.TEXT_NODE && node.textContent.trim().length > 0;
          const isElement = node.nodeType === Node.ELEMENT_NODE && !node.matches('span[data-details]');
          if ((isText || isElement) && node.textContent.match(/^[①-⑳]/)) {
            const text = node.textContent.replace(/^[①-⑳]\s*/, '');
            if (isText) node.textContent = text; else node.innerText = text;
          }
        });
      });
      dictEl.querySelectorAll('li').forEach(li => { li.style.listStyle = 'none'; });
    });

    glossaryEl.innerHTML = tempDiv.innerHTML;
  } else {
    glossaryEl.innerHTML = `No result found.`;
  }

  glossaryEl.querySelectorAll('a, [data-link]').forEach(el => {
    el.onclick = (e) => e.preventDefault();
    el.style.pointerEvents = 'none';
    el.style.cursor = 'default';
  });

  glossaryEl.querySelectorAll('[data-dictionary]').forEach(el => {
    const titleEl = el.firstElementChild;
    if (titleEl) {
      titleEl.textContent = titleEl.textContent.replace(/[()]/g, '').trim();
    }
  });

  glossaryEl.querySelectorAll('[data-dictionary]').forEach(el => {
    const titleEl = el.firstElementChild;
    if (!titleEl) return;
    titleEl.style.cursor = 'pointer';

    titleEl.addEventListener('click', (e) => {
      e.stopPropagation();
      glossaryEl.querySelectorAll('[data-dictionary] > *:first-child').forEach(child => {
        child.classList.remove('selected');
      });
      titleEl.classList.add('selected');
      sendSelectedDict(el);
    });
  });

  entryCounter.textContent = `${index + 1} / ${rawEntries.length}`;
  const showNav = rawEntries.length > 1;
  entryPrev.style.display = showNav ? 'flex' : 'none';
  entryNext.style.display = showNav ? 'flex' : 'none';
  entryCounter.style.display = showNav ? '' : 'none';

  // Sync active entry for Anki export matching
  ipcRenderer.send('active-entry', { expression: fields.expression, reading: fields.reading });
};

const sendSelectedDict = (el) => {
  const dictName = el.getAttribute('data-dictionary');
  const dictionaryHtml = el.outerHTML;

  let styleHtml = '';
  glossaryEl.querySelectorAll('style').forEach(styleEl => {
    styleHtml += filterDictionaryStyles(styleEl, dictName);
  });

  const dictContent = `<div class="yomitan-glossary" style="text-align: left;"><ol>${dictionaryHtml}</ol></div>${styleHtml}`;
  console.log('[UI] Dictionary selected:', dictName);
  ipcRenderer.send('dictionary-selected', dictContent);
};

ipcRenderer.on('lookup-term', async (event, data) => {
  console.log('[IPC] Received lookup data:', JSON.stringify(data));

  allEntries = [];
  currentEntryIndex = 0;
  currentShowFrequencies = data.showFrequencies || false;
  entryPrev.style.display = 'none';
  entryNext.style.display = 'none';
  entryCounter.style.display = 'none';

  renderHeader(data.term, data.reading, null, null);
  glossaryEl.innerHTML = '<div class="loading">Looking up...</div>';

  try {
    let result;
    const endpoints = [`http://127.0.0.1:19633/ankiFields`, `http://127.0.0.1:19633/api/ankiFields`];

    for (const url of endpoints) {
      try {
        const response = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            text: data.term,
            type: 'term',
            markers: [
              'glossary', 'expression', 'reading', 'furigana',
              'pitch-accent-categories', 'pitch-accents',
              ...(data.showFrequencies ? ['frequencies'] : [])
            ],
            maxEntries: 10,
            includeMedia: true
          })
        });

        if (response.ok) {
          result = await response.json();
          break;
        } else {
          console.warn(`Endpoint ${url} failed with status: ${response.status}`);
        }
      } catch (err) {
        console.warn(`Failed to fetch from ${url}:`, err);
      }
    }

    if (!result) throw new Error('All Yomitan endpoints failed');

    const entries = (result && result.fields) || (result && result[0] && result[0].fields) || [];

    if (!Array.isArray(entries) || entries.length === 0) {
      glossaryEl.innerHTML = `No result found for "${data.term}".`;
      return;
    }

    const sorted = [...entries].sort((a, b) => {
      const fa = a.fields || a;
      const fb = b.fields || b;
      const scoreA = ((fa['pitch-accents'] && fa['pitch-accents'] !== '') ? 2 : 0) +
                     ((fa.expression && fa.expression !== fa.reading) ? 1 : 0);
      const scoreB = ((fb['pitch-accents'] && fb['pitch-accents'] !== '') ? 2 : 0) +
                     ((fb.expression && fb.expression !== fb.reading) ? 1 : 0);
      return scoreB - scoreA;
    });

    allEntries = sorted;
    currentEntryIndex = 0;
    renderEntry(currentEntryIndex, allEntries, currentShowFrequencies);

  } catch (e) {
    console.error('Lookup failed', e);
    glossaryEl.innerHTML = `Error fetching from Yomitan: ${e.message}`;
  }
});

entryPrev.addEventListener('click', () => {
  if (allEntries.length === 0) return;
  currentEntryIndex = (currentEntryIndex - 1 + allEntries.length) % allEntries.length;
  renderEntry(currentEntryIndex, allEntries, currentShowFrequencies);
});

entryNext.addEventListener('click', () => {
  if (allEntries.length === 0) return;
  currentEntryIndex = (currentEntryIndex + 1) % allEntries.length;
  renderEntry(currentEntryIndex, allEntries, currentShowFrequencies);
});

let selectionTimeout;
document.addEventListener('selectionchange', () => {
  clearTimeout(selectionTimeout);
  selectionTimeout = setTimeout(() => {
    let selection = window.getSelection().toString().trim();
    if (!selection) return;
    selection = selection.replace(/\r?\n/g, '<br>');
    ipcRenderer.send('sync-selection', selection);
  }, 200);
});

document.addEventListener('mouseup', () => {
  const selection = window.getSelection();
  if (selection.rangeCount === 0 || selection.isCollapsed) return;

  const range = selection.getRangeAt(0);
  if (!glossaryEl.contains(range.commonAncestorContainer)) return;

  const startRuby = range.startContainer.parentElement?.closest('ruby');
  const endRuby = range.endContainer.parentElement?.closest('ruby');

  if (startRuby || endRuby) {
    if (startRuby) range.setStartBefore(startRuby);
    if (endRuby) range.setEndAfter(endRuby);
    selection.removeAllRanges();
    selection.addRange(range);
  }

  const contents = range.cloneContents();
  const hasBlocks = contents.querySelector('div, p, li, ol, ul');

  if (!hasBlocks) {
    const span = document.createElement('span');
    span.className = 'highlight';
    try {
      range.surroundContents(span);
    } catch (e) {
      span.appendChild(range.extractContents());
      range.insertNode(span);
    }
  }

  const selectedTitle = glossaryEl.querySelector('[data-dictionary] > .selected');
  if (selectedTitle) {
    sendSelectedDict(selectedTitle.parentElement);
  }
});
