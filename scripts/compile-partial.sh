#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_TEX="$ROOT_DIR/tesis.tex"
BUILD_DIR="$ROOT_DIR/build/partial"

usage() {
  cat <<'EOF'
Uso:
  scripts/compile-partial.sh "Titulo exacto del capitulo o apendice"

Ejemplos:
  scripts/compile-partial.sh "Mithril"
  scripts/compile-partial.sh "Primitivas Criptográficas"
EOF
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

TITLE="$1"

if [[ ! -f "$MAIN_TEX" ]]; then
  echo "No se encontro tesis.tex en $ROOT_DIR" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

NORMALIZED_TITLE="$(
  printf '%s' "$TITLE" \
    | sed 'y/ÁÀÄÂÃáàäâãÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔÕóòöôõÚÙÜÛúùüûÑñÇç/AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuNnCc/'
)"

SLUG="$(
  printf '%s' "$NORMALIZED_TITLE" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
)"

if [[ -z "$SLUG" ]]; then
  echo "No se pudo generar un nombre de salida valido para: $TITLE" >&2
  exit 1
fi

TMP_TEX="$BUILD_DIR/partial-$SLUG.tex"
JOBNAME="partial-$SLUG"
AUX_BASENAME="$BUILD_DIR/$JOBNAME"

APPENDIX_MODE="$(
  python3 - "$MAIN_TEX" "$TITLE" <<'PY'
import sys
from pathlib import Path

main_tex = Path(sys.argv[1])
title = sys.argv[2]
lines = main_tex.read_text(encoding="utf-8").splitlines()

in_appendix = False
target = f"\\chapter{{{title}}}"

for line in lines:
    if line == r"\appendix":
        in_appendix = True
    if line == target:
        print("yes" if in_appendix else "no")
        raise SystemExit(0)

raise SystemExit(1)
PY
)" || {
  echo "No encontre un bloque con titulo exacto: $TITLE" >&2
  exit 1
}

{
  sed '/\\begin{document}/q' "$MAIN_TEX"
  printf '\n'
  printf '\\mainmatter\n'
  printf '\\pagestyle{headings}\n'
  if [[ "$APPENDIX_MODE" == "yes" ]]; then
    printf '\\appendix\n'
  fi
  python3 - "$MAIN_TEX" "$TITLE" <<'PY'
import sys
from pathlib import Path

main_tex = Path(sys.argv[1])
title = sys.argv[2]
lines = main_tex.read_text(encoding="utf-8").splitlines()

target = f"\\chapter{{{title}}}"
capture = False
seen = False

for line in lines:
    if line == target:
        capture = True
    if capture:
        if line == r"\end{document}":
            break
        if seen and line.startswith(r"\chapter{"):
            break
        print(line)
        seen = True
PY
  printf '\n\\backmatter\n'
  printf '\\bibliographystyle{ieeetr}\n'
  printf '\\bibliography{tesis}\n'
  printf '\\end{document}\n'
} > "$TMP_TEX"

(
  cd "$ROOT_DIR"
  rm -f \
    "$AUX_BASENAME.aux" \
    "$AUX_BASENAME.bbl" \
    "$AUX_BASENAME.blg" \
    "$AUX_BASENAME.log" \
    "$AUX_BASENAME.out" \
    "$AUX_BASENAME.toc" \
    "$AUX_BASENAME.fls" \
    "$AUX_BASENAME.fdb_latexmk" \
    "$AUX_BASENAME.pdf"

  pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$BUILD_DIR" -jobname="$JOBNAME" "$TMP_TEX"
  (
    cd "$BUILD_DIR"
    BIBINPUTS="$ROOT_DIR:$BUILD_DIR:" BSTINPUTS="$ROOT_DIR:" bibtex "$JOBNAME"
  )
  pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$BUILD_DIR" -jobname="$JOBNAME" "$TMP_TEX"
  pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$BUILD_DIR" -jobname="$JOBNAME" "$TMP_TEX"
)

echo "PDF generado en: $BUILD_DIR/$JOBNAME.pdf"
