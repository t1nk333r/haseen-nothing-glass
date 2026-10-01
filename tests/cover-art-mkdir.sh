#!/usr/bin/env bash
set -euo pipefail
path=${!#}
if [[ $DIR_SCEN == collision && ! -e $DIR_STATE ]]; then
  # Occupy the candidate before the real exclusive mkdir. A retry must leave
  # the existing directory and its contents untouched, including at teardown.
  "$REAL_MKDIR" -m 700 -- "$path"
  printf '%s\n' "$path" > "$DIR_STATE"
  printf 'keep\n' > "$path/sentinel"
  "$REAL_MKDIR" "$@"
elif [[ $DIR_SCEN == mid-create ]]; then
  "$REAL_MKDIR" "$@"
  printf '%s\n' "$path" > "$DIR_STATE"
  sleep 2
else
  exec "$REAL_MKDIR" "$@"
fi
