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
# Version 1.8.7 - Robust path handling and runtime checks

##### CONFIG EXPORT / IMPORT LOCATION #####
export EXPIMPLOC=
###########################################

##### CONFIG CLIENT #######################
# DEFAULT (000), ALL or CLIENT Number
# Default Value = ALL
export EXPCLIENT=ALL
###########################################

##### CONFIG PARALLEL (SAP 1127194) #######
# DEFAULT 0, Max 1-2x CPU Count
export PARALLEL=0
###########################################

##### info ################################
# with this tool you can export and import
# tables from and into a sap system
# you have to run it as "sidadm"
# it use the normal R3trans for export
# and import with template files
####################(c) Florian Lamml 2025#

# Prerequisites ###########################
# need 'dialog' to run
###########################################

##### list of exit codes ##################
# general
# 99 - you try to run as "root"
# 98 - cannot find SAP SID
# 95 - cannot find R3trans
# 97 - cannot start dialog
# 96 - Hit ESC
# export
# 10 - exit because old run detected
# 11 - fail to select templates for export
# 12 - no template selected for export
# 13 - error while export
# 14 - export info error
# import
# 20 - no exports found for import
# 21 - exit because old run detected
# 22 - no OK exports found for import
# 23 - import select error
# 24 - no exports selected for import
# 25 - error while import
# 26 - import info error
###########################################

# set global variables
export global_pwd=$(pwd)
export global_height=25
export global_width=80
export global_list=20
export global_title="SAP Table EXP/IMP for SystemCopy (c) Florian Lamml 2025"
export global_backtitle="SAP Table EXP/IMP for SystemCopy (c) Florian Lamml 2025"
export global_copy="(c) Florian Lamml 2025"

wrap_dialog_text() {
  local text="$1"
  local wrap_width=$((global_width - 4))
  if [ "$wrap_width" -lt 10 ]; then
    wrap_width=10
  fi
  printf '%s\n' "$text" | fold -s -w "$wrap_width"
}

calculate_dialog_dimensions() {
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
    usable_height=25
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
    usable_width=80
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

calculate_dialog_dimensions

global_logo=$(cat <<'EOF'
   _______   ___
  / __/ _ | / _ \
 _\ \/ __ |/ ___/
/___/_/ |_/_/
 _________   ___  __   ____
/_  __/ _ | / _ )/ /  / __/
 / / / __ |/ _  / /__/ _/
/_/ /_/ |_/_/
   _____  _____  ______  ______
  / __/ |/_/ _ \/  _/  |/  / _ \
 / _/_>  </ ___// // /|_/ / ___/
/__/_/_/|_/_/  /___/_/  /_/_/
EOF
)

build_main_menu_message() {
  local info_loc info_path client_line os_line
  info_loc=$(wrap_dialog_text "INFO: $EXPIMPLOCINFO")
  info_path=$(wrap_dialog_text "INFO: $EXPIMPLOC")
  client_line=$(wrap_dialog_text "CLIENT: $EXPCLIENT | PARALLEL: $PARALLEL")
  os_line=$(wrap_dialog_text "OS: $OS | USER: $CURUSER | SAPSYSTEM: $SAPSYSTEMNAME")
  cat <<EOF
$global_logo

EXPORT or IMPORT Tables?

$info_loc
$info_path

$client_line
$os_line

$global_copy
EOF
}

# check export location (and create directory)
if [ -z "$EXPIMPLOC" ]; 
 then 
 export EXPIMPLOCINFO="EXPIMPLOC is not set, use default";
 export EXPIMPLOC=$global_pwd/expimp/$SAPSYSTEMNAME
else 
 export EXPIMPLOCINFO="EXPIMPLOC is set to"; 
fi
[ ! -d "$EXPIMPLOC" ] && mkdir -p "$EXPIMPLOC"

# set logfile
export EXPIMPLOGFILE=$EXPIMPLOC/EXP_IMP_LOG_$(date "+%d_%m_%Y").txt
printf '%s\n' "$(date "+%d.%m.%Y-%H:%M")" >> "$EXPIMPLOGFILE"

# root check
export CURUSER=$(whoami)
if [ "$CURUSER" == "root" ];
then
	echo "This script must not be run as root user!" 
	echo "... EXIT NOW"
	exit 99
fi 

# SAPSYSTEMNAME variable check (need for R3trans)
if [ -z "$SAPSYSTEMNAME" ];
 then
   echo "No SID found, is the user right?"
   echo "... EXIT NOW"
   exit 98
fi

# PARALLEL check empty variable
if [ -z "${PARALLEL}" ];
 then
	PARALLEL=0
fi

# check AIX and set PATH and LIBPATH to use linux dialog (build from dialog-1.2-20150225 with gcc-4.8.3-1.aix7.1 on AIX 7.1) on AIX
export OS=$(uname)
if [ "$OS" == AIX ]
then
export PATH=$PATH:$(pwd)/dialogaix/bin
export LIBPATH=$LIBPATH:$(pwd)/dialogaix/lib
chmod u+x "$(pwd)/dialogaix/bin/dialog"
fi

# check if dialog is running
dialog > /dev/null 2>&1
export DIAGCHECK=$(echo $?)
if [ "$DIAGCHECK" -ne 0 ];
 then
        echo "cannot start linux 'dialog' command"
        echo "... EXIT NOW"
        exit 97
fi

# check if R3trans is available
if ! command -v R3trans >/dev/null 2>&1;
 then
        echo "cannot find 'R3trans' command"
        echo "... EXIT NOW"
        exit 95
fi

# set executable to scripts
chmod u+x "$global_pwd/script/sap_export_tables.sh"
chmod u+x "$global_pwd/script/sap_import_tables.sh"

# EXPORT or IMPORT dialog
calculate_dialog_dimensions
menu_body=$(build_main_menu_message)
DIALOG=(dialog --title "$global_title" --backtitle "$global_backtitle" --radiolist "$menu_body" $global_height $global_width 2)
OPTIONS=("EXPORT" "Export SAP Tables" on "IMPORT" "Import SAP Tables" off)
EXPORIMP=$("${DIALOG[@]}" "${OPTIONS[@]}" 2>&1 >/dev/tty)
# check ESC hit
if [ $? -eq 255 ];
 then
	echo "Hit ESC"
	echo "... EXIT NOW"
	exit 96
fi

# EXPORT or IMPORT
for choice in $EXPORIMP
do
    case $choice in
        EXPORT)
			(
                        echo "Export SAP Tables" >> "$EXPIMPLOGFILE"
			# run export script
			$global_pwd/script/sap_export_tables.sh
			)
			export EXPIMPRUNRC=$(echo $?)
			export EXPIMPRUN="Export procedure finished with RC="
            ;;
        IMPORT)
			(
                        echo "Import SAP Tables" >> "$EXPIMPLOGFILE"
			# run import script
			$global_pwd/script/sap_import_tables.sh
			)
			export EXPIMPRUNRC=$(echo $?)
			export EXPIMPRUN="Import procedure finished with RC="
            ;;
    esac
done

# summary

calculate_dialog_dimensions
summary_text=$(cat <<EOF
$(wrap_dialog_text "$EXPIMPRUN$EXPIMPRUNRC")

$(wrap_dialog_text "Logfiles can be found in $EXPIMPLOC")
EOF
)

dialog --title "$global_title" --backtitle "$global_backtitle" --ok-label "EXIT" --msgbox "$summary_text" $global_height $global_width

# exit
clear
exit $EXPIMPRUNRC
