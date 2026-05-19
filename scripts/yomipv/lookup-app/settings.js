const { ipcRenderer } = require('electron');

let currentConfig = {};
let activeProfile = 'default';
let lastProfileList = [];

// Navigation
document.querySelectorAll('.nav-item').forEach(btn => {
  btn.onclick = () => {
    const sectionId = btn.dataset.section;
    document.querySelectorAll('.nav-item').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.settings-section').forEach(s => s.classList.add('hidden'));
    
    btn.classList.add('active');
    document.getElementById(`section-${sectionId}`).classList.remove('hidden');
  };
});

// Close button
document.getElementById('titlebar-close').onclick = () => {
  window.close();
};

// Toast notification
function showToast(msg) {
  const toast = document.getElementById('toast');
  toast.textContent = msg;
  toast.classList.remove('hidden');
  setTimeout(() => toast.classList.add('hidden'), 3000);
}

// Settings field rendering
const fieldConfigs = {
  general: [
    { type: 'header', label: 'Startup' },
    { key: 'auto_load', label: 'Auto-load Yomipv', type: 'checkbox' },
    { type: 'header', label: 'Profiles' },
    { type: 'profiles-manager' },
    { type: 'header', label: 'Keybindings' },
    { key: 'key_load_yomipv', label: 'Load Yomipv Manually', type: 'keybind' },
    { key: 'key_cycle_profile', label: 'Cycle Profiles', type: 'keybind' },
    { key: 'key_open_settings', label: 'Open Settings', type: 'keybind' }
  ],
  anki: [
    { type: 'header', label: 'AnkiConnect' },
    { key: 'ankiconnect_url', label: 'AnkiConnect URL', type: 'text' },
    { key: 'ankiconnect_api_key', label: 'API Key', type: 'password' },
    { key: 'ankidb_fields', label: 'Anki DB build settings', type: 'text' },
    { key: 'update_if_exists', label: 'Update if exists', type: 'checkbox', desc: 'Append media if card already exists' },
    { key: 'refresh_gui_after_update', label: 'Refresh Anki GUI', type: 'checkbox', desc: 'Reload Anki browser after export' },

    { type: 'header', label: 'Deck and Note Type' },
    { key: 'deck', label: 'Target Deck', type: 'text' },
    { key: 'note_type', label: 'Note Type', type: 'text' },

    { type: 'header', label: 'Note Type Fields' },
    { key: 'expression_field', label: 'Expression', type: 'text' },
    { key: 'expression_furigana_field', label: 'Expression Furigana', type: 'text' },
    { key: 'reading_field', label: 'Reading', type: 'text' },
    { key: 'pitch_accents_field', label: 'Pitch Accents', type: 'text' },
    { key: 'pitch_position_field', label: 'Pitch Position', type: 'text' },
    { key: 'pitch_categories_field', label: 'Pitch Categories', type: 'text' },
    { key: 'sentence_field', label: 'Sentence', type: 'text' },
    { key: 'sentence_furigana_field', label: 'Sentence Furigana', type: 'text' },
    { key: 'secondary_sentence_field', label: 'Translation Field', type: 'text' },
    { key: 'expression_audio_field', label: 'Word Audio', type: 'text' },
    { key: 'sentence_audio_field', label: 'Sentence Audio', type: 'text' },
    { key: 'selection_text_field', label: 'Selection Text', type: 'text' },
    { key: 'definition_field', label: 'Definition', type: 'text' },
    { key: 'glossary_field', label: 'Glossary', type: 'text' },
    { key: 'image_field', label: 'Image', type: 'text' },
    { key: 'freq_sort_field', label: 'Frequency Sort', type: 'text' },
    { key: 'freq_field', label: 'Frequency', type: 'text' },
    { key: 'miscinfo_field', label: 'Misc Info', type: 'text' },

    { type: 'header', label: 'Senren Exclusive' },
    { key: 'dictionary_pref_field', label: 'Dictionary Pref Field', type: 'text' },
    { key: 'dictionary_pref_value', label: 'Dictionary Pref', type: 'text' },
    { key: 'primary_sentence_wrapper', label: 'Primary Sentence Wrapper', type: 'text' },
    { key: 'secondary_sentence_wrapper', label: 'Secondary Sentence Wrapper', type: 'text' },
    { key: 'miscinfo_wrapper', label: 'Misc Info Wrapper', type: 'text' },

    { type: 'header', label: 'Note Tagging' },
    { key: 'note_tag', label: 'Note Tag', type: 'text' },

    { type: 'header', label: 'Misc Info Settings' },
    { key: 'miscinfo_episode_bullet', label: 'Use Bullet Logic', type: 'checkbox' },
    { key: 'miscinfo_show_season_one', label: 'Show Season 1 Index', type: 'checkbox' },
    { key: 'miscinfo_show_ms', label: 'Show Milliseconds', type: 'checkbox' },
    { key: 'miscinfo_episode_label', label: 'Episode Label', type: 'text' },
    { key: 'miscinfo_season_label', label: 'Season Label', type: 'text' },  
    { key: 'miscinfo_format', label: 'Format String', type: 'text' },

    { type: 'header', label: 'Media Templates' },
    { key: 'audio_template', label: 'Audio Template', type: 'text' },
    { key: 'image_template', label: 'Image Template', type: 'text' }
  ],

  yomitan: [
    { key: 'yomitan_url', label: 'Yomitan URL', type: 'text' },
    { type: 'header', label: 'Handlebars' },
    { key: 'selection_text_handlebar', label: 'Selection Handlebar', type: 'text' },
    { key: 'definition_handlebar', label: 'Definition Handlebar', type: 'text' },
    { key: 'glossary_handlebar', label: 'Glossary Handlebar', type: 'text' },
    { type: 'header', label: 'Sentence Highlight' },
    { key: 'sentence_highlight_tag', label: 'Sentence Highlight Tag', type: 'text' }
  ],

  picture: [
    { type: 'header', label: 'Picture Settings' },
    { key: 'picture_use_ffmpeg', label: 'Use FFmpeg (Picture)', type: 'checkbox' },
    { 
      key: 'picture_timestamp_source', 
      label: 'Timestamp Source', 
      type: 'select',
      options: [
        { label: 'Subtitle Start', value: 'subtitle_start' },
        { label: 'Current Position', value: 'current_position' }
      ]
    },
    { key: 'picture_animated', label: 'Capture images as animations', type: 'checkbox' },

    { type: 'header', label: 'Static Screenshot Settings' },
    { key: 'picture_static_format', label: 'Image Format', type: 'select',
      options: [
        { label: 'webp', value: 'webp'},
        { label: 'avif', value: 'avif' },
        { label: 'jpg', value: 'jpg' }
      ] 
    },
    { key: 'picture_static_quality', label: 'Image Quality', type: 'number', desc: '1-100' },
    { key: 'picture_static_width', label: 'Static Width', type: 'number' },
    { key: 'picture_static_offset', label: 'Static Offset', type: 'number' },

    { type: 'header', label: 'Animated Picture Settings' },
    { key: 'animation_format', label: 'Animation Format', type: 'select',
      options: [
        { label: 'webp', value: 'webp' },
        { label: 'avif', value: 'avif' }
      ]
    },
    { key: 'animation_quality', label: 'GIF Quality', type: 'number' },
    { key: 'animation_width', label: 'Animation Width', type: 'number' },
    { key: 'animation_fps', label: 'GIF FPS', type: 'number' },
    { key: 'animation_duration', label: 'Animation Duration', type: 'text' },
    { key: 'animation_offset', label: 'GIF Start Offset', type: 'number' },
    { key: 'animation_end_offset', label: 'GIF End Offset', type: 'number' },
    
    { type: 'header', label: 'Advanced Codec Settings' },
    { key: 'picture_webp_lossless', label: 'WebP Lossless', type: 'checkbox' },
    { key: 'picture_webp_compression', label: 'WebP Compression', type: 'number', desc: '0-6' },
    { key: 'picture_avif_cpu_used', label: 'AVIF CPU Used', type: 'number', desc: '0-8' },
  ],

  audio: [
    { key: 'audio_use_ffmpeg', label: 'Use FFmpeg (Audio)', type: 'checkbox' },
    { key: 'audio_format', label: 'Audio Format', type: 'select',
      options: [
        { label: 'opus', value: 'opus' },
        { label: 'mp3', value: 'mp3' },
        { label: 'ogg', value: 'ogg' },
        { label: 'wav', value: 'wav' }
      ]
    },
    { key: 'audio_bitrate', label: 'Audio Bitrate', type: 'text' },
    { key: 'audio_offset', label: 'Audio Start Offset', type: 'number' },
    { key: 'audio_end_offset', label: 'Audio End Offset', type: 'number' },
    { type: 'header', label: 'Misc' },
    { key: 'audio_match_volume', label: 'Match Volume', type: 'checkbox' },
    { key: 'filename_show_ms', label: 'MS in Filenames', type: 'checkbox' }
  ],

  selector: [
    { key: 'pre_tokenize', label: 'Pre-tokenize Subtitles', type: 'checkbox' },
    { key: 'selector_show_history', label: 'Show History in Selector', type: 'checkbox' },
    { key: 'selector_hide_ui', label: 'Hide Player UI', type: 'checkbox' },
    { key: 'selector_navigation_delay', label: 'Navigation Delay', type: 'number', desc: 'Input delay between repeated navigation actions' },
    { key: 'selector_trigger_on_mouse_move', label: 'Mouse Trigger', type: 'checkbox' },
    { key: 'selector_trigger_mouse_idle_time', label: 'Mouse Idle Time', type: 'number', desc: 'Seconds before trigger' },

    { type: 'header', label: 'Colorizer' },
    { key: 'colorizer_enabled', label: 'Enable Colorizer', type: 'checkbox' },
    { key: 'selector_colorize_words', label: 'Colorize Words', type: 'checkbox' },
    { key: 'selector_colorize_underline', label: 'Colorize Underline', type: 'checkbox' },
    { key: 'selector_colorize_opacity', label: 'Colorize Underline Opacity', type: 'number', desc: 'Opacity of colorized underlines from 0 to 100' },
    
    { type: 'header', label: 'Lookup Settings' },
    { key: 'selector_lookup_on_hover', label: 'Open Lookup on hover', type: 'checkbox' },
    { key: 'selector_lookup_on_navigation', label: 'Open Lookup on navigation', type: 'checkbox' },
    { key: 'selector_lookup_delay', label: 'Lookup Delay', type: 'number', desc: 'Delay before lookup opens on hover/navigation' },
    { key: 'selector_mora_hover', label: 'Mora Hover', type: 'checkbox' },
    { key: 'selector_mora_navigation', label: 'Mora Navigation', type: 'checkbox' },
    { key: 'lookup_show_frequencies', label: 'Show Frequencies', type: 'checkbox' },
    { key: 'lookup_show_pitch_accents', label: 'Show Pitch Accents', type: 'checkbox' },
    { key: 'prioritize_kanji_match', label: 'Prioritize Kanji', type: 'checkbox' },
    { key: 'prioritize_hiragana_match', label: 'Prioritize Hiragana', type: 'checkbox' },

    { type: 'header', label: 'Appearance' },
    { key: 'lookup_theme', label: 'Theme', type: 'select',
      options: [
        { label: 'Dark', value: 'dark' },
        { label: 'Light', value: 'light' }
      ]
    },

    { type: 'header', label: 'Typography' },
    { key: 'selector_font_name', label: 'Selector Font', type: 'text' },
    { key: 'selector_font_size', label: 'Selector Font Size', type: 'number' },
    { key: 'selector_line_height', label: 'Line Height', type: 'number' },

    { type: 'header', label: 'Appearance' },
    { key: 'selector_selection_underline', label: 'Underline Selection', type: 'checkbox' },
    { key: 'selector_underline_thickness', label: 'Underline Thickness', type: 'number' },
    { key: 'selector_underline_offset', label: 'Underline Offset', type: 'number' },
    { key: 'selector_border_size', label: 'Border Size', type: 'number' },
    { key: 'selector_shadow_offset', label: 'Shadow Offset', type: 'number' },

    { type: 'header', label: 'Colors' },
    { key: 'selector_color', label: 'Text Color', type: 'text' },
    { key: 'selector_selection_color', label: 'Selection Color', type: 'text' },
    { key: 'selector_lock_color', label: 'Lock Color', type: 'text' },
    { key: 'selector_persistent_color', label: 'Persistent Color', type: 'text' },
    { key: 'selector_border_color', label: 'Border Color', type: 'text' },
    { key: 'selector_shadow_color', label: 'Shadow Color', type: 'text' },
    
    { type: 'header', label: 'Layout' },
    { key: 'selector_pos_y', label: 'Vertical Position', type: 'number', desc: '0.0 - 1.0' },
    { key: 'selector_max_width_factor', label: 'Max Width Factor', type: 'number', desc: '0.0 - 1.0' },

    { type: 'header', label: 'Keybindings' },
    { key: 'key_toggle_colorizer', label: 'Toggle Colorizer', type: 'keybind' },
    { key: 'key_open_selector', label: 'Open Selector', type: 'keybind' },
    { key: 'key_selector_confirm', label: 'Selector Confirm', type: 'keybind' },
    { key: 'key_selector_cancel', label: 'Selector Cancel', type: 'keybind' },
    { key: 'key_selector_left', label: 'Selector Left', type: 'keybind' },
    { key: 'key_selector_right', label: 'Selector Right', type: 'keybind' },
    { key: 'key_selector_up', label: 'Selector Up', type: 'keybind' },
    { key: 'key_selector_down', label: 'Selector Down', type: 'keybind' },
    { key: 'key_expand_prev', label: 'Expand Prev', type: 'keybind' },
    { key: 'key_expand_next', label: 'Expand Next', type: 'keybind' },
    { key: 'key_selector_lookup', label: 'Selector Lookup', type: 'keybind' },
    { key: 'key_selector_lock', label: 'Selector Lock', type: 'keybind' },
    { key: 'key_toggle_mora_navigation', label: 'Toggle Mora Navigation', type: 'keybind' },
    { key: 'key_toggle_selector_trigger_on_mouse_move', label: 'Toggle Selector Trigger on Mouse Move', type: 'keybind' },
    { key: 'key_append_mode', label: 'Append Mode', type: 'keybind' },
    { key: 'key_set_timing_start', label: 'Set Timing Start', type: 'keybind' },
    { key: 'key_set_timing_end', label: 'Set Timing End', type: 'keybind' },
    { key: 'key_clear_timings', label: 'Clear Timings', type: 'keybind' },
    { key: 'key_build_ankidb', label: 'Build AnkiDB', type: 'keybind' },
    { key: 'key_toggle_picture_animated', label: 'Toggle Picture Animated', type: 'keybind' }
  ],

  history: [
    { key: 'history_show_secondary', label: 'Show Translations', type: 'checkbox' },
    { key: 'history_hide_volume', label: 'Hide Volume Slider', type: 'checkbox', desc: 'Hide uosc volume while panel is open' },
    { key: 'history_max_entries', label: 'Max History Entries', type: 'number' },

    { type: 'header', label: 'Size' },
    { key: 'history_width', label: 'Panel Width', type: 'number' },
    { key: 'history_max_height', label: 'Panel Max Height', type: 'text', desc: 'e.g. 60vh or 500px' },

    { type: 'header', label: 'Typography' },
    { key: 'history_font_size', label: 'Font Size', type: 'number' },
    { key: 'history_secondary_font_size', label: 'History Sub Font Size', type: 'number' },
    { key: 'history_font_family', label: 'History Font', type: 'text' },

    { type: 'header', label: 'Appearance' },
    { key: 'history_accent_color', label: 'History Accent', type: 'text' },
    { key: 'history_header_background_color', label: 'History Header BG', type: 'text' },
    { key: 'history_background_color', label: 'History BG', type: 'text' },
    { key: 'history_background_opacity', label: 'History Opacity', type: 'text' },
    { key: 'history_border_radius', label: 'History Radius', type: 'number' },

    { type: 'header', label: 'Keybindings' },
    { key: 'key_toggle_history', label: 'Toggle History', type: 'keybind' },
    { key: 'key_history_clear', label: 'Clear History', type: 'keybind' }
  ],

  subtitles: [
    { key: 'subtitle_filter_enabled', label: 'Filter Subtitles', type: 'checkbox' },

    { type: 'header', label: 'Primary Subtitle' },
    { key: 'primary_autoload', label: 'Auto-load Subs', type: 'checkbox' },
    { key: 'primary_sub_lang', label: 'Subtitle Language', type: 'text', desc: 'Preferred languages for primary subtitles' },
    { key: 'primary_sub_exclude', label: 'Excluded Keywords', type: 'text', desc: 'Skip tracks with matching keywords' },
    { key: 'auto_sync_subtitles', label: 'Auto Sync Timing', type: 'checkbox', desc: 'Automatically sync primary subtitle timing to secondary if languages match' },

    { type: 'header', label: 'Secondary Subtitle' },
    { key: 'secondary_sid', label: 'Secondary Subtitle', type: 'checkbox' },
    { key: 'secondary_on_hover', label: 'Secondary on Hover', type: 'checkbox' },
    { key: 'secondary_sub_lang', label: 'Subtitle Language', type: 'text', desc: 'Preferred languages for secondary subtitles' },
    { key: 'secondary_sub_exclude', label: 'Excluded Keywords', type: 'text', desc: 'Skip tracks with matching keywords' },

    { type: 'header', label: 'Keybindings' },
    { key: 'key_sub_seek_next', label: 'Seek Next', type: 'keybind', desc: 'Jump to next subtitle line' },
    { key: 'key_sub_seek_prev', label: 'Seek Previous', type: 'keybind', desc: 'Jump to previous subtitle line' },
    { key: 'key_secondary_sub_next', label: 'Next Secondary Sub', type: 'keybind' },
    { key: 'key_secondary_sub_prev', label: 'Previous Secondary Sub', type: 'keybind' },
    { key: 'key_sync_subtitles', label: 'Sync Subtitles', type: 'keybind', desc: 'Sync primary subtitle timing to secondary if languages match' }
  ],

  anilist: [
    { key: 'anilist_enabled', label: 'Enable AniList', type: 'checkbox' },
    { key: 'anilist_token', label: 'AniList Token', type: 'password' },
    { key: 'anilist_update_thresh_percent', label: 'AniList Threshold', type: 'number', desc: '80-100' },
    { key: 'anilist_show_notifications', label: 'AniList OSD', type: 'checkbox' },

    { type: 'header', label: 'Keybindings' },
    { key: 'key_anilist_auth', label: 'AniList Auth', type: 'keybind' }
  ],

  updater: [
    { key: 'updater_enabled', label: 'Enable Updater', type: 'checkbox' },
    { key: 'updater_check_on_startup', label: 'Check for Updates', type: 'checkbox' },
    { key: 'updater_use_source', label: 'Update from Source', type: 'checkbox' },

    { type: 'header', label: 'Keybindings' },
    { key: 'key_update', label: 'Update', type: 'keybind' }
  ],

  mpv: [
    { key: 'osd_messages', label: 'Show OSD Messages', type: 'checkbox' }
  ]
};

function renderFields() {
  Object.keys(fieldConfigs).forEach(section => {
    const container = document.getElementById(`fields-${section}`);
    if (!container) return;
    
    container.innerHTML = '';
    fieldConfigs[section].forEach(conf => {
      const fieldEl = document.createElement('div');
      fieldEl.className = 'field';
      
      const val = currentConfig[conf.key];
      
      if (conf.type === 'header') {
        fieldEl.className = 'field-section-header';
        fieldEl.textContent = conf.label;
      } else if (conf.type === 'profiles-manager') {
        fieldEl.className = 'profiles-manager-container';
        fieldEl.innerHTML = `
          <div id="profile-list" class="profile-list"></div>
          <div class="profile-create">
            <label for="new-profile-name">Create profile</label>
            <div class="input-row">
              <input id="new-profile-name" type="text" spellcheck="false">
              <button id="btn-create-profile" class="btn-primary">Create</button>
            </div>
            <p class="hint">
              Creates <code>script-opts/yomipv_<em>&lt;name&gt;</em>.conf</code> as a copy of the current config.
            </p>
          </div>
        `;
        
        // Wait for DOM attachment
        setTimeout(() => {
          const refreshBtn = document.getElementById('btn-refresh-profiles');
          const createBtn = document.getElementById('btn-create-profile');
          if (refreshBtn) refreshBtn.onclick = () => ipcRenderer.send('profile-list-request');
          if (createBtn) {
            createBtn.onclick = () => {
              const input = document.getElementById('new-profile-name');
              const rawName = input.value.trim();
              const name = rawName.toLowerCase().replace(/[^a-z0-9_-]/g, '');
              if (!rawName) { showToast('Please enter a name'); return; }
              if (!name) { showToast('Invalid name'); return; }
              ipcRenderer.send('profile-create', name);
              input.value = '';
              showToast(`Creating profile: ${name}`);
            };
          }
          renderProfiles();
        }, 0);
      } else if (conf.type === 'checkbox') {
        fieldEl.innerHTML = `
          <div class="field-label"></div>
          <div class="checkbox-container">
            <input type="checkbox" id="field-${conf.key}">
          </div>
          <div class="field-desc"></div>
        `;
        const input = fieldEl.querySelector('input');
        input.checked = !!val;
        input.onchange = (e) => updateSetting(conf.key, e.target.checked);
        fieldEl.querySelector('.field-label').textContent = conf.label;
        if (conf.desc) fieldEl.querySelector('.field-desc').textContent = conf.desc;
        else fieldEl.querySelector('.field-desc').remove();
      } else if (conf.type === 'select') {
        fieldEl.innerHTML = `
          <div class="field-label"></div>
          <div class="field-input-row">
            <select id="field-${conf.key}"></select>
          </div>
          <div class="field-desc"></div>
        `;
        const select = fieldEl.querySelector('select');
        conf.options.forEach(opt => {
          const option = document.createElement('option');
          option.value = opt.value;
          option.textContent = opt.label;
          select.appendChild(option);
        });
        select.value = val;
        select.onchange = (e) => updateSetting(conf.key, e.target.value);
        fieldEl.querySelector('.field-label').textContent = conf.label;
        if (conf.desc) fieldEl.querySelector('.field-desc').textContent = conf.desc;
        else fieldEl.querySelector('.field-desc').remove();
      } else if (conf.type === 'keybind') {
        fieldEl.innerHTML = `
          <div class="field-label"></div>
          <div class="field-input-row">
            <input type="text" class="keybind-input" id="field-${conf.key}" readonly placeholder="Click to record...">
          </div>
          <div class="field-desc"></div>
        `;
        const input = fieldEl.querySelector('input');
        input.value = (val !== undefined && val !== null) ? val : '';
        
        input.onclick = () => {
          if (input.classList.contains('recording')) return;
          
          input.value = 'Press key...';
          input.classList.add('recording');
          
          const onKeydown = (e) => {
            e.preventDefault();
            e.stopPropagation();
            
            let key = e.key;
            if (['Control', 'Shift', 'Alt', 'Meta'].includes(key)) return;

            const keyMap = {
              'ArrowUp': 'UP',
              'ArrowDown': 'DOWN',
              'ArrowLeft': 'LEFT',
              'ArrowRight': 'RIGHT',
              'Enter': 'ENTER',
              'Escape': 'ESC',
              ' ': 'SPACE',
              'Backspace': 'BS',
              'Delete': 'DEL',
              'Insert': 'INS',
              'Home': 'HOME',
              'End': 'END',
              'PageUp': 'PGUP',
              'PageDown': 'PGDWN',
              'Tab': 'TAB'
            };
            
            if (keyMap[key]) key = keyMap[key];
            else if (key.length > 1) key = key.toUpperCase();

            let mods = [];
            if (e.ctrlKey) mods.push('Ctrl');
            if (e.altKey) mods.push('Alt');
            if (e.shiftKey) mods.push('Shift');
            
            const combo = mods.length > 0 ? mods.join('+') + '+' + key : key;
            
            input.value = combo;
            input.classList.remove('recording');
            updateSetting(conf.key, combo);
            window.removeEventListener('keydown', onKeydown, true);
          };
          
          window.addEventListener('keydown', onKeydown, true);
        };

        fieldEl.querySelector('.field-label').textContent = conf.label;
        if (conf.desc) fieldEl.querySelector('.field-desc').textContent = conf.desc;
        else fieldEl.querySelector('.field-desc').remove();
      } else {
        fieldEl.innerHTML = `
          <div class="field-label"></div>
          <div class="field-input-row">
            <input type="${conf.type}" id="field-${conf.key}" spellcheck="false">
          </div>
          <div class="field-desc"></div>
        `;
        const input = fieldEl.querySelector('input');
        input.value = (val !== undefined && val !== null) ? val : '';
        input.onblur = (e) => updateSetting(conf.key, e.target.value);
        fieldEl.querySelector('.field-label').textContent = conf.label;
        if (conf.desc) fieldEl.querySelector('.field-desc').textContent = conf.desc;
        else fieldEl.querySelector('.field-desc').remove();
      }
      
      container.appendChild(fieldEl);
    });
  });
}

function updateSetting(key, val) {
  ipcRenderer.send('settings-set', { key, value: val });
  currentConfig[key] = val;
  showToast('Setting saved');
}

// Profile logic
function renderProfiles(profiles) {
  if (profiles) lastProfileList = profiles;
  const container = document.getElementById('profile-list');
  if (!container) return;
  container.innerHTML = '';
  
  const profilesToRender = lastProfileList;
  const baseCard = document.createElement('div');
  baseCard.className = `profile-card ${activeProfile === 'default' ? 'active' : ''}`;
  baseCard.innerHTML = `
    <div class="profile-name">Default (yomipv.conf)</div>
    <div class="profile-actions">
      <button class="btn-primary btn-switch" ${activeProfile === 'default' ? 'disabled' : ''}>Switch</button>
    </div>
  `;
  baseCard.querySelector('.btn-switch').onclick = () => switchProfile('default');
  container.appendChild(baseCard);
  
  // External profiles
  profilesToRender.forEach(name => {
    const card = document.createElement('div');
    card.className = `profile-card ${activeProfile === name ? 'active' : ''}`;
    card.innerHTML = `
      <div class="profile-name">${name}</div>
      <div class="profile-actions">
        <button class="btn-primary btn-switch" ${activeProfile === name ? 'disabled' : ''}>Switch</button>
        <button class="btn-danger btn-delete">Delete</button>
      </div>
    `;
    card.querySelector('.btn-switch').onclick = () => switchProfile(name);
    card.querySelector('.btn-delete').onclick = () => deleteProfile(name);
    container.appendChild(card);
  });
}

function switchProfile(name) {
  ipcRenderer.send('profile-switch', name);
  showToast(`Switching to profile: ${name}`);
}

function deleteProfile(name) {
  if (confirm(`Delete profile "${name}"? This will remove yomipv_${name}.conf.`)) {
    ipcRenderer.send('profile-delete', name);
  }
}


// IPC listeners
ipcRenderer.on('settings-data', (event, data) => {
  if (data && data.config) {
    currentConfig = data.config;
    activeProfile = data.config.current_profile || 'default';
    renderFields();
    renderProfiles(); // Re-render profiles to update highlight
  }
});

ipcRenderer.on('profile-list', (event, profiles) => {
  renderProfiles(profiles);
});

// Initialization
renderFields();
ipcRenderer.send('settings-window-ready');
ipcRenderer.send('profile-list-request');
