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
  awk -v title="$TITLE" '
    BEGIN { in_appendix = 0 }
    /^\\appendix$/ { in_appendix = 1 }
    $0 == "\\chapter{" title "}" {
      print(in_appendix ? "yes" : "no")
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$MAIN_TEX"
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
  awk -v title="$TITLE" '
    $0 == "\\chapter{" title "}" {
      capture = 1
    }
    capture {
      if (seen && $0 ~ /^\\chapter\{/) {
        exit
      }
      print
      seen = 1
    }
  ' "$MAIN_TEX"
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
