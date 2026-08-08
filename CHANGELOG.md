# Changelog

Todas las versiones notables de Claude Code para Termux se documentan aqui.
Formato basado en [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- `install.sh`: configuracion DNS robusta (`resolv.conf` multi-servidor con
  `options timeout:1 attempts:2 rotate`), preferencia IPv4 en `gai.conf` y
  verificacion DNS post-instalacion. Mitiga el error de OAuth
  `getaddrinfo ETIMEOUT platform.claude.com`.
- `README.md`: seccion de solucion de problemas para el error OAuth
  `getaddrinfo ETIMEOUT platform.claude.com`.
- Tests: validacion del `resolv.conf` generado por el instalador.
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

## [1.0.1] - 2026-08

### Fixed
- `install.sh`: instalacion automatica de herramientas faltantes
  (`curl`, `tar`, `file`, `clang`) via `pkg`; ya no pide ejecutar la orden
  manualmente. Reintenta tras `pkg update` si falla la primera vez.
- `install.sh`: `file` anadido a la lista de paquetes de la capa glibc.
- `install.sh`: recuperacion automatica de dpkg interrumpido antes de instalar.
- `install.sh`: `restore_backup` usa el respaldo mas reciente y copia dotfiles.
- `install.sh`: no sobrescribe `settings.json` existente sin `python3`.
- `install.sh`: verificacion de integridad sha512 del tarball npm y checksum
  sha256 de la cache local.
- `install.sh`: desinstalacion basada en archivos (no en `command -v`).
- `tests`: deteccion robusta de invocaciones de `curl` con `--proto`.
- `versions.json`: actualizado a 2.1.226 con mirror en GitHub.

## [2.1.224] - 2026-07

- Instalador nativo de Claude Code para Termux con landing multi-idioma.
- Launcher con limpieza de LD_PRELOAD/LD_LIBRARY_PATH y arreglo del
  "invalid ELF header" en libc.so (override de symlinks glibc).
