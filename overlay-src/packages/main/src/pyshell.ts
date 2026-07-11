import {alasPath, pythonPath} from '/@/config';
import logger from '/@/logger';

const {PythonShell} = require('python-shell');
const treeKill = require('tree-kill');

export class PyShell extends PythonShell {
  constructor(script: string, args: Array<string> = []) {
    const options = {
      mode: 'text',
      args: args,
      pythonPath: pythonPath,
      scriptPath: alasPath,
      // --- alas-mac-pack patch ---
      // Run the python process with cwd = repo root so the webui's cwd-relative
      // asset paths (e.g. ./assets/gui/css/...) resolve. In a packaged .app the
      // process would otherwise inherit '/'. python-shell (v3) forwards this
      // options object to child_process.spawn, so `cwd` takes effect.
      cwd: alasPath,
      // --- end patch ---
    };
    logger.info(`${pythonPath} ${script} ${args}`);
    super(script, options);
  }

  on(event: string, listener: (...args: any[]) => void): this {
    this.removeAllListeners(event);
    super.on(event, listener);
    return this;
  }

  kill(callback: (...args: any[]) => void): this {
    treeKill(this.childProcess.pid, 'SIGTERM', callback);
    return this;
  }
}
