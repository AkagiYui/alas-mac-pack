if (process.env.VITE_APP_VERSION === undefined) {
  const now = new Date;
  process.env.VITE_APP_VERSION = `${now.getUTCFullYear() - 2000}.${now.getUTCMonth() + 1}.${now.getUTCDate()}-${now.getUTCHours() * 60 + now.getUTCMinutes()}`;
}

/**
 * @type {import('electron-builder').Configuration}
 * @see https://www.electron.build/configuration/configuration
 *
 * alas-mac-pack: build only the .app shell here (asar packed). The ~2GB payload
 * (repo + miniforge + git + adb) is copied in afterwards by the assemble step,
 * so it is intentionally NOT listed in `files`/`extraResources`.
 */
const config = {
  appId: 'com.lmeszinc.azurlaneautoscript',
  productName: 'AzurLaneAutoScript',
  directories: {
    output: 'dist',
    buildResources: 'buildResources',
  },
  files: [
    'packages/**/dist/**',
  ],
  extraMetadata: {
    version: process.env.VITE_APP_VERSION,
  },
  // asar packs the shell as Contents/Resources/app.asar, leaving the
  // Contents/Resources/payload directory (added later) untouched.
  asar: true,
  mac: {
    target: [{target: 'dir', arch: 'arm64'}],
    category: 'public.app-category.games',
    icon: 'buildResources/icon.icns',
    // Ad-hoc signing is done by the package step, not by electron-builder.
    identity: null,
    hardenedRuntime: false,
    gatekeeperAssess: false,
  },
};

module.exports = config;
