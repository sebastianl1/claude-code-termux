import re
from pathlib import Path

ROOT = Path(__file__).parent.parent


def test_installer_has_set_e():
    src = (ROOT / "install.sh").read_text()
    assert re.search(r"^set -[a-zA-Z]*e", src, re.M), "install.sh debe usar set -e"


def test_no_http_plain_downloads():
    src = (ROOT / "install.sh").read_text()
    bad = [ln for ln in src.splitlines() if "curl" in ln and "http://" in ln]
    assert not bad, f"curl con http:// encontrado: {bad}"


def test_curl_use_proto_https():
    src = (ROOT / "install.sh").read_text()
    # Solo lineas donde 'curl' es un comando con flags, no menciones en mensajes
    curl_lines = [ln for ln in src.splitlines() if re.search(r"curl\s+-[A-Za-z]", ln)]
    assert curl_lines, "debe haber descargas con curl"
    without_proto = [ln for ln in curl_lines if "--proto" not in ln]
    assert not without_proto, f"curl sin --proto =https: {without_proto}"


def _resolv_conf_block(src):
    # Extrae el heredoc que configure_dns escribe en $PREFIX/etc/resolv.conf
    m = re.search(
        r'cat > "\$resolv_conf" <<\'EOF\'\n(.*?)\nEOF',
        src,
        re.S,
    )
    assert m, "install.sh debe escribir resolv.conf con heredoc"
    return m.group(1)


def test_resolv_conf_multiple_nameservers():
    block = _resolv_conf_block((ROOT / "install.sh").read_text())
    nameservers = re.findall(r"^nameserver\s+(\S+)", block, re.M)
    assert len(nameservers) >= 2, f"resolv.conf debe tener >=2 nameservers: {nameservers}"
    assert len(set(nameservers)) == len(nameservers), "nameservers no deben repetirse"
    for ns in nameservers:
        assert re.fullmatch(r"\d{1,3}(?:\.\d{1,3}){3}", ns), f"nameserver invalido: {ns}"


def test_resolv_conf_short_timeout():
    block = _resolv_conf_block((ROOT / "install.sh").read_text())
    assert "options timeout:1" in block, "resolv.conf debe incluir timeout corto"
    assert "rotate" in block, "resolv.conf debe incluir rotate"


def test_gai_ipv4_precedence():
    src = (ROOT / "install.sh").read_text()
    assert "precedence ::ffff:0:0/96" in src, "install.sh debe configurar preferencia IPv4 en gai.conf"


def test_dns_verification_uses_getent_glibc():
    src = (ROOT / "install.sh").read_text()
    assert "getent" in src and "platform.claude.com" in src, (
        "install.sh debe verificar DNS resolviendo platform.claude.com con getent glibc"
    )
