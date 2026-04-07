const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const http = require('http');
const net = require('net');

let mainWindow;
let pendingHide = false;

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
            mpvIpc.end();
            mpvIpc = null;
          }
          
          setTimeout(() => {
            console.log('[INFO] Quitting app via shutdown signal');
            app.quit();
          }, 100);
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
          mpvIpc.end();
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
  if (mpvIpc) {
    const cmd = { command: ['script-message', 'yomipv-dictionary-selected', content] };
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
