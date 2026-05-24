const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage } = require('electron');
const path = require('path');
const http = require('http');
const net = require('net');

let mainWindow;
let historyWindow = null;
let settingsWindow = null;
let pendingHide = false;
let historyHideTimeout = null;
let lastSelectedDictHtml = '';
let tray = null;

let lookupSuspended = false;
let lookupSuspendTimeout = null;

const appIconPath = path.join(__dirname, 'build', 'lookup-app.png');

let isContextMenuOpen = false;
let appIsFocused = true;

// Verify lookup window inspector or detached tools state
function isMainDevToolsOpen() {
  const isDevToolsAlive = typeof devToolsWin !== 'undefined' && devToolsWin && !devToolsWin.isDestroyed();
  return isDevToolsAlive || (mainWindow && mainWindow.webContents.isDevToolsOpened());
}

// Verify history panel internal inspector state
function isHistoryDevToolsOpen() {
  return !!(historyWindow && historyWindow.webContents.isDevToolsOpened());
}

let mpvIpcQueue = [];

// Sends JSON command to mpv IPC pipe
function sendMpvMessage(message, ...args) {
  if (mpvIpc) {
    const cmd = { command: [message, ...args] };
    mpvIpc.write(JSON.stringify(cmd) + '\n');
  } else {
    console.warn(`[IPC] Queuing ${message}: mpvIpc not connected`);
    mpvIpcQueue.push([message, ...args]);
  }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 850,
    height: 480,
    frame: false,
    transparent: true,
    show: false,
    skipTaskbar: true,
    focusable: false,
    resizable: false,
    minimizable: false,
    maximizable: false,
    alwaysOnTop: true,
    type: 'toolbar', 
    icon: appIconPath,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  mainWindow.setAlwaysOnTop(true, 'screen-saver', 1);
  mainWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  if (process.platform === 'darwin') {
    mainWindow.setWindowButtonVisibility(false);
  }
  mainWindow.loadFile('index.html');
  mainWindow.webContents.on('context-menu', (e) => {
    e.preventDefault();
  });
}

function createHistoryWindow() {
  const { screen } = require('electron');
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width, height } = primaryDisplay.workAreaSize;
  const historyWidth = 420;
  
  historyWindow = new BrowserWindow({
    width: historyWidth,
    height: height,
    x: width - historyWidth,
    y: 0,
    frame: false,
    transparent: true,
    show: false,
    skipTaskbar: true,
    focusable: false,
    resizable: false,
    minimizable: false,
    maximizable: false,
    alwaysOnTop: true,
    type: 'toolbar',
    icon: appIconPath,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  historyWindow.setIgnoreMouseEvents(true, { forward: true });

  historyWindow.setAlwaysOnTop(true, 'screen-saver', 1);
  historyWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  historyWindow.loadFile('history.html');
}

function createSettingsWindow() {
  if (settingsWindow) {
    settingsWindow.show();
    settingsWindow.focus();
    return;
  }

  settingsWindow = new BrowserWindow({
    width: 900,
    height: 700,
    frame: false,
    show: false,
    alwaysOnTop: true,
    icon: appIconPath,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  settingsWindow.setAlwaysOnTop(true, 'screen-saver', 1);
  settingsWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  settingsWindow.loadFile('settings.html');
  settingsWindow.once('ready-to-show', () => settingsWindow.show());
  settingsWindow.on('closed', () => settingsWindow = null);
}

function createTray() {
  const iconPath = path.join(__dirname, 'build', 'lookup-app.png');
  const icon = nativeImage.createFromPath(iconPath).resize({ width: 16, height: 16 });
  tray = new Tray(icon);
  const contextMenu = Menu.buildFromTemplate([
    { label: 'Yomipv Lookup', enabled: false },
    { type: 'separator' },
    { label: 'Settings', click: () => createSettingsWindow() },
    { label: 'History', click: () => sendMpvMessage('script-message', 'yomipv-toggle-history') },
    { type: 'separator' },
    { label: 'Quit', click: () => app.quit() }
  ]);
  tray.setToolTip('Yomipv');
  tray.setContextMenu(contextMenu);
  tray.on('double-click', () => createSettingsWindow());
}

// mpv IPC pipe path from CLI argument
const ipcPipeArg = process.argv.find(arg => arg.startsWith('--ipc-pipe='));
const ipcPipe = ipcPipeArg ? ipcPipeArg.split('=')[1] : null;

let mpvIpc = null;
if (ipcPipe) {
  try {
    console.log('[IPC] Connecting to:', ipcPipe);
    mpvIpc = net.connect(ipcPipe, () => {
      console.log('[IPC] Connected to mpv');
      while (mpvIpcQueue.length > 0) {
        const [msg, ...args] = mpvIpcQueue.shift();
        sendMpvMessage(msg, ...args);
      }
    });
    mpvIpc.on('error', (err) => {
      console.warn('[IPC] mpv connection error:', err.message);
      mpvIpc = null;
    });
    mpvIpc.on('close', () => {
      console.log('[IPC] mpv connection closed');
      mpvIpc = null;
    });
  } catch (e) {
    console.error('[IPC] Failed to connect:', e.message);
  }
}

app.whenReady().then(() => {
  if (process.platform === 'win32') {
    app.setAppUserModelId('com.yomipv.lookup');
  }
  createWindow();
  createHistoryWindow();
  createTray();

  // HTTP server for terms and commands from mpv Lua
  const server = http.createServer((req, res) => {
    console.log(`[IPC] Request: ${req.method} ${req.url}`);
    
    if (req.method === 'GET' && req.url === '/selected-dictionary-html') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(lastSelectedDictHtml);
      return;
    }

    if (req.method === 'POST') {
      let body = '';
      req.on('data', chunk => {
        body += chunk.toString();
      });
      req.on('end', () => {
        if (req.url === '/shutdown') {
          console.log('[IPC] Shutdown signal received');
          res.end('closing');
          
          if (mpvIpc) {
            mpvIpc.destroy();
            mpvIpc = null;
          }
          
          setTimeout(() => {
            console.log('[INFO] Quitting app via shutdown signal');
            app.quit();
          }, 100);
          return;
        }

        if (req.url === '/copy') {
          console.log('[IPC] Copy signal received');
          res.end('ok');
          if (mainWindow) {
            mainWindow.webContents.send('copy-selection');
          }
          if (historyWindow) {
            historyWindow.webContents.send('copy-selection');
          }
          return;
        }

        if (req.url === '/hide') {
          console.log('[IPC] Hide signal received, requesting renderer clear');
          res.end('hiding');
          
          if (isMainDevToolsOpen()) return;
          
          if (mainWindow) {
            pendingHide = true;
            mainWindow.webContents.send('window-hide-request');
          }
          return;
        }

        if (req.url === '/settings-open') {
          console.log('[IPC] Settings open signal received');
          res.end('ok');
          createSettingsWindow();
          return;
        }

        if (req.url === '/history-show') {
          console.log('[IPC] History show signal received');
          res.end('ok');
          if (historyHideTimeout) {
            clearTimeout(historyHideTimeout);
            historyHideTimeout = null;
          }
          if (historyWindow) {
            historyWindow.showInactive();
            historyWindow.webContents.send('show-history');
          }
          return;
        }

        if (req.url === '/history-hide') {
          console.log('[IPC] History hide signal received');
          res.end('ok');
          
          if (isHistoryDevToolsOpen()) return;

          if (historyHideTimeout) {
            clearTimeout(historyHideTimeout);
          }
          if (historyWindow) {
            historyWindow.webContents.send('hide-history');
            historyHideTimeout = setTimeout(() => {
              if (historyWindow && !historyWindow.isDestroyed()) {
                historyWindow.hide();
              }
              historyHideTimeout = null;
            }, 450);
          }
          return;
        }

        if (req.url === '/history') {
          console.log('[IPC] History payload received');
          try {
            const data = JSON.parse(body);
            if (historyWindow && data.config && data.config.history_width) {
              const [w, h] = historyWindow.getSize();
              const [x, y] = historyWindow.getPosition();
              const newW = parseInt(data.config.history_width) + 40; // Padding for shadow
              if (w !== newW) {
                const { screen } = require('electron');
                const primaryDisplay = screen.getPrimaryDisplay();
                const { width: screenWidth } = primaryDisplay.workAreaSize;
                historyWindow.setBounds({
                  x: screenWidth - newW,
                  y: y,
                  width: newW,
                  height: h
                });
              }
            }
            if (historyWindow) {
              historyWindow.webContents.send('update-history', data);
            }
          } catch (e) {
            console.error('Failed to parse history body', e);
          }
          res.end('ok');
          return;
        }

        if (req.url === '/settings-data') {
          console.log('[IPC] Settings data received');
          try {
            const data = JSON.parse(body);
            if (settingsWindow) {
              settingsWindow.webContents.send('settings-data', data);
            }
          } catch (e) {
            console.error('Failed to parse settings body', e);
          }
          res.end('ok');
          return;
        }

        if (req.url === '/profile-list-data') {
          console.log('[IPC] Profile list received');
          try {
            const data = JSON.parse(body);
            if (settingsWindow) {
              settingsWindow.webContents.send('profile-list', data);
            }
          } catch (e) {
            console.error('Failed to parse profile list body', e);
          }
          res.end('ok');
          return;
        }

        if (req.url.startsWith('/app-focus')) {
          const stateStr = new URL(req.url, 'http://localhost').searchParams.get('state');
          appIsFocused = stateStr === 'true';
          
          if (stateStr === 'false') {
            if (!isMainDevToolsOpen() && !isContextMenuOpen && mainWindow && mainWindow.isVisible() && !pendingHide) {
              lookupSuspended = true;
              mainWindow.webContents.send('window-suspend-request');
            }
          } else if (stateStr === 'true') {
            if (lookupSuspended && mainWindow) {
              lookupSuspended = false;
              if (lookupSuspendTimeout) {
                clearTimeout(lookupSuspendTimeout);
                lookupSuspendTimeout = null;
              }
              if (!mainWindow.isVisible()) {
                mainWindow.showInactive();
              }
              mainWindow.webContents.send('window-resume-request');
            }
          }
          res.end('ok');
          return;
        }

        try {
          const data = JSON.parse(body);
          if (data.term) {
            console.log('[IPC] Lookup for:', data.term);
            if (!appIsFocused && !isMainDevToolsOpen()) {
              console.log('[IPC] Ignoring lookup while mpv is unfocused');
              res.end('ok');
              return;
            }
            pendingHide = false;
            if (mainWindow) {
              mainWindow.webContents.send('lookup-term', data);
            }
          }
        } catch (e) {
          console.error('Failed to parse request body', e);
        }
        res.end('ok');
      });
    } else {
      res.end('ready');
    }
  });

  server.on('error', (e) => {
    if (e.code === 'EADDRINUSE') {
      console.log('Address in use, exiting...');
      app.quit();
    }
  });

  server.listen(19634, '127.0.0.1', () => {
    console.log('Lookup IPC server listening on 19634');
  });

  // Monitor parent PID
  const parentPidArg = process.argv.find(arg => arg.startsWith('--parent-pid='));
  const parentPid = parentPidArg ? parseInt(parentPidArg.split('=')[1]) : null;

  if (parentPid && !isNaN(parentPid)) {
    console.log(`[INFO] Monitoring parent PID: ${parentPid}`);
    setInterval(() => {
      try {
        process.kill(parentPid, 0);
      } catch (e) {
        console.log('[INFO] Parent process died, shutting down...');
        if (mpvIpc) {
          mpvIpc.destroy();
          mpvIpc = null;
        }
        app.quit();
      }
    }, 500);
  }
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

ipcMain.on('hide-window', () => {
  mainWindow.hide();
});

ipcMain.on('move-window', (event, { dx, dy }) => {
  if (!mainWindow) return;
  const [x, y] = mainWindow.getPosition();
  mainWindow.setPosition(x + dx, y + dy);
});

let devToolsWin = null;

let inspectorTray = null;

function createInspectorTray() {
  const iconPath = path.join(__dirname, 'build', 'lookup-app.png');
  const icon = nativeImage.createFromPath(iconPath).resize({ width: 16, height: 16 });
  inspectorTray = new Tray(icon);
  inspectorTray.setToolTip('Yomipv Inspector');

  const updateMenu = () => {
    const menu = Menu.buildFromTemplate([
      {
        label: 'Show Inspector',
        click: () => {
          if (devToolsWin) {
            if (devToolsWin.isMinimized()) devToolsWin.restore();
            devToolsWin.show();
            devToolsWin.focus();
          }
        }
      },
      {
        label: 'Close Inspector',
        click: () => {
          if (devToolsWin && !devToolsWin.isDestroyed()) devToolsWin.close();
        }
      }
    ]);
    inspectorTray.setContextMenu(menu);
  };

  updateMenu();
  inspectorTray.on('click', () => {
    if (devToolsWin) {
      if (devToolsWin.isMinimized()) devToolsWin.restore();
      devToolsWin.show();
      devToolsWin.focus();
    }
  });
}

function destroyInspectorTray() {
  if (inspectorTray) {
    inspectorTray.destroy();
    inspectorTray = null;
  }
}

function openInspector() {
  if (!mainWindow) return;
  
  if (devToolsWin && !devToolsWin.isDestroyed()) {
    if (devToolsWin.isMinimized()) devToolsWin.restore();
    devToolsWin.show();
    devToolsWin.focus();
    return;
  }

  devToolsWin = new BrowserWindow({
    width: 800,
    height: 600,
    title: "Yomipv Inspector",
    alwaysOnTop: true,
    skipTaskbar: false,
    autoHideMenuBar: true
  });

  devToolsWin.setAlwaysOnTop(true, 'screen-saver', 2);

  mainWindow.webContents.setDevToolsWebContents(devToolsWin.webContents);
  mainWindow.webContents.openDevTools({ mode: 'detach' });

  // Restore lookup window visibility if suspended before opening inspector
  if (lookupSuspended && mainWindow) {
    lookupSuspended = false;
    if (lookupSuspendTimeout) {
      clearTimeout(lookupSuspendTimeout);
      lookupSuspendTimeout = null;
    }
    if (!mainWindow.isVisible()) {
      mainWindow.showInactive();
    }
    mainWindow.webContents.send('window-resume-request');
  }

  devToolsWin.webContents.once('dom-ready', () => {
    devToolsWin.webContents.executeJavaScript(
      "UI.inspectorView.showPanel('elements')"
    ).catch(() => {});
  });

  // Enable manual window repositioning during inspection
  mainWindow.setMovable(true);
  mainWindow.setFocusable(true);
  mainWindow.webContents.send('inspector-mode', true);

  const savedPosition = mainWindow.getPosition();

  createInspectorTray();

  const onInspectorClose = () => {
    destroyInspectorTray();
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.setPosition(savedPosition[0], savedPosition[1]);
      mainWindow.setMovable(false);
      mainWindow.setFocusable(false);
      mainWindow.webContents.send('inspector-mode', false);
    }

    if (!appIsFocused) {
      if (mainWindow && mainWindow.isVisible() && !pendingHide && !lookupSuspended) {
        lookupSuspended = true;
        mainWindow.webContents.send('window-suspend-request');
      }
    }
  };

  mainWindow.webContents.once('devtools-closed', () => {
    onInspectorClose();
    if (devToolsWin && !devToolsWin.isDestroyed()) {
      devToolsWin.close();
    }
    devToolsWin = null;
  });

  devToolsWin.on('closed', () => {
    onInspectorClose();
    if (mainWindow && !mainWindow.isDestroyed() && mainWindow.webContents.isDevToolsOpened()) {
      mainWindow.webContents.closeDevTools();
    }
    devToolsWin = null;
  });
}

ipcMain.on('open-inspector', () => {
  openInspector();
});

ipcMain.on('show-context-menu', (event, hasSelection) => {
  const isHistory = historyWindow && event.sender === historyWindow.webContents;
  const copyItem = {
    label: 'Copy',
    enabled: hasSelection,
    click: () => {
      event.sender.send('copy-selection');
    }
  };

  const template = isHistory ? [copyItem] : [
    copyItem,
    { type: 'separator' },
    {
      label: 'Inspect Element',
      click: () => {
        openInspector();
      }
    },
    {
      label: 'Refresh CSS',
      click: () => {
        event.sender.send('refresh-css');
      }
    }
  ];
  const menu = Menu.buildFromTemplate(template);
  
  menu.on('menu-will-show', () => { isContextMenuOpen = true; });
  menu.on('menu-will-close', () => { 
    setTimeout(() => { isContextMenuOpen = false; }, 300);
  });
  
  menu.popup(BrowserWindow.fromWebContents(event.sender));
});

ipcMain.on('sync-selection', (event, text) => {
  console.log('[IPC] sync-selection received:', text);
  sendMpvMessage('script-message', 'yomipv-sync-selection', text);
});

ipcMain.on('dictionary-selected', (event, content) => {
  console.log('[IPC] dictionary-selected received');
  lastSelectedDictHtml = content;
  sendMpvMessage('script-message', 'yomipv-dictionary-selected', 'HTTP_FETCH');
});

ipcMain.on('active-entry', (event, data) => {
  if (data) {
    sendMpvMessage('script-message', 'yomipv-active-entry', data.expression || '', data.reading || '');
  }
});

ipcMain.on('show-window', () => {
  if (mainWindow) {
    console.log('[IPC] show-window signal received');
    if (!appIsFocused && !isMainDevToolsOpen()) {
      console.log('[IPC] show-window ignored: mpv is unfocused');
      return;
    }
    pendingHide = false;
    if (!mainWindow.isVisible()) {
      console.log('[IPC] window is hidden, showing inactive');
      mainWindow.showInactive();
    }
  }
});

ipcMain.on('window-hide-confirmed', () => {
  if (mainWindow && pendingHide) {
    console.log('[IPC] Hide confirmed by renderer, hiding window');
    // Defer hiding to ensure frame synchronization and prevent flicker
    setTimeout(() => {
      if (mainWindow && pendingHide && !mainWindow.isDestroyed()) {
        mainWindow.hide();
        pendingHide = false;
      }
    }, 450);
  } else {
    console.log('[IPC] Hide confirmed but ignored (new lookup pending)');
  }
});

ipcMain.on('window-suspend-confirmed', () => {
  if (mainWindow && lookupSuspended) {
    lookupSuspendTimeout = setTimeout(() => {
      if (mainWindow && lookupSuspended && !mainWindow.isDestroyed()) {
        mainWindow.hide();
      }
      lookupSuspendTimeout = null;
    }, 450);
  }
});

// History IPC Actions to pass down to MPV
ipcMain.on('history-jump', (event, time) => {
  sendMpvMessage('script-message', 'yomipv-history-jump', time.toString());
});

ipcMain.on('history-expand', (event, entry) => {
  sendMpvMessage('script-message', 'yomipv-history-expand', JSON.stringify(entry));
});

ipcMain.on('history-clear', () => {
  sendMpvMessage('script-message', 'yomipv-history-clear');
});

ipcMain.on('history-toggle-anim', () => {
  sendMpvMessage('script-message', 'yomipv-history-toggle-anim');
});

ipcMain.on('history-toggle-time-source', () => {
  sendMpvMessage('script-message', 'yomipv-history-toggle-time-source');
});

ipcMain.on('history-set-ignore-mouse', (event, ignore) => {
  if (historyWindow) {
    historyWindow.setIgnoreMouseEvents(ignore, { forward: true });
  }
});

// Settings and profiles IPC
ipcMain.on('open-settings', () => {
  createSettingsWindow();
});

ipcMain.on('settings-window-ready', (event) => {
  sendMpvMessage('script-message', 'yomipv-get-settings');
});

ipcMain.on('settings-set', (event, { key, value }) => {
  sendMpvMessage('script-message', 'yomipv-set-setting', key, value.toString());
});

ipcMain.on('profile-list-request', () => {
  sendMpvMessage('script-message', 'yomipv-list-profiles');
});

ipcMain.on('profile-switch', (event, name) => {
  sendMpvMessage('script-message', 'yomipv-switch-profile', name);
});

ipcMain.on('profile-create', (event, name) => {
  sendMpvMessage('script-message', 'yomipv-create-profile', name);
});

ipcMain.on('profile-delete', (event, name) => {
  sendMpvMessage('script-message', 'yomipv-delete-profile', name);
});

// Incoming from MPV
ipcMain.on('profile-list', (event, profiles) => {
  if (settingsWindow) settingsWindow.webContents.send('profile-list', profiles);
});
