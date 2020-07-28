################################################################################
# Utility Functions
################################################################################

early_exit() {
    echo "exiting early..."
    exit 1
}


lookup_az_exception() {
    debug "lookup_az_exception():"
    if [ $# -ne 1 ]; then return 1; fi
    local az_name=${1}

    if [ -r ${az_map} ]; then
        grep "^${az_name}|" ${az_map} > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            grep "^${az_name}|" ${az_map} | cut -d '|' -f2
            return 0
        fi
    fi
    return 1
}

get_config_line() {
    if [ $# -lt 2 ]; then return 1; fi
    local key=${1}
    local column=${2}
    shift 2
    target_array=("$@")

    for elem in "${target_array[@]}"; do
        echo "${elem}" | grep "^${key}|" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            if [ "${column}" -ne 0 ]; then
                echo "${elem}" | cut -d '|' -f${column}
            else
                echo "${elem}"
            fi
            return 0
        fi
    done
    return 1
}

parse_config_line() {
    if [ $# -ne 1 ]; then return 1; fi
    cfg_line=${1}

    echo "${1}" | grep '|' > /dev/null 2>&1
    if [ $? -ne 0 ]; then echo "${1}"; return 0; fi

    local tmp_array=( )
    local field_idx=1
    local idx=0
    local field=$(echo "${cfg_line}" | cut -d '|' -f${field_idx})
    while [ -n "${field}" ]; do
        tmp_array[(idx++)]=${field}
        ((field_idx++))
        field=$(echo "${cfg_line}" | cut -d '|' -f${field_idx})
    done
    echo "${tmp_array[*]}"
}

update_image_path() {
    if [ $# -ne 2 ]; then return 1; fi
    local path1=${1}
    local path2=${2}

    # parse path1
    local n=$(echo "${path1}" | awk -F \/ '{print NF-2}')
    local s1="$(echo "${path1}" | cut -d \/ -f1-${n})/_base"

    # parse path2
    s2=$(echo "${path2}" | awk -F \/ '{print $NF}')

    echo "${s1}/${s2}"
}

in_array() {
  if [ $# -eq 0 ]; then return 1; fi

  local key=${1}
  shift
  defined_values=("$@")

  local value=""
  for value in "${defined_values[@]}"; do
    if [ "${value}" == "${key}" ]; then return 0; fi
  done

  return 1
}


convert_gb_to_bytes() {
    if [ $# -ne 1 ]; then return 1; fi
    local value_gb=${1}
    echo $(bc <<< "${value_gb} * 1000000000")
}


get_file_checksum() {
    if [ $# -ne 1 ]; then return 1; fi
    input_file=${1}

    # vallidate input file
    if [ ! -r ${input_file} ]; then
        echo "ERROR: input file not found: ${input_file}"
        return 1
    fi

    which md5sum > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "ERROR: missing md5sum package"
        return 1
    fi

    echo "$(md5sum ${input_file} | cut -d ' ' -f1)"
}

ensure_parent_dir() {
    if [ ! -d $(dirname $1) ]; then
        if ! (mkdir -p $(dirname $1)); then
            assert "Failed to create directory $(dirname $1)"
        fi
        if [ ! -d $(dirname $1) ]; then
            assert "Failed to create directory $(dirname $1)"
        fi
    fi
}

delete_remote_file() {
    debug "delete_remote_file():"
    if [ $# -ne 2 ]; then return 1; fi
    local ip_address=${1}
    local file_path=${2}
    local ssh_flags="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${ip_address} \
        "/bin/rm -f ${file_path}"
    return $?
}

