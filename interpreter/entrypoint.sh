#!/usr/bin/env bash
#
# Setzt Open Interpreter auf das LiteLLM des Stacks an und hängt die
# Argumente des Aufrufers hinten dran.
#
# Die Flag-Namen stammen aus Open Interpreter 0.4.x (--api_base, --api_key,
# --model, --context_window, --max_tokens) — mit Unterstrich, nicht mit
# Bindestrich. Open Interpreter benutzt intern litellm; damit litellm den
# LiteLLM-Proxy als OpenAI-kompatiblen Endpunkt anspricht (und nicht selbst
# versucht, Ollama zu erraten), muss dem Modellnamen "openai/" vorangehen:
#
#   LiteLLM kennt das Modell als   ollama/gemma3:12b
#   Open Interpreter braucht       openai/ollama/gemma3:12b
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -euo pipefail

API_BASE="${INTERPRETER_API_BASE:-http://litellm:4000/v1}"
API_KEY="${LITELLM_MASTER_KEY:-}"
MODEL="${INTERPRETER_MODEL:-ollama/gemma3:12b}"
CONTEXT="${INTERPRETER_CONTEXT_WINDOW:-16384}"
MAX_TOKENS="${INTERPRETER_MAX_TOKENS:-4096}"

# "openai/" nur voranstellen, wenn es nicht schon dasteht — so kann man in der
# .env auch einen vollqualifizierten Namen setzen, ohne dass er doppelt wird.
case "$MODEL" in
  openai/*) ;;
  *) MODEL="openai/${MODEL}" ;;
esac

# Die pkg_resources-Deprecation-Warnung taucht trotz "setuptools<81" im
# Dockerfile weiterhin auf und ist rein kosmetisch, kein Fehler - gezielt
# ausblenden, damit echte Warnungen von anderswo weiter sichtbar bleiben.
#
# WICHTIG - warum nach Nachrichtentext statt nach Modul gefiltert wird:
# pkg_resources ruft warnings.warn(..., stacklevel=2) auf. Das laesst die
# Warnung auf die AUFRUFENDE Datei zeigen (system_debug_info.py), nicht auf
# pkg_resources selbst - ein Filter nach Modul "pkg_resources" greift dann
# ins Leere (an einer echten Installation beobachtet: blieb trotz Filter
# sichtbar). Der Nachrichtentext bleibt unabhaengig vom stacklevel gleich.
export PYTHONWARNINGS="${PYTHONWARNINGS:-}${PYTHONWARNINGS:+,}ignore:pkg_resources is deprecated as an API:UserWarning"

if [ -z "$API_KEY" ]; then
  echo "LITELLM_MASTER_KEY ist nicht gesetzt — Open Interpreter kommt so nicht an LiteLLM." >&2
  echo "Prüfe die .env im Projektverzeichnis und starte erneut." >&2
  exit 1
fi

set -- --api_base "$API_BASE" \
       --api_key "$API_KEY" \
       --model "$MODEL" \
       --context_window "$CONTEXT" \
       --max_tokens "$MAX_TOKENS" \
       "$@"

exec interpreter "$@"
