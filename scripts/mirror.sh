#!/data/data/com.termux/files/usr/bin/bash
#
# mirror.sh - Sincroniza la copia de seguridad del binario de Claude Code
#
# Descarga el paquete de plataforma linux-arm64 desde el registry npm de
# Anthropic (@anthropic-ai/claude-code-linux-arm64), extrae el binario,
# lo verifica y lo sube como release asset a este mismo repositorio
# (sebastianl1/claude-code-termux), de modo que si npm falla o desaparece,
# el instalador sigue funcionando con el mirror.
#
# Uso:
#   bash scripts/mirror.sh              Sincroniza con la última versión de npm
#   bash scripts/mirror.sh 2.1.224      Sincroniza una versión concreta
#
# Requisitos: gh autenticado, curl, tar, sha256sum.

set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="sebastianl1/claude-code-termux"
NPM_PKG="@anthropic-ai/claude-code-linux-arm64"
ASSET="claude-code-linux-arm64.tar.gz"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$DIR"

# 1. Determinar versión
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "==> Consultando última versión en npm..."
    VERSION=$(curl -fsSL "https://registry.npmjs.org/${NPM_PKG}/latest" \
        | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
fi
[ -n "$VERSION" ] || { echo "ERROR: no se pudo determinar la versión."; exit 1; }
echo "    Versión: $VERSION"

TARBALL="$WORK/$ASSET"

# 2. Descargar desde el registry npm
echo "==> Descargando ${NPM_PKG}@${VERSION}..."
TARBALL_URL=$(curl -fsSL "https://registry.npmjs.org/${NPM_PKG}/${VERSION}" \
    | grep -o '"tarball":"[^"]*"' | cut -d'"' -f4)
[ -n "$TARBALL_URL" ] || { echo "ERROR: no se encontró el tarball en npm."; exit 1; }
curl -fsSL --proto =https "$TARBALL_URL" -o "$TARBALL"

# 3. Verificar integridad
echo "==> Verificando integridad..."
gzip -t "$TARBALL" || { echo "ERROR: gzip corrupto."; exit 1; }
[ "$(head -c 2 "$TARBALL" | od -An -tx1 | tr -d ' \n')" = "1f8b" ] || { echo "ERROR: no es gzip."; exit 1; }

tar -xzf "$TARBALL" -C "$WORK"
[ "$(head -c 4 "$WORK/package/claude" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || { echo "ERROR: claude no es un binario ELF."; exit 1; }
SIZE=$(wc -c < "$WORK/package/claude")
[ "$SIZE" -ge 200000000 ] || { echo "ERROR: claude demasiado pequeño ($SIZE bytes)."; exit 1; }
file "$WORK/package/claude" | grep -qi 'aarch64' || { echo "ERROR: claude no es aarch64."; exit 1; }

# Repack como tarball plano (claude)
echo "==> Empaquetando binario plano..."
tar -czf "$WORK/flat.tar.gz" -C "$WORK/package" claude
mv "$WORK/flat.tar.gz" "$TARBALL"

SHA=$(sha256sum "$TARBALL" | awk '{print $1}')
echo "    SHA256: $SHA"

# 4. Subir al release del propio repo
TAG="claude-${VERSION}"
echo "==> Subiendo a ${REPO}:${TAG}..."
if ! gh release view "$TAG" -R "$REPO" &>/dev/null; then
    gh release create "$TAG" -R "$REPO" \
        --title "Claude Code binary mirror $VERSION" \
        --notes "Copia de seguridad del binario de @anthropic-ai/claude-code-linux-arm64 $VERSION. SHA256: $SHA"
fi
gh release upload "$TAG" -R "$REPO" "$TARBALL" --clobber

# 5. Actualizar versions.json
echo "==> Actualizando versions.json..."
cat > "$DIR/versions.json" <<EOF
{
  "version": "$VERSION",
  "sha256": "$SHA",
  "urls": [
    "https://registry.npmjs.org/${NPM_PKG}/-/${NPM_PKG##*/}-${VERSION}.tgz",
    "https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"
  ]
}
EOF

echo ""
echo "✔ Mirror sincronizado: $VERSION ($SHA)"
echo "  No olvides commitear y pushear versions.json si cambió:"
echo "    git add versions.json && git commit -m \"mirror: actualizar a $VERSION\" && git push"
