################################################################################
# Functions for discovering & migrating Cinder volumes
################################################################################

create_empty_volume() {
    debug "create_empty_volume():"
    if [ $# -lt 5 ]; then return; fi
    local openstack_rc=${1}
    local project_name=${2}
    local volume_name=${3}
    local is_bootable=${4}
    local volume_size=${5}
    local volume_type=""
    if [ $# -eq 6 ]; then volume_type=${6}; fi

    # manage boot flag
    if [ "${is_bootable}" == "true" ]; then
        flag_bootable="--bootable"
    else
        flag_bootable=""
    fi

    if [ -n "${volume_type}" ]; then
        local cmd="openstack --os-project-name ${project_name} volume create ${flag_bootable} --type ${volume_type} --size ${volume_size} ${volume_name}"
    else
        local cmd="openstack --os-project-name ${project_name} volume create ${flag_bootable} --size ${volume_size} ${volume_name}"
    fi
    debug "    cmd: ${cmd}"
    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd} | debug
}


validate_lv_path_on_cinder_node() {
    debug "validate_lv_path_on_cinder_node():"
    if [ $# -ne 1 ]; then return 1; fi
    local source_lv_path=${1}
    local cinder_ip_address=$(echo "${source_lv_path}" | cut -d ':' -f1)
    local cinder_lv_path=$(echo "${source_lv_path}" | cut -d ':' -f2)

    cmd="if [ -L ${cinder_lv_path} ]; then exit 0; else exit 1; fi"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${source_ssh_privatekey} ${source_ssh_username}@${cinder_ip_address} ${cmd} 2>/dev/null
}

lookup_volume_type() {
    debug "lookup_volume_type():"
    if [ $# -ne 1 ]; then return 1; fi
    local project_name=${1}

    if [ -r ${volume_type_map} ]; then
        grep "^${project_name}|" ${volume_type_map} > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            grep "^${project_name}|" ${volume_type_map} | cut -d '|' -f2
            return 0
        fi
    fi
    return 1
}

lookup_cinder_device_basename() {
    debug "lookup_cinder_device_basename():"
    if [ $# -ne 1 ]; then return 1; fi
    local cinder_hostname=${1}

    if [ -r ${cinder_map} ]; then
        grep "^${cinder_hostname}|" ${cinder_map} > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            grep "^${cinder_hostname}|" ${cinder_map} | cut -d '|' -f4
            return 0
        fi
    fi
    return 1
}

lookup_cinder_vol_basename() {
    debug "lookup_cinder_vol_basename():"
    if [ $# -ne 1 ]; then return 1; fi
    local cinder_hostname=${1}

    if [ -r ${cinder_map} ]; then
        grep "^${cinder_hostname}|" ${cinder_map} > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            grep "^${cinder_hostname}|" ${cinder_map} | cut -d '|' -f3
            return 0
        fi
    fi
    return 1
}

lookup_cinder_host_ip() {
    debug "lookup_cinder_host_ip():"
    if [ $# -ne 1 ]; then return 1; fi
    local cinder_hostname=${1}

    if [ -r ${cinder_map} ]; then
        grep "^${cinder_hostname}|" ${cinder_map} > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            grep "^${cinder_hostname}|" ${cinder_map} | cut -d '|' -f2
            return 0
        fi
    fi
    return 1
}


get_volume_backend() {
    debug "get_volume_backend():"
    if [ $# -ne 1 ]; then return 1; fi
    local volume_db=${1}

    cat ${volume_db} | jq '."os-vol-host-attr:host"' | sed -e "s/\"//g"
}

get_volume_lv_size() {
    debug "get_volume_lv_size():"
    if [ $# -ne 1 ]; then return 1; fi
    local volume_db=${1}

    cat ${volume_db} | jq '."size"' | sed -e "s/\"//g"
}

migrate_volume_lvm_rsync() {
    debug "migrate_volume_lvm_rsync():"
    if [ $# -ne 9 ]; then return; fi
    local instance_uuid=${1}
    local volume_name=${2}
    local volume_uuid=${3}
    local mig_status=${4}
    local mig_name_id=${5}
    local is_bootable=${6}
    local project_name=${7}
    local source_rc=${8}
    local target_rc=${9}
    stdout "\n[Cinder Volume Migration]"
    stdout "--> Source volume: ${volume_name}"

    ##########################################################################################
    # SOURCE CLOUD
    ##########################################################################################
    # manage volume discovery cache
    local volume_db=${pkg_basedir}/db/${volume_uuid}.json
    ensure_parent_dir ${volume_db}
    if [ -r ${volume_db} ]; then rm -f ${volume_db}; fi

    # get volume metadata (json)
    get_volume ${source_rc} ${volume_uuid} ${volume_db}
    if [ $? -ne 0 ]; then assert "failed to get volume metadata"; fi

    # detach volume
    if [ "${is_bootable}" == "false" ]; then
        stdout "--> Detaching volume from instance"
        volume_attached ${source_rc} ${instance_uuid} ${volume_uuid}
        if [ $? -eq 0 ]; then
            detach_volume ${source_rc} ${instance_uuid} ${volume_uuid}
            if [ $? -ne 0 ]; then return 1; fi
        fi
    fi

    # get cinder backend for volume
    local v_backend=$(get_volume_backend ${volume_db})
    if [ -z "${v_backend}" ]; then assert "ERROR: failed to lookup volume backend"; fi

    # get volume size
    local v_size=$(get_volume_lv_size ${volume_db})
    if [ -z "${v_size}" ]; then assert "ERROR: failed to lookup volume size"; fi
    v_size_bytes=$(bc <<< "${v_size} * (1024^3)")

    # parse backend components
    local v_host=$(echo "${v_backend}" | cut -d '@' -f1)
    local v_storage_metadata=$(echo "${v_backend}" | cut -d '@' -f2)
   
    # map LV path
    local source_cinder_ip=$(lookup_cinder_host_ip ${v_host})
    if [ -z "${source_cinder_ip}" ]; then assert "ERROR: failed to map Cinder node: ${v_host} (update ${cinder_map})"; fi
    local cinder_volume_basename=$(lookup_cinder_vol_basename ${v_host})
	if [ "${mig_status}" == "success" ]; then
		local source_lv_name="${cinder_volume_basename}${mig_name_id}"
	else
		local source_lv_name="${cinder_volume_basename}${volume_uuid}"
	fi
    local cinder_device_basename=$(lookup_cinder_device_basename ${v_host})
    local lvm_volume_group=$(echo "${cinder_device_basename}" | awk -F \/ '{print $NF}')
    debug "DBG: mig_status = ${mig_status}"
    debug "DBG: mig_name_id = ${mig_name_id}"
	if [ "${mig_status}" == "success" ]; then
		local source_lv_path="${cinder_device_basename}/${cinder_volume_basename}${mig_name_id}"
	else
		local source_lv_path="${cinder_device_basename}/${cinder_volume_basename}${volume_uuid}"
	fi
    local snapshot_name="${volume_uuid}-snapshot"
    local snapshot_path="${cinder_device_basename}/${snapshot_name}"
    stdout "--> LV Path (source hypervisor): ${source_cinder_ip}:${source_lv_path}"

    # validate LV path on Cinder node
    validate_lv_path_on_cinder_node "${source_cinder_ip}:${source_lv_path}"
    if [ $? -ne 0 ]; then assert "ERROR: failed to validate LV path on source Cinder node"; fi

    ##########################################################################################
    # TARGET CLOUD
    ##########################################################################################
    # create volume on target cloud
    if [ "${is_bootable}" == "true" ]; then
        stdout "--> Creating bootable volume on target cloud: ${volume_name} (size = ${v_size})"
    else
        stdout "--> Creating non-bootable volume on target cloud: ${volume_name} (size = ${v_size})"
    fi
    if ! volume_exists ${target_rc} ${volume_name} ${project_name}; then
        create_empty_volume ${target_rc} ${project_name} ${volume_name} ${is_bootable} ${v_size} $(lookup_volume_type ${project_name})
        if [ $? -ne 0 ]; then assert "ERROR: failed to create volume"; fi
    fi
    if ! volume_exists ${target_rc} ${volume_name} ${project_name}; then
        stdout "ERROR: failed to validate volume on target cloud"
        return 1
    fi

    # get volume id (for volume just created)
    local target_volume_id=$(get_volume_id ${target_rc} ${volume_name} ${project_name})
    if [ -z "${target_volume_id}" ]; then assert "ERROR: failed to get volume uuid"; fi

    # manage volume discovery cache
    local target_volume_db=${pkg_basedir}/db/${target_volume_id}.json
    ensure_parent_dir ${target_volume_db}
    if [ -r ${target_volume_db} ]; then rm -f ${target_volume_db}; fi

    # get volume metadata (json)
    get_volume ${target_rc} ${target_volume_id} ${target_volume_db}
    if [ $? -ne 0 ]; then assert "failed to get volume metadata"; fi

    # get cinder backend for volume
    local target_v_backend=$(get_volume_backend ${target_volume_db})
    if [ -z "${target_v_backend}" ]; then assert "ERROR: failed to lookup volume backend"; fi

    # parse backend components
    v_host=$(echo "${target_v_backend}" | cut -d '@' -f1)
    v_storage_metadata=$(echo "${target_v_backend}" | cut -d '@' -f2)
   
    # map LV path
    local target_cinder_ip=$(lookup_cinder_host_ip ${v_host})
    if [ -z "${target_cinder_ip}" ]; then assert "ERROR: failed to map Cinder node: ${v_host} (update ${cinder_map})"; fi
    cinder_volume_basename=$(lookup_cinder_vol_basename ${v_host})
    cinder_device_basename=$(lookup_cinder_device_basename ${v_host})
    local target_lv_path="${cinder_device_basename}/${cinder_volume_basename}${target_volume_id}"
    stdout "--> LV Path (target hypervisor): ${target_cinder_ip}:${target_lv_path}"

    # validate LV path on Cinder node
    validate_lv_path_on_cinder_node "${target_cinder_ip}:${target_lv_path}"
    if [ $? -ne 0 ]; then assert "ERROR: failed to validate LV path on Cinder node, backend=${target_v_backend}"; fi

    ##########################################################################################
    # MIGRATE LV
    ##########################################################################################
    # copy images from SOUCE hypervisor to TARGET hypervisor
    dd_source_to_target ${source_cinder_ip} ${source_lv_name} ${source_lv_path} ${lvm_volume_group} ${snapshot_name} ${snapshot_path} ${target_cinder_ip} ${target_lv_path} ${source_ssh_username} ${source_ssh_privatekey} ${v_size_bytes}
    if [ $? -ne 0 ]; then assert "ERROR: failed to copy LV to target Cinder node"; fi

    # re-attach volume
    if [ "${is_bootable}" == "false" ]; then
        stdout "--> Re-attaching volume to source instance"
        volume_attached ${source_rc} ${instance_uuid} ${volume_uuid}
        if [ $? -ne 0 ]; then
            attach_volume ${source_rc} ${instance_uuid} ${volume_uuid}
            if [ $? -ne 0 ]; then return 1; fi
        fi
    fi

    return 0
}
