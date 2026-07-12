import {webuiArgs, webuiPath, webuiPort} from '/@/config';
import {PyShell} from '/@/pyshell';
import type {CallbackFun} from '/@/coreService';
import logger from '/@/logger';

const {execSync} = require('child_process');

/**
 * --- alas-mac-pack: reclaim the webui port from a stale backend ---
 * A previous / older instance (a crash, an orphaned backend, or an old version
 * still running in the menu bar when this one launched) can leave a python
 * webui listening on the port. createAlas forwards backend stderr to the
 * renderer, which navigates to the webui as soon as it sees `bind on address` —
 * i.e. it would attach to that stale server, whose working directory may point
 * at a now-moved/replaced bundle, so the page fails to load cwd-relative assets
 * (./assets/gui/css/alas.css -> FileNotFoundError on launch). Free the port
 * before (re)spawning so we always talk to our own backend, and never let
 * `bind on address` navigate the renderer to a foreign one.
 */
function freeWebuiPort() {
  try {
    const out = execSync(`/usr/sbin/lsof -ti tcp:${webuiPort}`, {encoding: 'utf8', timeout: 5000}).trim();
    for (const pid of out ? out.split('\n') : []) {
      try {
        process.kill(Number(pid), 'SIGKILL');
      } catch { /* already gone */ }
    }
  } catch { /* lsof exits non-zero when nothing is listening — nothing to do */ }
}

export const createAlas: CallbackFun = async ctx => {
  let restartedOnce = false;

  const build = (): PyShell | null => {
    // Always clear the port of any stale/foreign backend before spawning ours.
    freeWebuiPort();

    let alas: PyShell | null = null;
    try {
      alas = new PyShell(webuiPath, webuiArgs);
    } catch (e) {
      ctx.onError(e);
      return null;
    }

    alas.on('error', function (err: string) {
      if (!err) return;
      logger.error('alas.error:' + err);
      ctx.sendLaunchLog(err);
    });
    alas.end(function (err: string) {
      if (!err) return;
      logger.info('alas.end:' + err);
      ctx.sendLaunchLog(err);
      throw err;
    });
    alas.on('stdout', function (message) {
      ctx.sendLaunchLog(message);
    });
    alas.on('message', function (message) {
      ctx.sendLaunchLog(message);
    });
    alas.on('stderr', function (message: string) {
      /**
       * Port still occupied (a squatter survived the pre-kill). Do NOT forward
       * `bind on address` to the renderer — that log is exactly what makes it
       * navigate to the foreign server. Reclaim the port and respawn our own
       * backend once instead.
       */
      if (message.includes('bind on address') && !restartedOnce) {
        restartedOnce = true;
        logger.error('webui port busy — reclaiming it and respawning our backend');
        try {
          alas?.removeAllListeners();
          alas?.kill(() => { /* noop */ });
        } catch { /* ignore */ }
        build();
        return;
      }

      ctx.sendLaunchLog(message);
      /**
       * Ready once uvicorn reports startup complete:
       * `INFO:     Uvicorn running on http://0.0.0.0:22267 (Press CTRL+C to quit)`
       */
      if (message.includes('Application startup complete')) {
        alas?.removeAllListeners('stderr');
        alas?.removeAllListeners('message');
        alas?.removeAllListeners('stdout');
      }
    });

    alas.on('pythonError', err => {
      ctx.onError('alas pythonError:' + err);
    });
    return alas;
  };

  return build();
};
