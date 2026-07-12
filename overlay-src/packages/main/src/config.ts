import {isMacintosh} from '@common/utils/env';
import getAlasABSPath from '@common/utils/getAlasABSPath';
import {ALAS_INSTR_FILE} from '@common/constant/config';
import {validateConfigFile} from '@common/utils/validate';
import {join} from 'path';
import logger from '/@/logger';

const yaml = require('yaml');
const fs = require('fs');
const path = require('path');

function getAlasPath() {
  let file;
  const currentFilePath = process.cwd();
  const pathLookup = ['./', '../../', '../../../', './../'];
  for (const i in pathLookup) {
    file = path.join(currentFilePath, pathLookup[i], './config/deploy.yaml');
    if (fs.existsSync(file)) {
      return path.join(currentFilePath, pathLookup[i]);
    }
  }
  for (const i in pathLookup) {
    file = path.join(currentFilePath, pathLookup[i], './config/deploy.template.yaml');
    if (fs.existsSync(file)) {
      return path.join(currentFilePath, pathLookup[i]);
    }
  }
  return currentFilePath;
}

/**
 * --- alas-mac-pack patch ---
 * Upstream resolves the repo with getAlasABSPath() (globbing for config/deploy.yaml),
 * which returns the wrong directory for our bundle layout (the repo is nested at
 * Contents/Resources/payload/app, not at the app root). Resolve it explicitly from
 * process.resourcesPath and prepend the bundled python + adb to PATH.
 *
 *   <App>.app/Contents/Resources/
 *     app.asar                     <- this electron shell
 *     payload/
 *       app/                       <- the StarRailCopilot git repo (gui.py, config/, deploy/)
 *       python/bin/python3         <- python-build-standalone + pip deps
 *       platform-tools/adb         <- bundled adb
 */
function resolveAlasPath(): string {
  if (isMacintosh && import.meta.env.PROD) {
    const payload = path.join(process.resourcesPath, 'payload');
    const extraBin = [
      path.join(payload, 'python', 'bin'),
      path.join(payload, 'platform-tools'),
    ].join(path.delimiter);
    process.env.PATH = extraBin + path.delimiter + (process.env.PATH || '');
    return path.join(payload, 'app');
  }
  return getAlasPath();
}

export const alasPath = resolveAlasPath();
/* --- end alas-mac-pack patch --- */

try {
  validateConfigFile(join(alasPath, '/config'));
} catch (e) {
  logger.error((e as unknown as any).toString());
}

const file = fs.readFileSync(path.join(alasPath, './config/deploy.yaml'), 'utf8');
const config = yaml.parse(file) as DefAlasConfig;
const PythonExecutable = config.Deploy.Python.PythonExecutable;
const WebuiPort = config.Deploy.Webui.WebuiPort.toString();
const Theme = config.Deploy.Webui.Theme;

export const ThemeObj: {[k in string]: 'light' | 'dark'} = {
  default: 'light',
  light: 'light',
  dark: 'dark',
  system: 'light',
};

export const pythonPath = path.isAbsolute(PythonExecutable)
  ? PythonExecutable
  : path.join(alasPath, PythonExecutable);
export const installerPath = ALAS_INSTR_FILE;
export const installerArgs = import.meta.env.DEV ? ['--print-test'] : [];
export const webuiUrl = `http://127.0.0.1:${WebuiPort}`;
export const webuiPort = WebuiPort;
export const webuiPath = 'gui.py';
export const webuiArgs = ['--port', WebuiPort, '--electron'];
export const dpiScaling =
  Boolean(config.Deploy.Webui.DpiScaling) || config.Deploy.Webui.DpiScaling === undefined;

export const webuiTheme = ThemeObj[Theme] || 'light';

export const noSandbox = config.Deploy.Webui.NoSandbox;
