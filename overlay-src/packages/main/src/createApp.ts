import {createMainWindow} from '/@/createMainWindow';
import {addIpcMainListener} from '/@/addIpcMainListener';
import {CoreService} from '/@/coreService';
import logger from '/@/logger';
import {app, nativeImage, Tray, Menu, BrowserWindow} from 'electron';
import {join} from 'node:path';

/**
 * --- alas-mac-pack: window / tray lifecycle ---
 * Fixes matching the alas build:
 *  - the menu-bar icon is a small circular crop (tray.png) instead of the full
 *    app icon; a click only opens the menu (no window toggle);
 *  - hide-to-tray also hides the Dock icon; show restores it;
 *  - guards against a destroyed window;
 *  - the tray is a singleton (createApp may run again on 'activate').
 */
let tray: Tray | null = null;
let currentWindow: BrowserWindow | null = null;
let currentCore: CoreService | null = null;
let quitting = false;

export function getCurrentWindow(): BrowserWindow | null {
  return currentWindow && !currentWindow.isDestroyed() ? currentWindow : null;
}
export function getCurrentCore(): CoreService | null {
  return currentCore;
}

export function showWindow() {
  app.dock?.show?.();
  const w = getCurrentWindow();
  if (w) {
    if (w.isMinimized()) w.restore();
    w.show();
    w.focus();
  }
}

export function hideToTray() {
  const w = getCurrentWindow();
  if (w) w.hide();
  // Remove the Dock icon; keep running in the menu bar (tray).
  app.dock?.hide?.();
}

export function quitApp() {
  if (quitting) return;
  quitting = true;
  try {
    currentCore?.kill?.(() => logger.info('killed backend on quit'));
  } catch { /* ignore */ }
  try {
    tray?.destroy();
  } catch { /* ignore */ }
  tray = null;
  app.exit(0);
}

function ensureTray() {
  if (tray) return;
  const trayImage = nativeImage.createFromPath(join(__dirname, 'tray.png'));
  tray = new Tray(trayImage);
  const contextMenu = Menu.buildFromTemplate([
    {label: 'Show', click: showWindow},
    {label: 'Hide', click: hideToTray},
    {label: 'Exit', click: quitApp},
  ]);
  tray.setToolTip('StarRailCopilot');
  // On macOS, setContextMenu opens the menu on a click. Intentionally no 'click'
  // handler so the icon ONLY opens the menu (no window show/hide toggle).
  tray.setContextMenu(contextMenu);
}

export const createApp = async () => {
  logger.info('-----createApp-----');
  logger.info('-----createMainWindow-----');
  const mainWindow = await createMainWindow();
  const coreService = new CoreService({mainWindow});
  currentWindow = mainWindow;
  currentCore = coreService;
  mainWindow.on('closed', () => {
    if (currentWindow === mainWindow) currentWindow = null;
  });

  // Hide the app menu, ensure the tray exists (once).
  Menu.setApplicationMenu(null);
  ensureTray();

  await addIpcMainListener(mainWindow, coreService);
  return {
    mainWindow,
    coreService,
  };
};
