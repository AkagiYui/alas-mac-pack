import {alasPath, pythonPath} from '/@/config';

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
      // The webui opens cwd-relative asset paths (e.g. './assets/gui/css/alas.css'),
      // so the python process must run with its working directory at the repo root.
      // Upstream relied on the Windows launcher setting cwd; in a packaged macOS
      // .app the process would otherwise inherit '/'. python-shell (v3) forwards
      // this options object straight to child_process.spawn, so `cwd` takes effect.
      cwd: alasPath,
      // --- end patch ---
    };
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
