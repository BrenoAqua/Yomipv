const { ipcRenderer } = require('electron');

const glossaryEl = document.getElementById('glossary-content');
const headerEl = document.getElementById('term-header');

ipcRenderer.on('lookup-term', async (event, data) => {
  console.log('[IPC] Received lookup data:', JSON.stringify(data));

  const renderHeader = (term, reading, furigana) => {
    const cleanTerm = (term || '').trim();
    console.log(`[UI] Rendering header: term="${cleanTerm}"`);

    if (furigana && furigana.includes('[')) {
      // Parse Yomitan format: 敵[かな]わない -> <ruby>敵<rt>かな</rt></ruby>わない
      const rubyHtml = furigana.replace(/([^\[\]]+)\[([^\[\]]+)\]/g, '<ruby>$1<rt>$2</rt></ruby>');
      headerEl.innerHTML = `
        <div class="term-display">
          ${rubyHtml}
        </div>
      `;
    } else if (reading && reading !== cleanTerm) {
      headerEl.innerHTML = `
        <div class="term-display">
          <ruby>
            ${cleanTerm}
            <rt>${reading}</rt>
          </ruby>
        </div>
      `;
    } else {
      headerEl.innerHTML = `
        <div class="term-display">
          <div class="term-expression">${cleanTerm}</div>
        </div>
      `;
    }
  };

  renderHeader(data.term, data.reading);

  glossaryEl.innerHTML = '<div class="loading">Looking up...</div>';

  try {
    console.log('Sending request for:', data.term);
    
    let result;
    const endpoints = [`http://127.0.0.1:19633/ankiFields`, `http://127.0.0.1:19633/api/ankiFields`];
    
    for (const url of endpoints) {
      try {
        console.log(`Trying endpoint: ${url}`);
        const response = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            text: data.term,
            type: 'term',
            markers: ['glossary', 'expression', 'reading', 'furigana', 'pitch-accent-categories', 'pitch-accents'],
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

    if (!result) {
      throw new Error('All Yomitan endpoints failed');
    }

    console.log('API Result:', result);

    const entries = (result && result.fields) || (result && result[0] && result[0].fields) || [];
    
    let fields = null;
    if (Array.isArray(entries) && entries.length > 0) {
      // Prioritize entries with pitch accent or kanji
      fields = entries.find(e => (e['pitch-accents'] && e['pitch-accents'] !== '') || (e.expression && e.expression !== e.reading)) || entries[0];
    } else if (entries && !Array.isArray(entries)) {
      fields = entries;
    }

    if (fields && (fields.glossary || fields.definition)) {
      const term = fields.expression || data.term;
      const furigana = fields.furigana || '';
      
      let reading = fields.reading || data.reading;
      const pitchAccents = fields['pitch-accents'] || '';
      
      if (pitchAccents) {
        const tempPitch = document.createElement('div');
        tempPitch.innerHTML = pitchAccents;
        const firstPitch = tempPitch.querySelector('li');
        if (firstPitch) {
          reading = firstPitch.innerHTML;
          console.log('[UI] Using pitch accent for reading');
        }
      }

      renderHeader(term, reading, furigana);

      const pitchTarget = fields['pitch-accent-categories'] || '';
      console.log(`[UI] Pitch accent categories: "${pitchTarget}"`);
      
      const pitchColors = {
        'atamadaka': 'var(--pitch-red)',
        'heiban': 'var(--pitch-blue)',
        'nakadaka': 'var(--pitch-orange)',
        'odaka': 'var(--pitch-green)',
        'kifuku': 'var(--pitch-purple)'
      };

      const firstPitch = pitchTarget.split(/[\s,]+/).find(p => pitchColors[p.toLowerCase()]);
      
      if (firstPitch) {
        const color = pitchColors[firstPitch.toLowerCase()];
        console.log(`[UI] Applying pitch color: ${firstPitch} -> ${color}`);
        headerEl.style.setProperty('--pitch-accent-color', color);
      } else {
        headerEl.style.removeProperty('--pitch-accent-color');
      }

      let content = fields.glossary || fields.definition;
      
      const tempDiv = document.createElement('div');
      tempDiv.innerHTML = content;
      tempDiv.querySelectorAll('img').forEach(img => img.remove());
      
      // Merge Jitendex entries while preserving sense structure
      tempDiv.querySelectorAll('[data-dictionary*="Jitendex"]').forEach(dictEl => {
        dictEl.querySelectorAll('[data-sc-content="glossary"]').forEach(glossaryEl => {
          const children = Array.from(glossaryEl.childNodes);
          const definitions = [];
          
          children.forEach(node => {
            const isText = node.nodeType === Node.TEXT_NODE && node.textContent.trim().length > 0;
            const isElement = node.nodeType === Node.ELEMENT_NODE && !node.matches('span[data-details]');
            
            if (isText || isElement) {
              // Strip sense markers from node start
              let text = node.textContent;
              if (text.match(/^[①-⑳]/)) {
                text = text.replace(/^[①-⑳]\s*/, '');
                if (isText) {
                  node.textContent = text;
                } else {
                  node.innerText = text;
                }
              }
              
              if (text.trim().length > 0) {
                definitions.push(node);
              }
            }
          });
        });

        dictEl.querySelectorAll('li').forEach(li => {
          li.style.listStyle = 'none';
        });
      });

      glossaryEl.innerHTML = tempDiv.innerHTML;

      // Disable links and pointer events
      glossaryEl.querySelectorAll('a, [data-link]').forEach(el => {
        el.onclick = (e) => e.preventDefault();
        el.style.pointerEvents = 'none';
        el.style.cursor = 'default';
      });

      // Strip parentheses from dictionary titles
      glossaryEl.querySelectorAll('[data-dictionary]').forEach(el => {
        const titleEl = el.firstElementChild;
        if (titleEl) {
          titleEl.textContent = titleEl.textContent.replace(/[()]/g, '').trim();
        }
      });
    } else {
      glossaryEl.innerHTML = `No result found for "${data.term}".`;
    }

    glossaryEl.querySelectorAll('[data-dictionary]').forEach(el => {
      const titleEl = el.firstElementChild;
      if (titleEl) {
        titleEl.style.cursor = 'pointer';
        
        titleEl.addEventListener('click', (e) => {
          e.stopPropagation();

          glossaryEl.querySelectorAll('[data-dictionary] > *:first-child').forEach(child => {
            child.classList.remove('selected');
          });

          titleEl.classList.add('selected');
          
          const dictionaryHtml = el.outerHTML;
          let styleHtml = '';
          const styleEl = glossaryEl.querySelector('style');
          if (styleEl) {
            styleHtml = styleEl.outerHTML;
          }
          
          // Reconstruct glossary structure for single dictionary
          const dictContent = `<div class="yomitan-glossary" style="text-align: left;"><ol>${dictionaryHtml}</ol></div>${styleHtml}`;
          console.log('[UI] Dictionary selected:', el.getAttribute('data-dictionary'));
          
          ipcRenderer.send('dictionary-selected', dictContent);
        });
      }
    });
  } catch (e) {
    console.error('Lookup failed', e);
    glossaryEl.innerHTML = `Error fetching from Yomitan: ${e.message}`;
  }
});

document.addEventListener('selectionchange', () => {
  let selection = window.getSelection().toString().trim();
  // Convert newlines to <br> tags
  selection = selection.replace(/\r?\n/g, '<br>');
  console.log('[UI] selectionchange:', selection);
  ipcRenderer.send('sync-selection', selection);
});

document.addEventListener('mouseup', () => {
  const selection = window.getSelection();
  if (selection.rangeCount > 0 && !selection.isCollapsed) {
    const range = selection.getRangeAt(0);
    const startRuby = range.startContainer.parentElement?.closest('ruby');
    const endRuby = range.endContainer.parentElement?.closest('ruby');

    if (startRuby || endRuby) {
      console.log('[UI] Ruby detected in selection, expanding...');
      if (startRuby) range.setStartBefore(startRuby);
      if (endRuby) range.setEndAfter(endRuby);
      
      selection.removeAllRanges();
      selection.addRange(range);
    }

    const span = document.createElement('span');
    span.className = 'highlight';
    try {
      range.surroundContents(span);
    } catch (e) {
      // Fallback if selection crosses complex boundaries
      span.appendChild(range.extractContents());
      range.insertNode(span);
    }

    // Update main process with modified HTML
    const selectedTitle = glossaryEl.querySelector('[data-dictionary] > .selected');
    if (selectedTitle) {
      const dictEl = selectedTitle.parentElement;
      const dictionaryHtml = dictEl.outerHTML;
      
      let styleHtml = '';
      const styleEl = glossaryEl.querySelector('style');
      if (styleEl) {
        styleHtml = styleEl.outerHTML;
      }
      
      const dictContent = `<div class="yomitan-glossary" style="text-align: left;"><ol>${dictionaryHtml}</ol></div>${styleHtml}`;
      console.log('[UI] Updating selected dictionary with bold text');
      ipcRenderer.send('dictionary-selected', dictContent);
    }
  }
});
