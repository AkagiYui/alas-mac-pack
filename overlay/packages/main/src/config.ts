const yaml = require('yaml');
const fs = require('fs');
const path = require('path');

/**
 * --- alas-mac-pack patch ---
 * Upstream uses `alasPath = process.cwd()`, which works on Windows because the
 * `Alas.exe` launcher sets the working directory to the repo root. In a packaged
 * macOS `.app` launched by Finder, `process.cwd()` is `/`, so the bundled repo
 * and toolkit can't be found.
 *
 * The macOS package layout (see alas-mac-pack assemble step) is:
 *   AzurLaneAutoScript.app/Contents/Resources/
 *     app.asar                 <- this electron shell
 *     payload/
 *       app/                   <- the AzurLaneAutoScript git repo (gui.py, config/, deploy/)
 *       miniforge3/            <- bundled python env
 *       git/bin/git            <- bundled git (used by the in-app self-update)
 *       platform-tools/adb     <- bundled adb
 *
 * So in production we resolve the repo relative to `process.resourcesPath` and
 * prepend the bundled git + adb to PATH so the Python deploy/self-update works.
 */
function resolveAlasPath() {
  if (import.meta.env.PROD) {
    const payload = path.join(process.resourcesPath, 'payload');
    const extraBin = [
      path.join(payload, 'git', 'bin'),
      path.join(payload, 'platform-tools'),
    ].join(path.delimiter);
    process.env.PATH = extraBin + path.delimiter + (process.env.PATH || '');
    return path.join(payload, 'app');
  }
  return process.cwd();
}

export const alasPath = resolveAlasPath();
/* --- end alas-mac-pack patch --- */

const file = fs.readFileSync(path.join(alasPath, './config/deploy.yaml'), 'utf8');
const config = yaml.parse(file);
const PythonExecutable = config.Deploy.Python.PythonExecutable;
const WebuiPort = config.Deploy.Webui.WebuiPort.toString();

export const pythonPath = (path.isAbsolute(PythonExecutable) ? PythonExecutable : path.join(alasPath, PythonExecutable));
export const webuiUrl = `http://127.0.0.1:${WebuiPort}`;
export const webuiPath = 'gui.py';
export const webuiArgs = ['--port', WebuiPort, '--electron'];
export const dpiScaling = Boolean(config.Deploy.Webui.DpiScaling) || (config.Deploy.Webui.DpiScaling === undefined) ;
