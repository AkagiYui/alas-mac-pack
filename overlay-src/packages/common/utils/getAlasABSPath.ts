import {app} from 'electron';
import {isMacintosh} from './env';
import fs from 'fs';
/**
 * Get the absolute path of the project root directory.
 *
 * --- alas-mac-pack patch ---
 * In the packaged macOS app the repo is nested at
 * Contents/Resources/payload/app. Upstream's glob-based search returns the wrong
 * ancestor for that layout (and, from the preload where electron's `app` is
 * undefined, it walks up from the executable and returns Contents). Resolve it
 * directly from process.resourcesPath, which is available in both the main and
 * preload processes.
 */
const getAlasABSPath = (
  files: string[] = ['**/config/deploy.yaml', '**/config/deploy.template.yaml'],
  rootName: string | string[] = ['AzurLaneAutoScript', 'Alas', 'StarRailCopilot', 'SRC'],
) => {
  const path = require('path');
  const sep = path.sep;

  if (isMacintosh && import.meta.env.PROD && (process as any).resourcesPath) {
    const p = path.join((process as any).resourcesPath, 'payload', 'app');
    return p.endsWith(sep) ? p : p + sep;
  }

  const fg = require('fast-glob');
  let appAbsPath = process.cwd();
  if (isMacintosh && import.meta.env.PROD) {
    appAbsPath = app?.getAppPath() || process.execPath;
  }

  while (fs.lstatSync(appAbsPath).isFile()) {
    appAbsPath = appAbsPath.split(sep).slice(0, -1).join(sep);
  }

  let alasABSPath = '';
  let hasRootName = false;

  if (typeof rootName === 'string') {
    hasRootName = appAbsPath.includes(rootName);
  } else if (Array.isArray(rootName)) {
    hasRootName = rootName.some(item =>
      appAbsPath.toLocaleLowerCase().includes(item.toLocaleLowerCase()),
    );
  }

  if (hasRootName) {
    const appAbsPathArr = appAbsPath.split(sep);
    let flag = false;
    while (hasRootName && !flag) {
      const entries = fg.sync(files, {dot: true, cwd: appAbsPathArr.join(sep) as string});
      if (entries.length > 0) {
        flag = true;
        alasABSPath = appAbsPathArr.join(sep);
      }
      appAbsPathArr.pop();
    }
  } else {
    let step = 4;
    const appAbsPathArr = appAbsPath.split(sep);
    let flag = false;
    while (step > 0 && !flag) {
      const entries = fg.sync(files, {dot: true, cwd: appAbsPathArr.join(sep) as string});
      if (entries.length > 0) {
        flag = true;
        alasABSPath = appAbsPathArr.join(sep);
      }
      step--;
      appAbsPathArr.pop();
    }
  }

  return alasABSPath.endsWith(sep) ? alasABSPath : alasABSPath + sep;
};

export default getAlasABSPath;
