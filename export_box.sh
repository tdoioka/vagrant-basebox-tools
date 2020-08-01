#!/bin/bash

set -ueo pipefail

err() {
  echo "$@" 1>&2
}
err_exit() {
  err "$@"
  exit 1
}
usage_exit() {
  local ret=$1
  if [[ $# -ge 2 ]]; then
    shift
    err "$@"
  fi
  cat << __eof__
$0 <VMNAME> <BOXNAME>

export VM to vagrant box image.

VMNAME:  VirtualBox machine name
BOXNAME: output filename without suffix(.box)
__eof__
  return "$ret"
}

cli=vboxmanage
sanity() {
  # check CLI name.
  type $cli >&/dev/null || cli=VBoxManage.exe
  type $cli >&/dev/null || err_exit "ERR: Not found vboxmanage command."

  # Check arguments.
  [[ $# -eq 2 ]] || usage_exit -1 "ERR: Argument error."

  # Check vm exists
  $cli list vms | grep "\"${1}\"" >&/dev/null || \
    usage_exit -1 "ERR: VMNAME is not exists"
}


WSL_WIN_USER=${WSL_WIN_USER:-$(whoami)}
addpath() {
  export PATH="$PATH:$1"
}
configuration() {
  if type wslpath &> /dev/null; then
    export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS="1"
    export VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH="/mnt/d/virtualbox"
    export VAGRANT_WSL_WINDOWS_ACCESS_USER="$WSL_WIN_USER"
    addpath "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/"
    addpath "/mnt/c/Windows/System32/"
    addpath "/mnt/c/Program Files/Oracle/VirtualBox"
  fi
}


main() {
  local hddinfo ctrl port device hddpath VMNAME BOXNAME
  VMNAME=$1
  BOXNAME=$2
  # Get HDD line.
  hddinfo=$($cli showvminfo "$VMNAME" |
                    grep -E '(vdi|vmdk)' | sort | head -n 1 )
  test -n "$hddinfo" || err_exit -1 "ERR: Not found HDD in $VMNAME"
  # shellcheck disable=SC2001
  ctrl=$(echo "$hddinfo" | sed -e 's@^\([A-Za-z0-9 ]*\) .*@\1@')
  # shellcheck disable=SC2001
  port=$(echo "$hddinfo" | sed -e 's@.*(\([0-9]*\), [0-9]*):.*@\1@')
  # shellcheck disable=SC2001
  device=$(echo "$hddinfo" | sed -e 's@.*[0-9], \([0-9]*\)):.*@\1@')
  # shellcheck disable=SC2001
  hddpath=$(echo "$hddinfo" | sed -e 's@^[^:]*: \(.*\) ([^(]*$@\1@g')

  # Power off if runnning
  if $cli list runningvms | grep "\"${1}\"" >&/dev/null ; then
    err "INFO: Shutdown VM ${1}"
    $cli controlvm "${1}" poweroff
  fi

  if [[ "${hddpath##*.}" != "vdi" ]]; then
    # TODO: this statements.
    # swap to vdi
    err "INFO: Non-vdi disk comvert ${hddpath}=>vdi"
    $cli clonemedium "${hddpath}" "${hddpath%.*}.vdi" --format vdi
    $cli storageattach "$VMNAME" --storagectl "$ctrl" --port "$port" --device "$device" \
         --medium none
    $cli storageattach "$VMNAME" --storagectl "$ctrl" --port "$port" --device "$device" \
         --type hdd --medium "${hddpath%.*}.vdi"
    $cli closemedium "${hddpath}" --delete
  fi
  # Shrink hdd.
  err "INFO: Shrink hdd image ${hddpath%.*}.vdi"
  $cli modifymedium "${hddpath%.*}.vdi" --compact
  err "INFO: convert ${hddpath%.*}.vdi=>vmdk"
  $cli clonemedium "${hddpath%.*}.vdi" "${hddpath%.*}.vmdk" --format vmdk
  $cli storageattach "$VMNAME" --storagectl "$ctrl" --port "$port" --device "$device" \
       --medium none
  $cli storageattach "$VMNAME" --storagectl "$ctrl" --port "$port" --device "$device" \
       --type hdd --medium "${hddpath%.*}.vmdk"
  $cli closemedium "${hddpath%.*}.vdi" --delete

  # Create box.
  if [[ -e "${BOXNAME}.box" ]] ; then
    err "INFO: backup box if exists"
    mv -v "${BOXNAME}.box" "${BOXNAME}.box.bk" --backup=t
  fi
  err "INFO: create boxfile ${BOXNAME}.box"
  vagrant package --base "$VMNAME" --out "${BOXNAME}.box"
  md5sum "${BOXNAME}.box" > "${BOXNAME}.box.md5sum"
}

configuration "$@"
sanity "$@"
main "$@"
