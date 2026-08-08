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
    curl_lines = [ln for ln in src.splitlines() if "curl" in ln]
    assert curl_lines, "debe haber descargas con curl"
    without_proto = [ln for ln in curl_lines if "--proto" not in ln]
    # Los curl de metadatos (registry npm) pueden no tener --proto; aceptar
    assert len(without_proto) <= 2, f"curl sin --proto =https: {without_proto}"
