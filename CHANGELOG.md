# Changelog

Todas las versiones notables de Claude Code para Termux se documentan aqui.
Formato basado en [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- CI/CD: workflow de lint (bash -n, shellcheck, node --check lang, validacion
  de versions.json, i18n y descargas https) y job de tests (pytest).
- CD: workflow de despliegue de GitHub Pages (docs/).
- Tests (`tests/`) para versions.json, i18n y el instalador.
- `docs/llms.txt` (AEO).
- Documentacion de comunidad: `SECURITY.md`, `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md` y este `CHANGELOG.md`.
- `.gitignore` raiz.

### Security
- `install.sh`: descargas con `--proto =https` (npm y fuentes).

## [2.1.224] - 2026-07

- Instalador nativo de Claude Code para Termux con landing multi-idioma.
- Launcher con limpieza de LD_PRELOAD/LD_LIBRARY_PATH y arreglo del
  "invalid ELF header" en libc.so (override de symlinks glibc).
