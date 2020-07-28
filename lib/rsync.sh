# data migration functions (rsync/ssh)

dd_source_to_target() {
    if [ $# -ne 11 ]; then return 1; fi
    local source_ip=${1}
    local source_lv_name=${2}
    local source_path=${3}
    local volume_group=${4}
    local snapshot_name=${5}
    local snapshot_path=${6}
    local target_ip=${7}
    local target_path=${8}
    local ssh_user=${9}
    local ssh_key=${10}
    local lv_size_bytes=${11}
    local ssh_flags="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    local start_time=$(date +"%s.%N")
    local dd_flags="ibs=${dd_blocksize} obs=${dd_blocksize}"

    # delete snapshot (if exists)
    lvm_snapshot_exists ${source_ip} ${snapshot_name}
    if [ $? -eq 0 ]; then
        lvm_delete_snapshot ${source_ip} ${volume_group} ${snapshot_name}
    fi

    # create snapshot of logical volume
    lvm_create_snapshot ${source_ip} ${snapshot_name} ${source_path} ${lvm_snapshot_buffer_size}
    if [ $? -ne 0 ]; then return 1; fi

    # set target for dd [$snapshot_path | $source_path]
    dd_source=${snapshot_path}

    # retry loop (dd the snapshot to target Cinder node)
    local cnt=0
    while [ ${cnt} -lt ${RETRY_ATTEMPTS} ]; do
        if [ ${cnt} -gt 0 ]; then stdout "----- retry ${cnt} -----"; fi
        stdout "--> Copying source LV to target Cinder node (migrating volume)"
        cmd="sudo dd ${dd_flags} if=${dd_source} | ssh ${ssh_flags} -i ${ssh_key} ${ssh_user}@${target_ip} 'sudo dd ${dd_flags} of=${target_path} '"
        ssh -i ${ssh_key} ${ssh_flags} ${ssh_user}@${source_ip} ${cmd} 2>/dev/null | debug
        if [ $? -eq 0 ]; then break; fi
        sleep ${RETRY_DELAY}
        ((cnt++))
    done
    if [ ${cnt} -ge ${RETRY_ATTEMPTS} ]; then return 1; fi

    # delete snapshot (if exists)
    stdout "--> CLEANUP: removing snapshot on source Cinder node (snapshot_name = ${snapshot_name})"
    lvm_snapshot_exists ${source_ip} ${snapshot_name}
    if [ $? -eq 0 ]; then
        lvm_delete_snapshot ${source_ip} ${volume_group} ${snapshot_name}
    fi

    # calculate transer rate
    local end_time=$(date +"%s.%N")
    local elsapsed_time=$(echo "${end_time} - ${start_time}" | bc)
    local transfer_rate=$(echo "${lv_size_bytes} / ${elsapsed_time}" | bc)
    local transfer_rate_mbs=$(echo "scale=2; (${transfer_rate} * 8) / 1000000" | bc)
    stdout "    Transfer Rate: ${transfer_rate_mbs} Mbps (elapsed_time = ${elsapsed_time} seconds)"
    return 0
}

scp_target_to_source() {
    debug "scp_target_to_source()"
    if [ $# -ne 7 ]; then return 1; fi
    local source_ip=${1}
    local source_path=${2}
    local target_ip=${3}
    local target_path=${4}
    local ssh_user=${5}
    local ssh_key=${6}
    local image_size_bytes=${7}
    local ssh_flags="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    local start_time=$(date +"%s.%N")

    # retry loop
    local cnt=0
    while [ ${cnt} -lt ${RETRY_ATTEMPTS} ]; do
        ssh_cmd="ssh -i ${ssh_key} ${ssh_flags} ${ssh_user}@${target_ip}"
        scp_cmd="sudo scp -i '${ssh_key}' ${ssh_flags} ${ssh_user}@${source_ip}:${source_path} ${target_path}"
        cmd="${ssh_cmd} ${scp_cmd}"
        debug "${cmd}"
        if eval ${cmd} |& debug; then break; fi
        sleep ${RETRY_DELAY}
        ((cnt++))
    done
    if [ ${cnt} -ge ${RETRY_ATTEMPTS} ]; then return 1; fi

    # calculate transer rate
    local end_time=$(date +"%s.%N")
    local elsapsed_time=$(echo "${end_time} - ${start_time}" | bc)
    local transfer_rate=$(echo "${image_size_bytes} / ${elsapsed_time}" | bc)
    local transfer_rate_mbs=$(echo "scale=2; (${transfer_rate} * 8) / 1000000" | bc)
    stdout "    Transfer Rate: ${transfer_rate_mbs} Mbps (elapsed_time = ${elsapsed_time} seconds)"
    return 0
}


rsync_source_to_target() {
    debug "rsync_source_to_target()"
    if [ $# -ne 7 ]; then return 1; fi
    local source_ip=${1}
    local source_path=${2}
    local target_ip=${3}
    local target_path=${4}
    local ssh_user=${5}
    local ssh_key=${6}
    local image_size_bytes=${7}
    local ssh_flags="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    local start_time=$(date +"%s.%N")

    # retry loop (resumes file transfers on failure)
    local cnt=0
    while [ ${cnt} -lt ${RETRY_ATTEMPTS} ]; do
        if [ ${cnt} -eq 0 ]; then
            cmd="rsync ${rsync_flags} --partial --rsync-path=\"sudo rsync\" -e \"ssh -i ${ssh_key} ${ssh_flags}\" ${source_path} ${ssh_user}@${target_ip}:${target_path}"
        else
            cmd="rsync ${rsync_flags} --append  --rsync-path=\"sudo rsync\" -e \"ssh -i ${ssh_key} ${ssh_flags}\" ${source_path} ${ssh_user}@${target_ip}:${target_path}"
        fi
        debug "ssh -i ${ssh_key} ${ssh_user}@${source_ip} ${cmd}"
        ssh -i ${ssh_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${ssh_user}@${source_ip} ${cmd} 2>/dev/null | debug
        if [ $? -eq 0 ]; then break; fi
        sleep ${RETRY_DELAY}
        ((cnt++))
    done
    if [ ${cnt} -ge ${RETRY_ATTEMPTS} ]; then return 1; fi

    # calculate transer rate
    local end_time=$(date +"%s.%N")
    local elsapsed_time=$(echo "${end_time} - ${start_time}" | bc)
    local transfer_rate=$(echo "${image_size_bytes} / ${elsapsed_time}" | bc)
    local transfer_rate_mbs=$(echo "scale=2; (${transfer_rate} * 8) / 1000000" | bc)
    stdout "    Transfer Rate: ${transfer_rate_mbs} Mbps (elapsed_time = ${elsapsed_time} seconds)"
    return 0
}


rsync_file_from_remote() {
    debug "rsync_file_from_remote()"
    if [ $# -ne 5 ]; then return 1; fi
    local remote_ip=${1}
    local remote_path=${2}
    local local_path=${3}
    local ssh_user=${4}
    local ssh_key=${5}
    local ssh_flags="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    local start_time=$(date +"%s.%N")

    # retry loop (resumes file transfers on failure)
    local cnt=0
    while [ ${cnt} -lt ${RETRY_ATTEMPTS} ]; do
        if [ ${cnt} -eq 0 ]; then
            cmd="rsync ${rsync_flags} --partial -e \"ssh -i ${ssh_key} ${ssh_flags}\" ${ssh_user}@${remote_ip}:${remote_path} ${local_path}"
        else
            cmd="rsync ${rsync_flags} --append -e \"ssh -i ${ssh_key} ${ssh_flags}\" ${ssh_user}@${remote_ip}:${remote_path} ${local_path}"
        fi
        debug "${cmd}"
        eval ${cmd} > /dev/null 2>&1
        if [ $? -eq 0 ]; then break; fi
        sleep ${RETRY_DELAY}
        ((cnt++))
    done
    if [ ${cnt} -ge ${RETRY_ATTEMPTS} ]; then return 1; fi

    # calculate transer rate
    local image_size_bytes=$(ls -l ${local_path} | cut -d ' ' -f5)
    local end_time=$(date +"%s.%N")
    local elsapsed_time=$(echo "${end_time} - ${start_time}" | bc)
    local transfer_rate=$(echo "${image_size_bytes} / ${elsapsed_time}" | bc)
    local transfer_rate_mbs=$(echo "scale=2; (${transfer_rate} * 8) / 1000000" | bc)
    stdout "    Transfer Rate: ${transfer_rate_mbs} Mbps (elapsed_time = ${elsapsed_time} seconds)"
    return 0
}


rsync_file_to_remote() {
    debug "rsync_file_to_remote()"
    if [ $# -ne 5 ]; then return 1; fi
    local remote_ip=${1}
    local remote_path=${2}
    local local_path=${3}
    local ssh_user=${4}
    local ssh_key=${5}
    local ssh_flags="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    local start_time=$(date +"%s.%N")

    # retry loop (resumes file transfers on failure)
    stdout "--> Performing direct transfer of backing LV to target hypervisor"
    local cnt=0
    while [ ${cnt} -lt ${RETRY_ATTEMPTS} ]; do
        if [ ${cnt} -eq 0 ]; then
            cmd="rsync ${rsync_flags} --partial --rsync-path=\"sudo rsync\" -e \"ssh -i ${ssh_key} ${ssh_flags}\" ${local_path} ${ssh_user}@${remote_ip}:${remote_path}"
        else
            cmd="rsync ${rsync_flags} --append --rsync-path=\"sudo rsync\" -e \"ssh -i ${ssh_key} ${ssh_flags}\" ${local_path} ${ssh_user}@${remote_ip}:${remote_path}"
        fi
        debug "${cmd}"
        eval ${cmd} > /dev/null 2>&1
        if [ $? -eq 0 ]; then break; fi
        sleep ${RETRY_DELAY}
        ((cnt++))
    done
    if [ ${cnt} -ge ${RETRY_ATTEMPTS} ]; then return 1; fi

    # calculate transer rate
    local image_size_bytes=$(ls -l ${local_path} | cut -d ' ' -f5)
    local end_time=$(date +"%s.%N")
    local elsapsed_time=$(echo "${end_time} - ${start_time}" | bc)
    local transfer_rate=$(echo "${image_size_bytes} / ${elsapsed_time}" | bc)
    local transfer_rate_mbs=$(echo "scale=2; (${transfer_rate} * 8) / 1000000" | bc)
    stdout "    Transfer Rate: ${transfer_rate_mbs} Mbps (elapsed_time = ${elsapsed_time} seconds)"
    return 0
}
