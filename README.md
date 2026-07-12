# alas-mac-pack

Package **AzurLaneAutoScript** (Alas) and **StarRailCopilot** (SRC) as *normal*
macOS Electron apps for Apple Silicon — instead of the Platypus "terminal window"
wrapper.

Two build **profiles** share one pipeline (`PROFILE=alas` default, `PROFILE=src`):

| | alas | src |
| --- | --- | --- |
| upstream | LmeSzinc/AzurLaneAutoScript | LmeSzinc/StarRailCopilot |
| python | conda env (`config/environment-alas.yml`) | python-build-standalone + pip |
| payload builder | `scripts/05-alas-build-payload.sh` | `scripts/05-src-build-payload.sh` |
| deploy | `config/deploy-alas.mac.yaml` | `config/deploy-src.mac.yaml` |
| overlay | `overlay-alas/` | `overlay-src/` |
| workflow | `.github/workflows/build-alas.yml` | `.github/workflows/build-src.yml` |
| artifact | ~810 MB | ~200 MB |

Profile-specific files are **peers**, each marked with its profile name (there is
no unmarked "default" profile): `overlay-<p>/`, `config/deploy-<p>.mac.yaml`,
`scripts/05-<p>-build-payload.sh`, `.github/workflows/build-<p>.yml`. Everything
else is shared and selected by `scripts/env.sh` (`PROFILE=alas` default, or `src`).

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

Nothing from upstream is stored here — the Electron shell (`webapp/`), the Alas
repo, the python env, adb and the icon art are all pulled at build time from the
upstream repo at its release tag. The repo holds only patches, config, scripts:

```
overlay-<p>/                     # my patches, layered over the upstream webapp
  packages/main/src/config.ts    #  -> resolve payload from the .app, inject PATH
  packages/main/src/index.ts     #  -> menu-bar (tray) icon sizing fix
  packages/main/src/pyshell.ts   #  -> run python with cwd = repo root
  electron-builder.config.js     #  -> mac arm64 target, productName, icon
config/deploy-<p>.mac.yaml       # deploy.yaml written into the payload
config/environment-alas.yml      # conda env spec (alas only)
scripts/                         # build pipeline (see below)
```

The app icon, menu-bar icon, and the DMG background (with the
`xattr -c /Applications/<App>.app` un-quarantine instruction) are all generated
per-app at build time by `06-make-icons.sh` — nothing image-related is stored.

Bundle layout produced:

```
AzurLaneAutoScript.app/Contents/Resources/
  app.asar                       # the Electron shell (asar-packed)
  payload/
    app/                         # AzurLaneAutoScript git repo (gui.py, config/, deploy/)
    miniforge3/envs/alas/        # conda env -> bin/python, bin/git
    platform-tools/adb           # -> ../platform-tools/adb
```

`config.ts` (the only meaningful code patch) computes
`alasPath = <Resources>/payload/app` in production and prepends the bundled env
`bin` (python + git) and `adb` to `PATH`, replacing upstream's Windows-only
`alasPath = process.cwd()`.

## Build

Requirements: macOS on Apple Silicon, Node ≥18, `create-dmg`
(`brew install create-dmg`).

```bash
./build.sh            # full pipeline -> dist/AzurLaneAutoScript.app + .dmg
```

Sub-targets: `./build.sh shell | assemble | package`.

### Inputs (override via env)

- `WEBAPP_SRC` — upstream Electron shell source. Default `build/webapp-upstream`,
  extracted from the cloned repo by `05-alas-build-payload.sh` (not stored in this repo).
- `PAYLOAD_SRC` — a directory containing `app/ miniforge3/envs/alas/
  platform-tools/`. Default `build/payload`, produced by
  `scripts/05-alas-build-payload.sh`. Locally you can point it at an existing
  `Contents/Resources` to reuse a prebuilt env:
  ```bash
  PAYLOAD_SRC=/some/Resources ./build.sh
  ```

> **Node version:** the toolchain needs Node ≤ 18. `10-build-shell.sh` auto-hops
> to a fnm-managed Node 18 if your default is newer; CI pins it via `.node-version`.

## The payload (built at build time, not stored)

Nothing heavy lives in this repo — only config + scripts. The payload is produced
fresh by [`scripts/05-alas-build-payload.sh`](scripts/05-alas-build-payload.sh):

- **python env** — `conda env create -f config/environment-alas.yml` builds the `alas`
  env (python 3.8 + `mxnet==1.5.1`, opencv, numpy, av … from the `anaconda` /
  `conda-forge` channels). These are conda-only packages, not pip-installable,
  which is why conda is required. `environment-alas.yml` is adapted from
  [Dreamry2C/MAC-arm-conda-alas](https://github.com/Dreamry2C/MAC-arm-conda-alas).
  The built env is copied into the bundle at `payload/miniforge3/envs/alas`.
- **app repo** — `git clone` of AzurLaneAutoScript at its **latest release tag**
  (not master HEAD) → `payload/app` (a real checkout, so the in-app self-update
  works). The release tag is resolved at build time via
  `gh release view LmeSzinc/AzurLaneAutoScript`.
- **git** — a relocatable Apple git (~6 MB) copied by
  [`scripts/bundle-git.sh`](scripts/bundle-git.sh) → `payload/git`, so self-update
  works on a Mac with no system git. Both profiles share it. See
  [docs/bundling-git.md](docs/bundling-git.md) for the (non-obvious) reasoning.
- **adb** — Google's `platform-tools-latest-darwin.zip` → `payload/platform-tools`.

### macOS 15 (Sequoia) rpath fix

Several conda arm64 libs (libopenblas, libgfortran, numpy's `_multiarray_umath.so`, …)
ship **duplicate `LC_RPATH`** load commands. macOS ≤14 tolerates this; **macOS 15
dyld rejects it**, so `import numpy`/`cv2` fails and the scheduler crashes with
`Library not loaded: @rpath/libgfortran.5.dylib … (duplicate LC_RPATH '@loader_path')`.
[`scripts/fix-env-rpaths.py`](scripts/fix-env-rpaths.py) de-duplicates the rpaths
and re-signs each affected Mach-O; it runs inside `05-alas-build-payload.sh`.

> Note: CI runners are macos-14, where the bug does **not** reproduce, so CI
> cannot catch it. The fix is verified on macOS 15. The smoke test now also
> imports numpy/cv2/mxnet to catch gross breakage.

## Continuous Integration

[`.github/workflows/build-alas.yml`](.github/workflows/build-alas.yml) runs on
**`macos-15`** (Apple Silicon — the same OS users have, so the smoke test really
validates) and uploads to a workflow **artifact** (no release). All build work
happens in CI; nothing is built locally.

1. `setup-miniconda` + create the `alas` env from `config/environment-alas.yml`,
2. build the payload (clone repo **at the latest release tag**, copy + rpath-fix
   the env, download adb),
3. build the Electron shell (Node 18, npm, electron-builder),
4. assemble + ad-hoc sign + `create-dmg`,
5. **end-to-end smoke test**: import numpy/cv2/mxnet from the bundled python, then
   launch the real Electron app and drive a pywebio websocket session
   (`index()` → `add_css`) — fails the build if the GUI can't render,
6. upload `dist/*.dmg` as the **`AzurLaneAutoScript-mac-arm64-<upstream-commit>`** artifact
   (the `.dmg` filename and the artifact name both carry the packaged upstream short commit hash).

Trigger: push an `alas-v*` tag, or run **build-macos-alas** manually (`workflow_dispatch`).

## Pipeline

| Step | Script                    | Does                                                        |
| ---- | ------------------------- | ----------------------------------------------------------- |
| 0.5  | `05-alas-build-payload.sh`     | clone repo (release tag), copy conda env, download adb; extract icon art |
| 0    | `00-prepare-webapp.sh`    | copy webapp → `build/`, overlay mac patches                 |
| 0.6  | `06-make-icons.sh`        | generate the dock (`.icns`) + menu-bar (`tray.png`) icons from the upstream art |
| 1    | `10-build-shell.sh`       | `npm install`, vite build, `electron-builder --dir`         |
| 2    | `20-assemble.sh`          | copy payload into `.app`, write `deploy.yaml`, drop upstream deploy templates |
| 3    | `30-package.sh`           | ad-hoc sign, `create-dmg` → `dist/` (DMG named by upstream commit hash) |
| 4    | `40-smoke-test.sh`        | headless: launch bundled python, assert webui HTTP 200      |
