import type {CoreService} from '/@/coreService';
import type {BrowserWindow} from 'electron';
import {ipcMain, nativeTheme} from 'electron';
import {
  ELECTRON_THEME,
  INSTALLER_READY,
  PAGE_ERROR,
  WINDOW_READY,
} from '@common/constant/eventNames';
import {ThemeObj} from '@common/constant/theme';
import logger from '/@/logger';
import {getCurrentWindow, getCurrentCore, hideToTray, quitApp} from '/@/createApp';

// Register the IPC handlers once. createApp() may run again (e.g. on 'activate'),
// and re-registering would stack duplicate handlers. The handlers below read the
// *current* window / core so they keep working across window re-creation.
let registered = false;

export const addIpcMainListener = async (_mainWindow: BrowserWindow, _coreService: CoreService) => {
  if (registered) return;
  registered = true;

  // Window controls (from the custom title bar).
  ipcMain.on('window-tray', function () {
    hideToTray();               // down-arrow: hide window + Dock icon (menu bar only)
  });
  ipcMain.on('window-minimize', function () {
    getCurrentWindow()?.minimize();
  });
  ipcMain.on('window-maximize', function () {
    const w = getCurrentWindow();
    if (!w) return;
    w.isMaximized() ? w.restore() : w.maximize();
  });
  ipcMain.on('window-close', function () {
    quitApp();                  // X: stop backend + quit
  });

  ipcMain.on(WINDOW_READY, async function (_, args) {
    logger.info('-----WINDOW_READY-----');
    args && (await getCurrentCore()?.run());
  });

  ipcMain.on(INSTALLER_READY, function () {
    logger.info('-----INSTALLER_READY-----');
    getCurrentCore()?.next();
  });

  ipcMain.on(ELECTRON_THEME, (_, args) => {
    logger.info('-----ELECTRON_THEME-----');
    nativeTheme.themeSource = ThemeObj[args];
  });

  ipcMain.on(PAGE_ERROR, (_, args) => {
    logger.info('-----PAGE_ERROR-----');
    logger.error(args);
  });
};
