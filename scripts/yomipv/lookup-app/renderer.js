const { ipcRenderer } = require('electron');
const { toNormalizedChars, computeMatchedLen } = require('./match-sort');

const glossaryEl = document.getElementById('glossary-content');
const headerEl = document.getElementById('term-header');
const entryPrev = document.getElementById('entry-prev');
const entryNext = document.getElementById('entry-next');
const entryCounter = document.getElementById('entry-counter');
let isWindowVisible = false;
let isPerformingLookup = false;

let allEntries = [];
let currentEntryIndex = 0;
let currentShowFrequencies = false;
let currentDictionaryMedia = [];
let lookupHistory = [];
let currentAbortController = null;
let currentPrioritizeKanjiMatch = false;
let currentPrioritizeHiraganaMatch = false;
let currentShowPitchAccents = true;

const renderHeader = (term, reading, frequencies) => {
  const cleanTerm = (term || '').trim();

  // Wrap each character in a clickable span
  const wrapChars = (text, startIndex = 0) => {
    return Array.from(text).map((char, i) => 
      `<span class="header-char" data-index="${startIndex + i}">${char}</span>`
    ).join('');
  };

  let headerHtml = '';
  if (reading && reading !== cleanTerm) {
    headerHtml = `<ruby><span class="header-base">${wrapChars(cleanTerm)}</span><rt>${reading}</rt></ruby>`;
  } else {
    headerHtml = `<div class="term-expression">${wrapChars(cleanTerm)}</div>`;
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
    ${freqHtml ? `<div class="header-frequencies">${freqHtml}</div>` : ''}
  `;

  // Attach click listeners to characters
  headerEl.querySelectorAll('.header-char').forEach(el => {
    el.onclick = (e) => {
      e.stopPropagation();
      const index = parseInt(el.getAttribute('data-index'));
      const subTerm = cleanTerm.substring(index);
      if (subTerm && subTerm !== cleanTerm) {
        console.log('[UI] Sending sync-selection for header click:', subTerm);
        ipcRenderer.send('sync-selection-hint', subTerm);
        performLookup(subTerm, currentShowFrequencies, currentShowPitchAccents, false, currentPrioritizeKanjiMatch, currentPrioritizeHiraganaMatch);
      }
    };
  });

  // Go back to previous term on right click
  headerEl.oncontextmenu = (e) => {
    e.preventDefault();
    if (lookupHistory.length > 0) {
      const prev = lookupHistory.pop();
      performLookup(prev.term, prev.showFrequencies, prev.showPitchAccents, true, prev.prioritizeKanjiMatch, prev.prioritizeHiraganaMatch);
    }
  };
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

const renderEntry = (index, rawEntries, showFrequencies, showPitchAccents) => {
  const entry = rawEntries[index];
  if (!entry) return;

  const fields = entry.fields || entry;
  const term = fields.expression || '';
  let reading = fields.reading || '';
  const pitchAccents = fields['pitch-accents'] || '';
  const firstPitch = fields['pitch-accent-categories'] || '';

  if (showPitchAccents && pitchAccents) {
    const tempPitch = document.createElement('div');
    tempPitch.innerHTML = pitchAccents;
    const firstPitchEl = tempPitch.querySelector('li');
    if (firstPitchEl) reading = firstPitchEl.innerHTML;
  }

  const frequencies = buildFrequencies(rawEntries, fields.expression, fields.reading, showFrequencies);
  renderHeader(term, reading, frequencies);
  
  if (showPitchAccents) {
    applyPitchColor(firstPitch);
  } else {
    headerEl.style.removeProperty('--pitch-accent-color');
  }

  if (fields.glossary || fields.definition) {
    let content = fields.glossary || fields.definition;
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = content;

    tempDiv.querySelectorAll('img').forEach(img => {
      const src = img.getAttribute('src');
      if (src && currentDictionaryMedia) {
        const srcFilename = src.split(/[\\/]/).pop();
        const media = currentDictionaryMedia.find(m => 
          m.ankiFilename === src || 
          m.filename === src || 
          m.ankiFilename === srcFilename || 
          m.filename === srcFilename
        );

        if (media && media.content) {
          const ext = srcFilename.split('.').pop().toLowerCase();
          const mimeMap = {
            'png': 'image/png',
            'gif': 'image/gif',
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'webp': 'image/webp',
            'svg': 'image/svg+xml'
          };
          const mime = mimeMap[ext] || 'image/png';
          img.src = `data:${mime};base64,${media.content}`;
          img.setAttribute('data-anki-src', src);
        }
      }
    });

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
      titleEl.dataset.originalTitle = titleEl.textContent;
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
  
  // Clone for export and revert image sources to original filenames
  const exportEl = el.cloneNode(true);
  exportEl.querySelectorAll('img[data-anki-src]').forEach(img => {
    img.src = img.getAttribute('data-anki-src');
    img.removeAttribute('data-anki-src');
  });

  // Remove inline style properties injected by the lookup UI
  exportEl.querySelectorAll('a, [data-link]').forEach(link => {
    link.style.removeProperty('pointer-events');
    link.style.removeProperty('cursor');
    if (!link.style.cssText) link.removeAttribute('style');
  });
  const exportTitle = exportEl.firstElementChild;
  if (exportTitle) {
    if (exportTitle.dataset.originalTitle) {
      exportTitle.textContent = exportTitle.dataset.originalTitle;
      exportTitle.removeAttribute('data-original-title');
    }
    exportTitle.classList.remove('selected');
    exportTitle.style.removeProperty('cursor');
    if (!exportTitle.style.cssText) exportTitle.removeAttribute('style');
  }
  exportEl.querySelectorAll('li').forEach(li => {
    li.style.removeProperty('list-style');
    if (!li.style.cssText) li.removeAttribute('style');
  });

  const dictionaryHtml = exportEl.outerHTML;

  // Each dictionary's <style> block selectors reference its own name, so a text match is sufficient
  let styleHtml = '';
  glossaryEl.querySelectorAll('style').forEach(styleEl => {
    const css = styleEl.textContent.trim();
    if (css && css.includes(dictName)) styleHtml += `<style>${css}</style>`;
  });

  const dictContent = `<div style="text-align: left;" class="yomitan-glossary"><ol>${dictionaryHtml}${styleHtml}</ol></div>`;
  console.log('[UI] Dictionary selected:', dictName);
  ipcRenderer.send('dictionary-selected', dictContent);
};

const performLookup = async (term, showFrequencies, showPitchAccents, isBack = false, prioritizeKanjiMatch, prioritizeHiraganaMatch) => {
  console.log('[UI] Performing lookup for:', term);
  
  const container = document.getElementById('lookup-container');
  const isVisible = container.classList.contains('visible');

  isPerformingLookup = true;

  // Abort any pending lookup fetch
  if (currentAbortController) {
    currentAbortController.abort();
  }
  currentAbortController = new AbortController();
  const { signal } = currentAbortController;

  // Detect if this is a sub-word transition
  let isSubword = false;
  let currentTerm = '';
  if (allEntries.length > 0 && currentEntryIndex < allEntries.length) {
    const currentFields = allEntries[currentEntryIndex].fields || allEntries[currentEntryIndex];
    currentTerm = currentFields.expression || '';
    isSubword = isWindowVisible && isVisible && currentTerm && currentTerm.includes(term);
  }

  // If identical term and already visible, skip fetch/re-render to avoid flicker
  if (isSubword && term === currentTerm && isWindowVisible && isVisible) {
    console.log('[UI] Identical term and already fully visible, skipping redundant lookup');
    isPerformingLookup = false;
    currentAbortController = null;
    return;
  }

  // Save current term to history if not going back
  if (!isBack && currentTerm && currentTerm !== term) {
    lookupHistory.push({
      term: currentTerm,
      showFrequencies: currentShowFrequencies,
      showPitchAccents: currentShowPitchAccents,
      prioritizeKanjiMatch: currentPrioritizeKanjiMatch,
      prioritizeHiraganaMatch: currentPrioritizeHiraganaMatch
    });
  }

  currentShowFrequencies = showFrequencies || false;
  currentShowPitchAccents = showPitchAccents !== undefined ? showPitchAccents : true;
  currentPrioritizeKanjiMatch = prioritizeKanjiMatch !== undefined ? prioritizeKanjiMatch : false;
  currentPrioritizeHiraganaMatch = prioritizeHiraganaMatch !== undefined ? prioritizeHiraganaMatch : false;

  // Show transition screen only for non-subword transitions
  if (!isSubword) {
    allEntries = [];
    currentEntryIndex = 0;
    
    // Hide the container to prevent seeing old content
    container.classList.add('no-transition');
    container.classList.remove('visible');
    
    headerEl.innerHTML = '';
    glossaryEl.innerHTML = '';
    entryPrev.style.display = 'none';
    entryNext.style.display = 'none';
    entryCounter.style.display = 'none';

    void container.offsetHeight;

    ipcRenderer.send('show-window');
    isWindowVisible = true;
  }

  try {
    let result;
    const endpoints = [`http://127.0.0.1:19633/ankiFields`, `http://127.0.0.1:19633/api/ankiFields`];

    for (const url of endpoints) {
      if (signal.aborted) return;
      try {
        const response = await fetch(url, {
          method: 'POST',
          signal: signal,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            text: term,
            type: 'term',
            markers: [
              'glossary', 'expression', 'reading',
              'pitch-accent-categories', 'pitch-accents',
              ...(showFrequencies ? ['frequencies'] : []),
              ...(showPitchAccents ? ['pitch-accents', 'pitch-accent-categories'] : [])
            ],
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

    currentDictionaryMedia = result.dictionaryMedia || (result[0] && result[0].dictionaryMedia) || [];
    const entries = (result && result.fields) || (result && result[0] && result[0].fields) || [];

    if (!Array.isArray(entries) || entries.length === 0) {
      allEntries = [];
      currentEntryIndex = 0;
      headerEl.innerHTML = '';
      glossaryEl.innerHTML = `No result found for "${term}".`;
      entryPrev.style.display = 'none';
      entryNext.style.display = 'none';
      entryCounter.style.display = 'none';
      
      ipcRenderer.send('show-window');
      isWindowVisible = true;

      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          container.classList.remove('no-transition');
          requestAnimationFrame(() => {
            requestAnimationFrame(() => {
              document.getElementById('lookup-container').classList.add('visible');
            });
          });
        });
      });
      return;
    }

    // Fetch termEntries in parallel to get maxOriginalTextLength per entry,
    // which reflects how many characters Yomitan consumed (including deconjugation).
    // This correctly ranks deconjugated forms above shorter literal prefix matches.
    const origLenMap = new Map();
    try {
      const termEntriesEndpoints = [
        `http://127.0.0.1:19633/termEntries`,
        `http://127.0.0.1:19633/api/termEntries`,
      ];
      let teResult;
      for (const url of termEntriesEndpoints) {
        if (signal.aborted) break;
        try {
          const r = await fetch(url, {
            method: 'POST',
            signal,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ term }),
          });
          if (r.ok) { teResult = await r.json(); break; }
        } catch (_) { /* try next endpoint */ }
      }
      if (teResult && Array.isArray(teResult.dictionaryEntries)) {
        for (const de of teResult.dictionaryEntries) {
          const origLen = de.maxOriginalTextLength || 0;
          if (!origLen) continue;
          for (const hw of (de.headwords || [])) {
            const key = `${hw.term}\x00${hw.reading}`;
            if ((origLenMap.get(key) || 0) < origLen) origLenMap.set(key, origLen);
          }
        }
      }
    } catch (_) { /* non-critical; fall back to prefix-match sort */ }

    const isHiraganaOnly = /^[\u3041-\u309F]+$/.test(term);
    const termChars = toNormalizedChars(term);

    const getOrigLen = (f) => {
      const key = `${f.expression || ''}\x00${f.reading || ''}`;
      return origLenMap.get(key) || 0;
    };

    const sorted = [...entries].sort((a, b) => {
      const fa = a.fields || a;
      const fb = b.fields || b;

      const exprA = fa.expression || '';
      const exprB = fb.expression || '';

      const cleanSortTerm = term.replace(/^[\s\u200B]+/, '');
      
      // Exact-match priority
      const exactA = exprA === cleanSortTerm ? 1 : 0;
      const exactB = exprB === cleanSortTerm ? 1 : 0;
      if (exactA !== exactB) return exactB - exactA;

      // Hiragana exact-match priority
      if (currentPrioritizeHiraganaMatch && isHiraganaOnly) {
        const exactA = exprA === term ? 1 : 0;
        const exactB = exprB === term ? 1 : 0;
        if (exactA !== exactB) return exactB - exactA;
      }

      const origA = getOrigLen(fa);
      const origB = getOrigLen(fb);

      // Prefer the entry whose deinflection consumed more of the original text
      if (origA !== origB) return origB - origA;

      // Katakana priority when matched prefix is Katakana
      let isKataA = 0;
      let isKataB = 0;
      const termKataPrefixMatch = cleanSortTerm.match(/^[\u30A0-\u30FF]+/);
      if (termKataPrefixMatch && termKataPrefixMatch[0].length > 0) {
        isKataA = /^[\u30A0-\u30FF]+$/.test(exprA) ? 1 : 0;
        isKataB = /^[\u30A0-\u30FF]+$/.test(exprB) ? 1 : 0;
      }
      if (isKataA !== isKataB) return isKataB - isKataA;

      // Fall back to kana prefix-match when termEntries gave the same (or no) length
      const lenA = computeMatchedLen(termChars, exprA, fa.reading || '');
      const lenB = computeMatchedLen(termChars, exprB, fb.reading || '');

      if (!currentPrioritizeKanjiMatch) {
        // Matched-length priority (common prefix with term, kana-normalized)
        if (lenA !== lenB) return lenB - lenA;

        // Kanji priority
        const kanjiA = (exprA && fa.reading && exprA !== fa.reading) ? 1 : 0;
        const kanjiB = (exprB && fb.reading && exprB !== fb.reading) ? 1 : 0;
        if (kanjiA !== kanjiB) return kanjiB - kanjiA;

        return 0;
      } else {
        // Kanji priority
        const kanjiA = (exprA && exprA !== fa.reading) ? 1 : 0;
        const kanjiB = (exprB && exprB !== fb.reading) ? 1 : 0;
        if (kanjiA !== kanjiB) return kanjiB - kanjiA;

        // Fallback to matched length
        return lenB - lenA;
      }
    });

    allEntries = sorted;
    currentEntryIndex = 0;
    renderEntry(currentEntryIndex, allEntries, currentShowFrequencies, currentShowPitchAccents);

    if (signal.aborted) return;

    if (isSubword) {
      container.classList.add('visible');
      isWindowVisible = true;
    } else {
      ipcRenderer.send('show-window');
      isWindowVisible = true;
      
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          container.classList.remove('no-transition');
          requestAnimationFrame(() => {
            requestAnimationFrame(() => {
              container.classList.add('visible');
            });
          });
        });
      });
    }

    isPerformingLookup = false;
    currentAbortController = null;

  } catch (e) {
    if (e.name === 'AbortError') return;
    console.error('Lookup failed', e);
    isPerformingLookup = false;
    currentAbortController = null;
    allEntries = [];
    currentEntryIndex = 0;
    headerEl.innerHTML = '';
    glossaryEl.innerHTML = `Error fetching from Yomitan: ${e.message}`;
    entryPrev.style.display = 'none';
    entryNext.style.display = 'none';
    entryCounter.style.display = 'none';
    
    ipcRenderer.send('show-window');
    isWindowVisible = true;

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        container.classList.remove('no-transition');
        requestAnimationFrame(() => {
          requestAnimationFrame(() => {
            document.getElementById('lookup-container').classList.add('visible');
          });
        });
      });
    });
  }
};

ipcRenderer.on('lookup-term', async (event, data) => {
  console.log('[IPC] Received lookup data:', JSON.stringify(data));
  
  if (data.theme === 'light') {
    document.body.classList.add('light-theme');
  } else {
    document.body.classList.remove('light-theme');
  }

  lookupHistory = [];
  performLookup(data.term, data.showFrequencies, data.showPitchAccents, false, data.prioritizeKanjiMatch, data.prioritizeHiraganaMatch);
});

ipcRenderer.on('window-hide-request', () => {
  console.log('[IPC] window-hide-request received, clearing and confirming');
  
  if (isPerformingLookup && currentAbortController) {
    console.log('[IPC] Aborting active lookup due to hide request');
    currentAbortController.abort();
    isPerformingLookup = false;
  }
  
  isWindowVisible = false;
  const container = document.getElementById('lookup-container');
  container.classList.add('no-transition');
  container.classList.remove('visible');
  headerEl.innerHTML = '';
  glossaryEl.innerHTML = '';
  allEntries = [];
  currentEntryIndex = 0;
  
  requestAnimationFrame(() => {
    ipcRenderer.send('window-hide-confirmed');
  });
});

entryPrev.addEventListener('click', () => {
  if (allEntries.length === 0) return;
  currentEntryIndex = (currentEntryIndex - 1 + allEntries.length) % allEntries.length;
  renderEntry(currentEntryIndex, allEntries, currentShowFrequencies, currentShowPitchAccents);
});

entryNext.addEventListener('click', () => {
  if (allEntries.length === 0) return;
  currentEntryIndex = (currentEntryIndex + 1) % allEntries.length;
  renderEntry(currentEntryIndex, allEntries, currentShowFrequencies, currentShowPitchAccents);
});

let selectionTimeout;
document.addEventListener('selectionchange', () => {
  clearTimeout(selectionTimeout);
  selectionTimeout = setTimeout(() => {
    const selectionObj = window.getSelection();
    if (selectionObj.rangeCount === 0 || selectionObj.isCollapsed) return;

    const range = selectionObj.getRangeAt(0);
    if (!glossaryEl.contains(range.commonAncestorContainer)) return;

    let selection = selectionObj.toString().trim();
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

  // Resolve before any DOM mutation so extractContents can't displace it
  const selectedTitle = glossaryEl.querySelector('[data-dictionary] > .selected');
  const targetDict = selectedTitle?.parentElement;

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

  if (targetDict) sendSelectedDict(targetDict);
});

