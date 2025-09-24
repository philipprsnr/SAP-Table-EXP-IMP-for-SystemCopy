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

# set config file and delete old one
export selectedtablesforexport="$EXPIMPLOC/selected_tables_for_export.conf"
export exportedtables="$EXPIMPLOC/exported_tables.conf"

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

# logfile info
echo "=== selected tables for export ===" >> "$EXPIMPLOGFILE"
cat "$selectedtablesforexport" >> "$EXPIMPLOGFILE"
echo "=== selected tables for export ===" >> "$EXPIMPLOGFILE"

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
