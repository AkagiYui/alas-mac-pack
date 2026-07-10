# alas-mac-pack

Package **AzurLaneAutoScript** (Alas) as a *normal* macOS Electron app for Apple
Silicon — instead of the Platypus "terminal window" wrapper.

Upstream already ships a proper Electron desktop shell (`webapp/`, a
vite-electron-builder Vue3 app) but only builds it for Windows. This repo reuses
that shell, adds the small macOS adaptations it's missing, stuffs in a working
Python/git/adb toolkit, and produces a `.dmg`.

## What you get

- A real Electron window (frameless, tray icon) — no visible terminal.
- The Alas web UI (pywebio, served by the bundled Python) rendered inside the
  window.
- The in-app **self-update** (git pull + pip install of the Alas repo) keeps
  working — the Electron shell launches the Python backend which owns that logic.

## Design decisions (this build)

| Decision            | Choice                                             |
| ------------------- | -------------------------------------------------- |
| Architecture        | Apple Silicon (`arm64`) only *                     |
| Signing             | Ad-hoc / unsigned (users approve on first launch)  |
| Payload location    | Inside the `.app` bundle                           |

\* The bundled `miniforge3` python and `git` are arm64-only. Intel would need a
separate x86_64 python env.

### The one real caveat (payload-inside-bundle + unsigned)

The Alas repo self-updates with `git` **inside** `…/Contents/Resources/payload/app`.
That means:

- The app is **not notarized**; on first launch users must right-click → **Open**
  (or run `xattr -cr /path/AzurLaneAutoScript.app`).
- Updates write into the bundle, so keep the app somewhere user-writable
  (e.g. `~/Applications`, not a locked `/Applications` needing admin).

If you later want a notarizable, cleanly double-clickable app, switch to the
"external data dir" model (bootstrap the payload to
`~/Library/Application Support/AzurLaneAutoScript` on first run). The scripts are
structured to make that swap localized to `20-assemble.sh` + `config.ts`.

## How it works

The build is the "outside" approach — upstream is treated as read-only input and
all adaptations live here:

```
overlay/                         # files copied over the vendored webapp
  packages/main/src/config.ts    #  -> resolve payload from the .app, inject PATH
  electron-builder.config.js     #  -> mac arm64 target, productName, icon
config/deploy.mac.yaml           # deploy.yaml written into the payload (relative
                                 #   ../ paths to bundled python/git/adb)
scripts/                         # 4-step pipeline (see below)
assets/icon.icns, background.png
```

Bundle layout produced:

```
AzurLaneAutoScript.app/Contents/Resources/
  app.asar                       # the Electron shell (asar-packed)
  payload/
    app/                         # AzurLaneAutoScript git repo (gui.py, config/, deploy/)
    miniforge3/                  # python env  -> ../miniforge3/envs/alas/bin/python
    git/bin/git                  # -> ../git/bin/git
    platform-tools/adb           # -> ../platform-tools/adb
```

`config.ts` (the only meaningful code patch) computes
`alasPath = <Resources>/payload/app` in production and prepends the bundled
`git`/`adb` to `PATH`, replacing upstream's Windows-only `alasPath = process.cwd()`.

## Build

Requirements: macOS on Apple Silicon, Node ≥18, `create-dmg`
(`brew install create-dmg`).

```bash
./build.sh            # full pipeline -> dist/AzurLaneAutoScript.app + .dmg
```

Sub-targets: `./build.sh shell | assemble | package`.

### Inputs (override via env)

- `WEBAPP_SRC` — upstream Electron shell source. Vendored into this repo at
  `webapp-src/` (default), so builds are hermetic.
- `PAYLOAD_SRC` — a directory that already contains
  `app/ miniforge3/ git/ platform-tools/`. Defaults to the local Platypus `.app`
  `Contents/Resources`; CI points it at the extracted payload archive.

```bash
PAYLOAD_SRC=/some/Resources ./build.sh
```

The payload (repo + python env + git + adb) is reused as-is; this repo does not
rebuild the Python environment.

> **Node version:** the toolchain needs Node ≤ 18. `10-build-shell.sh` auto-hops
> to a fnm-managed Node 18 if your default is newer; CI pins it via `.node-version`.

## The payload (why it's prebuilt)

The Alas python env is **conda/miniforge**-based: `requirements.txt` is full of
`@ file:///…` conda builds (numpy, av, `mxnet==1.5.1`, gluoncv, lz4 …) that are
**not pip-installable**, and `mxnet 1.5.1` for osx-arm64/py3.8 effectively only
exists as that prebuilt env. So the ~2GB `miniforge3` env can't be reconstructed
from `pip` in CI — it is shipped as a prebuilt archive.

- `payload-arm64.tar.zst` (≈570 MB) contains `app/ miniforge3/ git/ platform-tools/`.
- It's stored as an asset on a GitHub **Release** (tag `payload-v1`).
- Regenerate it from a known-good `Contents/Resources` with:
  ```bash
  tar -C <Resources> -cf - app miniforge3 git platform-tools \
    | zstd -T0 -17 -o payload-arm64.tar.zst
  gh release create payload-v1 payload-arm64.tar.zst   # or: gh release upload
  ```

## Continuous Integration

[`.github/workflows/build.yml`](.github/workflows/build.yml) runs on
`macos-14` (Apple Silicon):

1. build the Electron shell (Node 18, npm, electron-builder),
2. download + extract the payload archive from the `payload-v1` release,
3. assemble + ad-hoc sign + `create-dmg`,
4. headless smoke test (launch the bundled python, assert the webui returns
   HTTP 200),
5. upload `dist/*.dmg` as the **`AzurLaneAutoScript-mac-arm64-dmg`** artifact.

Trigger: push a `v*` tag, or run **build-macos** manually (`workflow_dispatch`).

## Pipeline

| Step | Script                    | Does                                                        |
| ---- | ------------------------- | ----------------------------------------------------------- |
| 0    | `00-prepare-webapp.sh`    | copy webapp → `build/`, overlay mac patches                 |
| 1    | `10-build-shell.sh`       | `npm install`, vite build, `electron-builder --dir`         |
| 2    | `20-assemble.sh`          | copy payload into `.app`, write `deploy.yaml`               |
| 3    | `30-package.sh`           | ad-hoc sign, `create-dmg` → `dist/`                         |
