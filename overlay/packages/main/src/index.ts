import {app, Menu, Tray, BrowserWindow, ipcMain, globalShortcut, nativeImage} from 'electron';
import {URL} from 'url';
import {PyShell} from '/@/pyshell';
import {webuiArgs, webuiPath, dpiScaling} from '/@/config';

const path = require('path');

const isSingleInstance = app.requestSingleInstanceLock();

if (!isSingleInstance) {
  app.quit();
  process.exit(0);
}

app.disableHardwareAcceleration();

// Install "Vue.js devtools"
if (import.meta.env.MODE === 'development') {
  app.whenReady()
    .then(() => import('electron-devtools-installer'))
    .then(({default: installExtension, VUEJS3_DEVTOOLS}) => installExtension(VUEJS3_DEVTOOLS, {
      loadExtensionOptions: {
        allowFileAccess: true,
      },
    }))
    .catch(e => console.error('Failed install extension:', e));
}

/**
 * Load deploy settings and start Alas web server.
 */
let alas = new PyShell(webuiPath, webuiArgs);
alas.end(function (err: string) {
  // if (err) throw err;
});


let mainWindow: BrowserWindow | null = null;
let tray: Tray | null = null;
let alasReady = false;
let isQuitting = false;

/**
 * --- alas-mac-pack: window / tray lifecycle ---
 * Upstream guarded window access with `mainWindow?.`, which only checks for
 * null — not for a *destroyed* window — so tray/menu handlers crashed with
 * "Object has been destroyed" after the window was closed. And on macOS closing
 * a window does not quit the app, so Close / Exit only hid the window and left a
 * zombie. These helpers centralise the correct behaviour.
 */
function hasWindow(): boolean {
  return !!mainWindow && !mainWindow.isDestroyed();
}

function loadURL() {
  if (!hasWindow()) return;
  const pageUrl = import.meta.env.MODE === 'development' && import.meta.env.VITE_DEV_SERVER_URL !== undefined
    ? import.meta.env.VITE_DEV_SERVER_URL
    : new URL('../renderer/dist/index.html', 'file://' + __dirname).toString();
  mainWindow!.loadURL(pageUrl);
}

// Show / restore the window (and the Dock icon). Re-creates the window if it was
// destroyed (e.g. Dock click after all windows closed on macOS).
function showWindow() {
  app.dock?.show?.();
  if (!hasWindow()) {
    createWindow();
    return;
  }
  if (mainWindow!.isMinimized()) mainWindow!.restore();
  mainWindow!.show();
  mainWindow!.focus();
}

// Hide the window and remove the Dock icon: keep running in the menu bar (tray).
function hideToTray() {
  if (hasWindow()) mainWindow!.hide();
  app.dock?.hide?.();
}

// Fully quit: stop the python backend, remove the tray, then exit.
function quitApp() {
  if (isQuitting) return;
  isQuitting = true;
  const finish = () => {
    try {
      app.exit(0);
    } catch {
      process.exit(0);
    }
  };
  try {
    tray?.destroy();
  } catch { /* ignore */ }
  tray = null;
  try {
    if (alas && typeof alas.kill === 'function') {
      alas.kill(finish);
    } else {
      finish();
    }
  } catch {
    finish();
  }
  // Safety net in case the kill callback never fires.
  setTimeout(finish, 2000);
}

const createWindow = () => {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 880,
    show: false, // Use 'ready-to-show' event to show window
    frame: false,
    icon: path.join(__dirname, './buildResources/icon.ico'),
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,   // Spectron tests can't work with contextIsolation: true
      nativeWindowOpen: true,
    },
  });

  /**
   * Use `show: false` + 'ready-to-show' to avoid flicker and close issues.
   * @see https://github.com/electron/electron/issues/25012
   */
  mainWindow.on('ready-to-show', () => {
    mainWindow?.show();

    // Hide menu
    Menu.setApplicationMenu(null);

    if (import.meta.env.MODE === 'development') {
      mainWindow?.webContents.openDevTools();
    }
  });

  // Keep the reference accurate so hasWindow() reports destroyed windows.
  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  mainWindow.on('focus', function () {
    // Dev tools
    globalShortcut.register('CommandOrControl+Shift+I', function () {
      if (mainWindow?.webContents.isDevToolsOpened()) {
        mainWindow?.webContents.closeDevTools();
      } else {
        mainWindow?.webContents.openDevTools();
      }
    });
    // Refresh
    globalShortcut.register('CommandOrControl+R', function () {
      mainWindow?.reload();
    });
    globalShortcut.register('CommandOrControl+Shift+R', function () {
      mainWindow?.reload();
    });
  });
  mainWindow.on('blur', function () {
    globalShortcut.unregisterAll();
  });

  // If the backend is already up (window was re-created), load the UI now.
  if (alasReady) {
    loadURL();
  }
};

// Register the window-control IPC handlers once (not per-window).
function registerIpcHandlers() {
  ipcMain.on('window-tray', hideToTray);        // down-arrow: hide to menu bar
  ipcMain.on('window-min', function () {
    if (hasWindow()) mainWindow!.minimize();
  });
  ipcMain.on('window-max', function () {
    if (!hasWindow()) return;
    mainWindow!.isMaximized() ? mainWindow!.restore() : mainWindow!.maximize();
  });
  ipcMain.on('window-close', quitApp);          // X: quit the app
}

// Create the menu-bar (tray) icon once.
function createTray() {
  // alas-mac-pack: small, menu-bar-sized icon (tray.png = 22px, tray@2x.png for
  // Retina, auto-loaded by nativeImage.createFromPath). Upstream passed the full
  // 256px app icon, so macOS rendered it at full size.
  const trayImage = nativeImage.createFromPath(path.join(__dirname, 'tray.png'));
  tray = new Tray(trayImage);
  const contextMenu = Menu.buildFromTemplate([
    {label: 'Show', click: showWindow},
    {label: 'Hide', click: hideToTray},
    {label: 'Exit', click: quitApp},
  ]);
  tray.setToolTip('Alas');
  tray.setContextMenu(contextMenu);
  tray.on('click', () => {
    if (hasWindow() && mainWindow!.isVisible()) {
      hideToTray();
    } else {
      showWindow();
    }
  });
  tray.on('right-click', () => {
    tray?.popUpContextMenu(contextMenu);
  });
}


// No DPI scaling
if (!dpiScaling) {
  app.commandLine.appendSwitch('high-dpi-support', '1');
  app.commandLine.appendSwitch('force-device-scale-factor', '1');
}


alas.on('stderr', function (message: string) {
  /**
   * Receive logs, judge if Alas is ready
   * `INFO:     Uvicorn running on http://0.0.0.0:22267 (Press CTRL+C to quit)`
   * or `[Errno 10048] error while attempting to bind on address ...`
   */
  if (message.includes('Application startup complete') || message.includes('bind on address')) {
    alasReady = true;
    alas.removeAllListeners('stderr');
    loadURL();
  }
});


app.on('second-instance', () => {
  // Someone tried to run a second instance: focus / restore our window.
  showWindow();
});

// macOS: clicking the Dock icon re-opens / re-creates the window.
app.on('activate', () => {
  showWindow();
});

app.on('window-all-closed', () => {
  // On macOS the app stays alive after windows close (we quit explicitly via
  // quitApp()). Only auto-quit on other platforms.
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

// Ensure the python backend is stopped on any quit path (e.g. Cmd+Q).
app.on('before-quit', () => {
  isQuitting = true;
  try {
    alas?.kill?.(() => { /* noop */ });
  } catch { /* ignore */ }
});


app.whenReady()
  .then(() => {
    registerIpcHandlers();
    createTray();
    createWindow();
  })
  .catch((e) => console.error('Failed create window:', e));


// Auto-updates
if (import.meta.env.PROD) {
  app.whenReady()
    .then(() => import('electron-updater'))
    .then(({autoUpdater}) => autoUpdater.checkForUpdatesAndNotify())
    .catch((e) => console.error('Failed check updates:', e));
}
