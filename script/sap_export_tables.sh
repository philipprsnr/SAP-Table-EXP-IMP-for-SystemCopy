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
export selectedtablesforexport="$EXPIMPLOC/selected_tables_for_export.conf"
export exportedtables="$EXPIMPLOC/exported_tables.conf"
export customtables="$EXPIMPLOC/custom_tables_manual.conf"
export customtablemap="$EXPIMPLOC/custom_table_map.conf"

sanitize_table_name() {
  local input="$1"
  input=$(printf '%s' "$input" | tr '[:lower:]' '[:upper:]')
  input=$(printf '%s' "$input" | sed 's/^[[:space:]]\+//;s/[[:space:]]\+$//')
  input=${input//[$'\t\r\n ']}
  printf '%s' "$input"
}

generate_custom_identifier() {
  local table_name="$1"
  local sanitized
  sanitized=$(printf '%s' "$table_name" | sed 's/[^A-Za-z0-9_]/_/g')
  if [ -z "$sanitized" ]; then
    sanitized="CUSTOM_TABLE"
  else
    sanitized="CUSTOM_${sanitized}"
  fi
  local candidate="$sanitized"
  local counter=1
  while [ -e "$EXPIMPLOC/$candidate.dat" ] || \
        { [ -s "$customtablemap" ] && grep -Fq "^$candidate|" "$customtablemap"; } || \
        grep -Fq "^$candidate|" "$exportedtables" 2>/dev/null; do
    candidate="${sanitized}_${counter}"
    counter=$((counter + 1))
  done
  printf '%s' "$candidate"
}

prompt_custom_tables() {
  rm -f -- "$customtables" "$customtablemap"
  local tmp_input
  if command -v mktemp >/dev/null 2>&1; then
    tmp_input=$(mktemp "$EXPIMPLOC/custom_table_input.XXXXXX")
  else
    tmp_input="$EXPIMPLOC/custom_table_input_$$.tmp"
  fi
  local -a table_list=()
  local rc raw_input sanitized_input duplicate existing
  while true; do
    if ! dialog --title "$global_title" --backtitle "$global_backtitle" --ok-label "Add" --cancel-label "Finish" \
        --inputbox "Enter an additional table name to export/import.\n\nLeave empty and press Add to finish or press Finish to stop adding tables." \
        $global_height $global_width 2> "$tmp_input"; then
      rc=$?
      case $rc in
        1)
          break
          ;;
        255)
          rm -f -- "$tmp_input"
          exit 96
          ;;
      esac
    fi
    local raw_input
    raw_input=$(cat "$tmp_input")
    local sanitized_input
    sanitized_input=$(sanitize_table_name "$raw_input")
    if [ -z "$sanitized_input" ]; then
      break
    fi
    if ! printf '%s\n' "$sanitized_input" | grep -Eq '^[A-Z0-9_/$#]+$'; then
      dialog --title "$global_title" --backtitle "$global_backtitle" --msgbox "Table name $sanitized_input contains unsupported characters.\nOnly A-Z, 0-9, _, /, $ and # are allowed." 8 70
      continue
    fi
    local duplicate=0
    for existing in "${table_list[@]}"; do
      if [ "$existing" = "$sanitized_input" ]; then
        duplicate=1
        break
      fi
    done
    if [ "$duplicate" -eq 1 ]; then
      dialog --title "$global_title" --backtitle "$global_backtitle" --msgbox "Table $sanitized_input already added." 7 60
      continue
    fi
    table_list+=("$sanitized_input")
  done
  rm -f -- "$tmp_input"
  if [ ${#table_list[@]} -gt 0 ]; then
    : > "$customtables"
    for table_name in "${table_list[@]}"; do
      printf '%s\n' "$table_name" >> "$customtables"
    done
  fi
}

# check existing data
if [ -e "$selectedtablesforexport" ]
 then
        dialog --title "$global_title" --backtitle "$global_backtitle"  --yes-label "Continue" --no-label "Exit" --yesno  "There are export files in $EXPIMPLOC\nIf you continue these files will be deleted!" $global_height $global_width
        CONTINUE=$?
        case $CONTINUE in
                        0)
                                echo "INFO: delete old files" >> "$EXPIMPLOGFILE"
                                rm -f -- "$selectedtablesforexport"
                                [ -e "$exportedtables" ] && rm -f -- "$exportedtables"
                                [ -e "$customtables" ] && rm -f -- "$customtables"
                                [ -e "$customtablemap" ] && rm -f -- "$customtablemap"
                                ;;
                        1|255)
                                echo "INFO: exit because old run detected" >> "$EXPIMPLOGFILE"
                                exit 10
                                ;;
        esac
fi

# search templates
template_options=()
while IFS= read -r template_path
do
  [ -z "$template_path" ] && continue
  template_name=${template_path##*/}
  template_options+=("$template_name" "$template_name" "off")
done < <(find "$global_pwd/templates" -type f -print 2>/dev/null)

if [ ${#template_options[@]} -eq 0 ]; then
    echo "ERROR: fail to select templates for export (no templates found)" >> "$EXPIMPLOGFILE"
    exit 11
fi

if ! dialog --title "$global_title" --backtitle "$global_backtitle" --separate-output --checklist "Select the Templates for Export:" $global_height $global_width $global_list "${template_options[@]}" 2> "$selectedtablesforexport"
 then
    echo "ERROR: fail to select templates for export" >> "$EXPIMPLOGFILE"
        exit 11
fi
clear
if [ "$(wc -l < "$selectedtablesforexport")" -eq 0 ]
 then
        echo "ERROR: no template selected for export" >> "$EXPIMPLOGFILE"
        exit 12
fi

if [ "$OS" == Linux ]
 then
  export listcleaner="$EXPIMPLOC/listcleaner.conf"
  sed 's/\"//g' "$selectedtablesforexport" > "$listcleaner"
  mv "$listcleaner" "$selectedtablesforexport"
fi

prompt_custom_tables

# logfile info
echo "=== selected tables for export ===" >> "$EXPIMPLOGFILE"
cat "$selectedtablesforexport" >> "$EXPIMPLOGFILE"
echo "=== selected tables for export ===" >> "$EXPIMPLOGFILE"

if [ -s "$customtables" ]
 then
        echo "=== custom tables for export ===" >> "$EXPIMPLOGFILE"
        cat "$customtables" >> "$EXPIMPLOGFILE"
        echo "=== custom tables for export ===" >> "$EXPIMPLOGFILE"
fi

# delete old exports
for pattern in "$EXPIMPLOC"/*.tpl "$EXPIMPLOC"/*.exp.log "$EXPIMPLOC"/*.dat
 do
  [ -e "$pattern" ] && rm -f -- "$pattern"
done

# info file
{
  printf '# Template name | Return Code of Export\n'
  printf '# =====================================\n'
  printf '# Exported to:\n'
  printf '# %s\n' "$EXPIMPLOC"
  printf '# =====================================\n'
} > "$exportedtables"

# check STMS_QA export
if grep -q '^STMS_QA$' "$selectedtablesforexport"
then
 dialog --title "$global_title" --backtitle "$global_backtitle" --exit-label "Continue" --msgbox "You are going to export STMS_QA \n\n Please refresh STMS_QA before continue" $global_height $global_width
 # check ESC hit
 if [ $? -eq 255 ];
 then
        exit 96
 fi
fi

# prepare progress logging
if command -v mktemp >/dev/null 2>&1; then
  progress_log=$(mktemp "$EXPIMPLOC/export_progress.XXXXXX")
else
  progress_log="$EXPIMPLOC/export_progress_$$.log"
fi
: > "$progress_log"
progress_pid=""
cleanup_progress() {
  if [ -n "$progress_pid" ]; then
    kill "$progress_pid" 2>/dev/null
    wait "$progress_pid" 2>/dev/null
    progress_pid=""
  fi
  rm -f -- "$progress_log"
}
trap cleanup_progress EXIT
(
  trap 'exit 0' TERM
  while true; do
    tail -n +1 -f "$progress_log" | dialog --title "$global_title" --backtitle "$global_backtitle" --progressbox "Export SAP Tables"  $global_height $global_width
    status=$?
    if [ "$status" -eq 3 ]; then
      continue
    fi
    break
  done
) &
progress_pid=$!

export_error=0
while IFS= read -r SELTABLES
 do
  [ -z "$SELTABLES" ] && continue
  tpl_file="$EXPIMPLOC/$SELTABLES.tpl"
  {
    printf 'export\n'
    printf 'client = %s\n' "$EXPCLIENT"
    if [ "${PARALLEL}" -ne 0 ]; then
      printf 'parallel = %s\n' "$PARALLEL"
    fi
    printf "file = '%s/%s.dat'\n" "$EXPIMPLOC" "$SELTABLES"
  } > "$tpl_file"
  cat "$global_pwd/templates/$SELTABLES" >> "$tpl_file"
  printf '=== Export START %s ===\n' "$SELTABLES" >> "$progress_log"
  R3trans -w "$EXPIMPLOC/$SELTABLES.exp.log" "$tpl_file"
  rc=$?
  printf '%s|RC=%s\n' "$SELTABLES" "$rc" >> "$exportedtables"
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 4 ]; then
    export_error=1
  fi
  printf '=== Export END %s ===\n\n' "$SELTABLES" >> "$progress_log"
  sleep 1
 done < "$selectedtablesforexport"

if [ -s "$customtables" ]
 then
  : > "$customtablemap"
  while IFS= read -r CUSTOMTABLE
   do
    [ -z "$CUSTOMTABLE" ] && continue
    custom_identifier=$(generate_custom_identifier "$CUSTOMTABLE")
    tpl_file="$EXPIMPLOC/$custom_identifier.tpl"
    {
      printf 'export\n'
      printf 'client = %s\n' "$EXPCLIENT"
      if [ "${PARALLEL}" -ne 0 ]; then
        printf 'parallel = %s\n' "$PARALLEL"
      fi
      printf "file = '%s/%s.dat'\n" "$EXPIMPLOC" "$custom_identifier"
      printf 'delete from %s\n' "$CUSTOMTABLE"
      printf 'select * from %s\n' "$CUSTOMTABLE"
    } > "$tpl_file"
    printf '=== Export START %s (custom) ===\n' "$CUSTOMTABLE" >> "$progress_log"
    R3trans -w "$EXPIMPLOC/$custom_identifier.exp.log" "$tpl_file"
    rc=$?
    printf '%s|RC=%s\n' "$custom_identifier" "$rc" >> "$exportedtables"
    printf '%s|%s\n' "$custom_identifier" "$CUSTOMTABLE" >> "$customtablemap"
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 4 ]; then
      export_error=1
    fi
    printf '=== Export END %s (custom) ===\n\n' "$CUSTOMTABLE" >> "$progress_log"
    sleep 1
  done < "$customtables"
fi

if [ -s "$customtablemap" ]
 then
  {
    printf '# Custom table mapping (file id -> table name)\n'
    while IFS='|' read -r map_id map_table
     do
      [ -z "$map_id" ] && continue
      printf '# %s -> %s\n' "$map_id" "$map_table"
    done < "$customtablemap"
  } >> "$exportedtables"
fi
printf '# =====================================\n' >> "$exportedtables"

cleanup_progress
trap - EXIT

# logfile info
echo "=== exported tables ===" >> "$EXPIMPLOGFILE"
cat "$exportedtables" >> "$EXPIMPLOGFILE"
echo "=== exported tables ===" >> "$EXPIMPLOGFILE"

# export info
if ! dialog --title "$global_title" --backtitle "$global_backtitle" --exit-label "Continue" --textbox "$exportedtables" $global_height $global_width
 then
        echo "ERROR: export info error" >> "$EXPIMPLOGFILE"
        exit 14
fi
clear

if [ "$export_error" -ne 0 ]; then
  echo "ERROR: error while export" >> "$EXPIMPLOGFILE"
  echo "=== export finished (with errors) ===" >> "$EXPIMPLOGFILE"
  exit 13
fi

echo "=== export finished ===" >> "$EXPIMPLOGFILE"
exit 0
