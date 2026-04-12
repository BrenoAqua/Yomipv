const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage } = require('electron');
const path = require('path');
const http = require('http');
const net = require('net');

let mainWindow;
let pendingHide = false;
let lastSelectedDictHtml = '';

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

// mpv IPC setup
const ipcPipeArg = process.argv.find(arg => arg.startsWith('--ipc-pipe='));
const ipcPipe = ipcPipeArg ? ipcPipeArg.split('=')[1] : null;

let mpvIpc = null;
if (ipcPipe) {
  try {
    console.log('[IPC] Connecting to:', ipcPipe);
    mpvIpc = net.connect(ipcPipe, () => {
      console.log('[IPC] Connected to mpv');
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
  createWindow();

  // Simple HTTP server to receive terms from MPV
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
          return;
        }

        if (req.url === '/hide') {
          console.log('[IPC] Hide signal received, requesting renderer clear');
          res.end('hiding');
          if (mainWindow) {
            pendingHide = true;
            mainWindow.webContents.send('window-hide-request');
          }
          return;
        }

        try {
          const data = JSON.parse(body);
          if (data.term) {
            console.log('[IPC] Lookup for:', data.term);
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

  // Parent PID monitoring
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
  const template = [
    {
      label: 'Copy',
      enabled: hasSelection,
      click: () => {
        if (mainWindow) {
          mainWindow.webContents.send('copy-selection');
        }
      }
    },
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
        if (mainWindow) {
          mainWindow.webContents.send('refresh-css');
        }
      }
    }
  ];
  const menu = Menu.buildFromTemplate(template);
  menu.popup(BrowserWindow.fromWebContents(event.sender));
});

ipcMain.on('sync-selection', (event, text) => {
  console.log('[IPC] sync-selection received:', text);
  if (mpvIpc) {
    const cmd = { command: ['script-message', 'yomipv-sync-selection', text] };
    mpvIpc.write(JSON.stringify(cmd) + '\n');
  } else {
    console.warn('[IPC] Cannot sync selection: mpvIpc not connected');
  }
});

ipcMain.on('dictionary-selected', (event, content) => {
  console.log('[IPC] dictionary-selected received');
  
  lastSelectedDictHtml = content;

  if (mpvIpc) {
    const cmd = { command: ['script-message', 'yomipv-dictionary-selected', 'HTTP_FETCH'] };
    mpvIpc.write(JSON.stringify(cmd) + '\n');
  } else {
    console.warn('[IPC] Cannot send dictionary selection: mpvIpc not connected');
  }
});

ipcMain.on('active-entry', (event, data) => {
  if (mpvIpc && data) {
    const cmd = { command: ['script-message', 'yomipv-active-entry', data.expression || '', data.reading || ''] };
    mpvIpc.write(JSON.stringify(cmd) + '\n');
  }
});

ipcMain.on('show-window', () => {
  if (mainWindow) {
    console.log('[IPC] show-window signal received');
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
    mainWindow.hide();
    pendingHide = false;
  } else {
    console.log('[IPC] Hide confirmed but ignored (new lookup pending)');
  }
});
