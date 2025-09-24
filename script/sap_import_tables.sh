#!/bin/bash
# SAP(R) Table EXP/IMP for SystemCopy (c) Florian Lamml 2025
# www.florian-lamml.de
# Version 1.0 - Initial Release
# Version 1.1 - Client Config
# Version 1.2 - New Tables
# Version 1.3 - Template Correction
# Version 1.4 - Minor Corrections
# Version 1.5 - Cloud ALM Template
# Version 1.6 - Corrections Cloud ALM and GTS Template
# Version 1.7 - More Templates
# Version 1.7.1 - More Templates Correction
# Version 1.7.2 - BD97 Template
# Version 1.8 - R3load Parallel Parameter
# Version 1.8.1 - More Templates
# Version 1.8.2 - More Templates
# Version 1.8.3 - $SAPSYSTEMNAME in default expimp location
# Version 1.8.4 - Correction of OAC0 Template
# Version 1.8.5 - OMIQ Template, Correction OAC0 Template
# Version 1.8.6 - Correct OAC0 Template
# Version 1.8.7 - Robust handling improvements
# Version 1.9 - Manual custom table selection

# set config file and delete old one
export exportedtables="$EXPIMPLOC/exported_tables.conf"
export customtablemap="$EXPIMPLOC/custom_table_map.conf"

ensure_dialog_dimensions() {
  local term_height term_width usable_height usable_width list_height

  term_height=$(tput lines 2>/dev/null || echo 0)
  term_width=$(tput cols 2>/dev/null || echo 0)

  if [ "$term_height" -gt 0 ]; then
    usable_height=$((term_height - 4))
    if [ "$usable_height" -lt 18 ]; then
      usable_height=$((term_height - 2))
    fi
    if [ "$usable_height" -lt 14 ]; then
      usable_height=14
    fi
    if [ "$usable_height" -gt 60 ]; then
      usable_height=60
    fi
    if [ "$usable_height" -ge "$term_height" ]; then
      usable_height=$((term_height - 1))
    fi
  else
    usable_height=${global_height:-25}
  fi

  if [ "$term_width" -gt 0 ]; then
    usable_width=$((term_width - 4))
    if [ "$usable_width" -lt 70 ]; then
      usable_width=$((term_width - 2))
    fi
    if [ "$usable_width" -lt 50 ]; then
      if [ "$term_width" -gt 4 ]; then
        usable_width=$((term_width - 2))
      else
        usable_width=50
      fi
    fi
    if [ "$usable_width" -gt 120 ]; then
      usable_width=120
    fi
    if [ "$usable_width" -le 0 ]; then
      usable_width=50
    fi
  else
    usable_width=${global_width:-80}
  fi

  export global_height=$usable_height
  export global_width=$usable_width

  list_height=$((global_height - 12))
  if [ "$list_height" -gt 35 ]; then
    list_height=35
  fi
  if [ "$list_height" -lt 8 ]; then
    list_height=8
  fi
  export global_list=$list_height
}

ensure_dialog_dimensions

get_custom_display_name() {
  local identifier="$1"
  local display="$identifier"
  if [ -s "$customtablemap" ]; then
    local map_line
    map_line=$(grep -F "^$identifier|" "$customtablemap" 2>/dev/null | head -n 1)
    if [ -n "$map_line" ]; then
      display=${map_line#*|}
    fi
  fi
  printf '%s' "$display"
}
if [ ! -s "$exportedtables" ]
 then
        echo "ERROR: no exports found for import" >> "$EXPIMPLOGFILE"
        exit 20
fi

# set config file
export exportedtablesok="$EXPIMPLOC/exported_tables_ok.conf"

# check existing data
if [ -e "$exportedtablesok" ]
 then
        ensure_dialog_dimensions
        dialog --title "$global_title" --backtitle "$global_backtitle"  --yes-label "Continue" --no-label "Exit" --yesno  "There are import files in $EXPIMPLOC\nIf you continue these files will be deleted!" $global_height $global_width
        CONTINUE=$?
        case $CONTINUE in
                        0)
                                echo "INFO: delete old files" >> "$EXPIMPLOGFILE"
                                rm -f -- "$exportedtablesok"
                                ;;
                        1|255)
                                echo "INFO: exit because old run detected" >> "$EXPIMPLOGFILE"
                                exit 21
                                ;;
        esac
fi

# build list of OK exports for import
export templist="$EXPIMPLOC/templist.conf"
[ -e "$templist" ] && rm -f -- "$templist"
while IFS= read -r line
 do
  case $line in
    ''|\#*)
      continue
      ;;
  esac
  printf '%s\n' "$line" >> "$templist"
done < "$exportedtables"
grep -E 'RC=(0|4)' "$templist" > "$exportedtablesok"
[ -e "$templist" ] && rm -f -- "$templist"
if [ ! -s "$exportedtablesok" ]
 then
        echo "ERROR: no OK exports found for import" >> "$EXPIMPLOGFILE"
        exit 22
fi

# set config file and delete old one
export importtables="$EXPIMPLOC/selected_tables_import.conf"
[ -e "$importtables" ] && rm -f -- "$importtables"

# select exports to import
IMPORTEDTABLES=()
while IFS= read -r IMPORTEDTABLES_LINE
do
  [ -z "$IMPORTEDTABLES_LINE" ] && continue
  table_name=${IMPORTEDTABLES_LINE%%|*}
  display_name=$(get_custom_display_name "$table_name")
  if [ "$display_name" != "$table_name" ]; then
    display_label="$display_name (custom)"
  else
    display_label="$display_name"
  fi
  IMPORTEDTABLES+=("$table_name" "$display_label" "on")
done < "$exportedtablesok"

ensure_dialog_dimensions
if ! dialog --title "$global_title" --backtitle "$global_backtitle" --separate-output --checklist "Select the exports to import:" $global_height $global_width $global_list "${IMPORTEDTABLES[@]}" 2> "$importtables"
 then
        echo "ERROR: import select error" >> "$EXPIMPLOGFILE"
        exit 23
fi
clear
if [ "$(wc -l < "$importtables")" -eq 0 ]
 then
        echo "ERROR: no exports selected for import" >> "$EXPIMPLOGFILE"
        exit 24
fi

if [ "$OS" == Linux ]
 then
  export listcleaner="$EXPIMPLOC/listcleaner.conf"
  sed 's/\"//g' "$importtables" > "$listcleaner"
  mv "$listcleaner" "$importtables"
fi

# export info file
export importedtables="$EXPIMPLOC/imported_tables.conf"
[ -e "$importedtables" ] && rm -f -- "$importedtables"

# info file
{
  printf '# Template name | Return Code of Import\n'
  printf '# =====================================\n'
  printf '# Imported from:\n'
  printf '# %s\n' "$EXPIMPLOC"
  printf '# =====================================\n'
} > "$importedtables"

# prepare progress logging
if command -v mktemp >/dev/null 2>&1; then
  progress_log=$(mktemp "$EXPIMPLOC/import_progress.XXXXXX")
else
  progress_log="$EXPIMPLOC/import_progress_$$.log"
fi
: > "$progress_log"
progress_pid=""
cleanup_progress() {
  if [ -n "$progress_pid" ]; then
    if command -v pgrep >/dev/null 2>&1; then
      while IFS= read -r child_pid; do
        [ -n "$child_pid" ] && kill "$child_pid" 2>/dev/null
      done < <(pgrep -P "$progress_pid" 2>/dev/null)
    else
      while IFS= read -r child_pid; do
        child_pid=${child_pid##*[[:space:]]}
        [ -n "$child_pid" ] && kill "$child_pid" 2>/dev/null
      done < <(ps -eo pid=,ppid= 2>/dev/null | awk -v p="$progress_pid" '$2 == p { print $1 }')
    fi
    kill "$progress_pid" 2>/dev/null
    wait "$progress_pid" 2>/dev/null
    progress_pid=""
  fi
  rm -f -- "$progress_log"
}
trap cleanup_progress EXIT
ensure_dialog_dimensions
(
  trap 'exit 0' TERM
  while true; do
    ensure_dialog_dimensions
    tail -n +1 -f "$progress_log" | dialog --title "$global_title" --backtitle "$global_backtitle" --progressbox "Import selected tables"  $global_height $global_width
    status=$?
    if [ "$status" -eq 3 ]; then
      continue
    fi
    break
  done
) &
progress_pid=$!

import_error=0
while IFS= read -r SELTABLES
 do
  [ -z "$SELTABLES" ] && continue
  display_name=$(get_custom_display_name "$SELTABLES")
  if [ "$display_name" != "$SELTABLES" ]; then
    progress_label="$display_name (custom)"
  else
    progress_label="$display_name"
  fi
  printf '=== Import START %s ===\n' "$progress_label" >> "$progress_log"
  R3trans -w "$EXPIMPLOC/$SELTABLES.imp.log" -i "$EXPIMPLOC/$SELTABLES.dat"
  rc=$?
  printf '%s|RC=%s\n' "$SELTABLES" "$rc" >> "$importedtables"
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 4 ]; then
    import_error=1
  fi
  printf '=== Import END %s ===\n\n' "$progress_label" >> "$progress_log"
  sleep 1
 done < "$importtables"

if [ -s "$customtablemap" ]
 then
  {
    printf '# Custom table mapping (file id -> table name)\n'
    while IFS='|' read -r map_id map_table
     do
      [ -z "$map_id" ] && continue
      printf '# %s -> %s\n' "$map_id" "$map_table"
    done < "$customtablemap"
  } >> "$importedtables"
fi
printf '# =====================================\n' >> "$importedtables"

cleanup_progress
trap - EXIT

# logfile info
echo "=== imported tables ===" >> "$EXPIMPLOGFILE"
cat "$importedtables" >> "$EXPIMPLOGFILE"
echo "=== imported tables ===" >> "$EXPIMPLOGFILE"

# import info
ensure_dialog_dimensions
if ! dialog --title "$global_title" --backtitle "$global_backtitle" --exit-label "Continue" --textbox "$importedtables" $global_height $global_width
 then
        echo "ERROR: import info error" >> "$EXPIMPLOGFILE"
        exit 26
fi
clear

if [ "$import_error" -ne 0 ]; then
  echo "ERROR: error while import" >> "$EXPIMPLOGFILE"
  echo "=== import finished (with errors) ===" >> "$EXPIMPLOGFILE"
  exit 25
fi

echo "=== import finished ===" >> "$EXPIMPLOGFILE"
exit 0
