#!/usr/bin/env bash
#
# Kleine Helfer zum Lesen und Schreiben der .env — gemeinsam genutzt von
# service-credentials.sh und librechat-user.sh.
#
# Hintergrund: install.sh schreibt die .env bei jedem Lauf neu und übernimmt
# dabei vorhandene Werte. Neue Schlüssel landen dadurch aber NUR dort, wo der
# Installer seither einmal gelaufen ist. Bei einer älteren Installation fehlen
# sie schlicht — und ein Skript, das sie voraussetzt, scheitert dann mit
# "fehlt in der .env", obwohl der Nutzer alles richtig gemacht hat.
#
# env_ensure() schließt genau diese Lücke: fehlt ein Schlüssel, wird er
# erzeugt und nachgetragen, statt abzubrechen.
#
# Wird gesourct, nicht ausgeführt. Erwartet $ENV_FILE.
#
# This file is part of Self-Hosted AI Stack. MIT License.

# Zufalls-String. '|| true' fängt das SIGPIPE von tr ab (head schließt die
# Pipe früh) — sonst bricht ein Aufrufer mit 'set -o pipefail' hier ab.
env_rand() { LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "${1:-32}" || true; }

# Wert eines Schlüssels AUS DER DATEI lesen (nicht aus der Umgebung — dort
# könnte ein alter Wert von einem früheren source stehen).
env_get() {
  local key="$1"
  [ -f "$ENV_FILE" ] || return 1
  sed -n "s/^${key}=//p" "$ENV_FILE" | tail -1
}

# KEY=WERT schreiben: vorhandene Zeile ersetzen, sonst anhängen.
# Der Wert geht über eine Umgebungsvariable an awk — mit sed würden Zeichen
# wie & oder / im Wert als Ersetzungsmuster gedeutet und ihn verstümmeln.
env_set() {
  local key="$1" val="$2" tmp
  if [ ! -f "$ENV_FILE" ]; then
    printf '%s=%s\n' "$key" "$val" > "$ENV_FILE" || return 1
    chmod 600 "$ENV_FILE" 2>/dev/null || true
    return 0
  fi
  tmp="$(mktemp "${ENV_FILE}.XXXXXX")" || return 1
  KEY="$key" VAL="$val" awk '
    BEGIN { key = ENVIRON["KEY"]; val = ENVIRON["VAL"]; done = 0 }
    $0 ~ "^" key "=" { print key "=" val; done = 1; next }
    { print }
    END { if (!done) print key "=" val }
  ' "$ENV_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod --reference="$ENV_FILE" "$tmp" 2>/dev/null || chmod 600 "$tmp"
  mv "$tmp" "$ENV_FILE"
}

# Schlüssel nachtragen, falls er fehlt oder leer ist.
# Rückgabe 0 = nachgetragen, 1 = war schon da.
# Die nachgetragenen Namen sammeln sich in $ENV_ADDED, damit der Aufrufer
# das sichtbar machen kann — stille Änderungen an der .env wären unschön.
ENV_ADDED=""
env_ensure() {
  local key="$1" val="$2" cur
  cur="$(env_get "$key")"
  if [ -n "$cur" ]; then
    export "${key}=${cur}"
    return 1
  fi
  env_set "$key" "$val" || return 2
  export "${key}=${val}"
  ENV_ADDED="${ENV_ADDED}${ENV_ADDED:+ }${key}"
  return 0
}

# Meldet einmal, was ergänzt wurde.
env_report_added() {
  [ -n "$ENV_ADDED" ] || return 0
  printf '  %sIn die .env ergänzt: %s%s\n' "${c_dim:-}" "$ENV_ADDED" "${c_reset:-}"
  ENV_ADDED=""
}
