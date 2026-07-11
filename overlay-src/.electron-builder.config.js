/**
 * alas-mac-pack: build the StarRailCopilot .app shell (asar packed) for macOS
 * arm64. The payload (repo + python + adb) is copied in afterwards by the
 * assemble step, so it is intentionally NOT in `files`/`extraResources`.
 *
 * electron-builder doesn't support ESM configs, hence the async function form.
 */
module.exports = async function () {
  const {getVersion} = await import('./version/getVersion.mjs');

  return {
    appId: 'com.lmeszinc.starrailcopilot',
    productName: 'StarRailCopilot',
    directories: {
      output: 'dist',
      buildResources: 'buildResources',
    },
    files: ['packages/**/dist/**'],
    extraMetadata: {
      version: getVersion(),
    },
    asar: true,
    mac: {
      target: [{target: 'dir', arch: 'arm64'}],
      category: 'public.app-category.games',
      icon: 'buildResources/icon.icns',
      identity: null,            // ad-hoc signed by the package step
      hardenedRuntime: false,
      gatekeeperAssess: false,
    },
  };
};
