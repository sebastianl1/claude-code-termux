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
