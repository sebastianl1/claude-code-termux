/*
 * Claude Code — Termux launcher
 *
 * Ejecuta el binario glibc de Claude Code (claude.real) dentro de la capa
 * glibc de Termux invocando el cargador dinamico glibc directamente:
 *
 *   ld-linux-aarch64.so.1 --library-path <glibc/lib> claude.real [args]
 *
 * PREFIX se inyecta en tiempo de compilacion:
 *   cc -O2 -DPREFIX="\"$PREFIX\"" -o claude launcher.c
 *
 * A diferencia de otros CLI, Claude Code necesita ademas:
 *   - TMPDIR/CLAUDE_CODE_TMPDIR -> prefijo de Termux (no hay /tmp escribible)
 *   - CLAUDE_CODE_EXECPATH     -> este launcher, para que los subprocesos
 *                                 (grep/find/rg y herramientas embebidas)
 *                                 vuelvan a re-ejecutarse a traves de el.
 */

#ifndef PREFIX
#define PREFIX "/data/data/com.termux/files/usr"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define GLIBC_LOADER PREFIX "/glibc/lib/ld-linux-aarch64.so.1"
#define GLIBC_LIB    PREFIX "/glibc/lib"
#define CLAUDE_REAL  PREFIX "/share/claude/claude.real"
#define CLAUDE_BIN   PREFIX "/bin/claude"
#define SSL_CERTS    PREFIX "/etc/tls/cert.pem"
#define TMP_DIR      PREFIX "/tmp"

int main(int argc, char **argv) {
    char **args;
    int i;

    setenv("SSL_CERT_FILE", SSL_CERTS, 1);
    if (!getenv("TMPDIR")) {
        setenv("TMPDIR", TMP_DIR, 1);
    }
    if (!getenv("CLAUDE_CODE_TMPDIR")) {
        setenv("CLAUDE_CODE_TMPDIR", TMP_DIR, 1);
    }
    if (!getenv("CLAUDE_CODE_EXECPATH")) {
        setenv("CLAUDE_CODE_EXECPATH", CLAUDE_BIN, 1);
    }
    setenv("DISABLE_AUTOUPDATER", "1", 1);

    args = calloc((size_t)argc + 4, sizeof(char *));
    if (!args) {
        perror("claude: calloc");
        return 127;
    }

    args[0] = GLIBC_LOADER;
    args[1] = "--library-path";
    args[2] = GLIBC_LIB;
    args[3] = CLAUDE_REAL;
    for (i = 1; i < argc; i++) {
        args[i + 3] = argv[i];
    }
    args[argc + 3] = NULL;

    execv(GLIBC_LOADER, args);
    perror("claude");
    return 127;
}
