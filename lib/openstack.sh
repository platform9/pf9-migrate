################################################################################
# Openstack Functions
################################################################################

get_token() {
    debug "get_token():"
    if [ $# -ne 1 ]; then return 1; fi
    local openstack_rc=${1}
 
    local cmd="openstack token issue -f json"
    debug "    cmd: ${cmd}"
    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd} | jq '.id' | sed -e "s/\"//g"
    return $?
}


server_group_exists() {
    debug "server_group_exists():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local server_group_name=${2}

    local cmd="openstack server group list -c ID -c Name -f value"
    debug "    cmd: ${cmd}"

    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd} | grep " ${server_group_name}$" > /dev/null 2>&1
    return $?
}

port_exists() {
    debug "port_exists():"
    if [ $# -ne 3 ]; then return 1; fi
    local openstack_rc=${1}
    local port_name=${2}
    local project_id=${3}

    local cmd="openstack --os-project-id ${project_id} port show -c name -f value ${port_name}"
    debug "    cmd: ${cmd}"

    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd} 2>/dev/null | debug
    return $?
}

create_server_group() {
    debug "create_server_group():"
    if [ $# -ne 4 ]; then return 1; fi
    local openstack_rc=${1}
    local server_group_name=${2}
    local affinity_rule=${3}
    local project_id=${4}

    local cmd="openstack server group create --policy ${affinity_rule} ${server_group_name}"
    debug "    cmd: ${cmd}"
    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd} 2>/dev/null | debug
    return $?
}


create_port() {
    debug "create_port():"
    if [ $# -ne 6 ]; then return 1; fi
    local openstack_rc=${1}
    local port_net_id=${2}
    local port_fixed_ip=${3}
    local port_mac=${4}
    local project_id=${5}
    local port_name=${6}

    local cmd="openstack port create --network ${port_net_id} --mac-address ${port_mac} --fixed-ip ip-address=${port_fixed_ip} --project ${project_id} ${port_name}"
    debug "    cmd: ${cmd}"
    stdout "${cmd}"
    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd}
    return $?
}

set_instance_property() {
    debug "set_instance_property():"
    if [ $# -ne 3 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_uuid=${2}
    local property_value=${3}
 
    local cmd="openstack server set --property ${property_value} ${instance_uuid}"
    debug "    cmd: ${cmd}"
    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd}
    return $?
}

get_server_group_id() {
    debug "get_server_group_id():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local server_group_name=${2}
 
    local cmd="openstack server group list -c ID -c Name -f value"
    debug "    cmd: ${cmd}"
    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd} | grep " ${server_group_name}$" | cut -d ' ' -f1
    return $?
}

get_server_group_affinity() {
    debug "get_server_group_affinity():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local server_group_id=${2}
 
    local cmd="openstack server group show -c policies -f value ${server_group_id}"
    debug "    cmd: ${cmd}"
    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd}
    return $?
}


get_instance_id() {
    debug "get_instance_id_all_projects():"
    if [ $# -ne 3 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}
    local project_id=${3}
 
    local cmd="openstack --os-project-id ${project_id} server show -c id -f value ${instance_name}"
    debug "    cmd: ${cmd}"
    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd}
    return $?
}

get_neutron_port_id() {
    debug "get_neutron_port_id():"
    if [ $# -ne 3 ]; then return 1; fi
    local openstack_rc=${1}
    local fixed_ip=${2}
    local project_id=${3}
 
    local cmd="openstack --os-project-id ${project_id} port list --fixed-ip ip-address=${fixed_ip} -c ID -c 'MAC Address' -f value"
    debug "    cmd: ${cmd}"
    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd}
    return $?
}

get_project_id_byname() {
    debug "get_project_id_byname():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local project_name=${2}
 
    local cmd="openstack project list -c Name -c ID -f value"
    debug "    cmd: ${cmd}"
    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd} | grep ${project_name}$ | cut -d ' ' -f1
    return $?
}

validate_ephemeral_image_path_on_hv() {
    debug "validate_ephemeral_image_path_on_hv():"
    if [ $# -ne 1 ]; then return 1; fi
    local hv_image_path=${1}
    local hv_ip_address=$(echo "${hv_image_path}" | cut -d ':' -f1)
    local hv_image_path=$(echo "${hv_image_path}" | cut -d ':' -f2)
    local ssh_flags="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

    ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${hv_ip_address} \
        "if [ -r ${hv_image_path} ]; then exit 0; else exit 1; fi" |& debug
}

convert_image_raw_qcow2_on_hv() {
    debug "convert_image_raw_qcow2_on_hv():"
    if [ $# -ne 3 ]; then return 1; fi
    local hv_ip_address=${1}
    local src_image_path=${2}
    local dst_image_path=${3}
    local ssh_flags="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    debug "    qemu-img convert -p -O qcow2 ${src_image_path} ${dst_image_path}"

    ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${hv_ip_address} \
        "qemu-img convert -O qcow2 ${src_image_path} ${dst_image_path}" |& debug
    return $?
}

get_remote_filesize() {
    debug "get_remote_filesize():"
    if [ $# -ne 2 ]; then return 1; fi
    local ip_address=${1}
    local file_path=${2}
    local ssh_flags="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${ip_address} \
        "ls -s ${file_path} | cut -d ' ' -f1"
    return $?
}

get_ephemeral_image_path_on_hv() {
    debug "get_ephemeral_image_path_on_hv():"
    if [ $# -ne 2 ]; then return 1; fi
    local hv_name=${1}
    local instance_uuid=${2}
    local hv_ip_address=""
    local hv_image_path=""
    local hv_instance_basedir=""

    if [ -r ${hv_map} ]; then
        grep "^${hv_name}|" ${hv_map} > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            hv_instance_basedir=$(grep "^${hv_name}|" ${hv_map} | cut -d '|' -f3)
            hv_ip_address=$(grep "^${hv_name}|" ${hv_map} | cut -d '|' -f2)
            hv_image_path="${hv_ip_address}:${hv_instance_basedir}/${instance_uuid}"
            debug "    ${hv_image_path}"
            echo "${hv_image_path}"
            return 0
        fi
    fi
    return 1
}


set_image_backingstore_metadata() {
    debug "set_image_backingstore_metadata():"
    if [ $# -ne 3 ]; then return 1; fi
    local remote_host=${1}
    local baseimage_path=${2}
    local backingimage_path=${3}
    local instance_basedir=$(echo "${baseimage_path}" | sed 's/disk$/\*/')
    local ssh_flags="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

    debug "set_image_backingstore_metadata().baseimage_path=${baseimage_path}"
    debug "set_image_backingstore_metadata().backingimage_path=${backingimage_path}"
    debug "set_image_backingstore_metadata().instance_basedir=${instance_basedir}"
    debug "running on ${remote_host} via ssh: sudo qemu-img rebase -f qcow2 -u -b ${backingimage_path} ${baseimage_path}"

    ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${remote_host} \
        "sudo qemu-img rebase -f qcow2 -u -b ${backingimage_path} ${baseimage_path}" |& debug
    ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${remote_host} \
        "sudo chown -R ${instance_migration_user}:${instance_migration_group} ${instance_basedir}" |& debug
    ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${remote_host} \
        "ls -Ral ${instance_basedir}" |& debug

    return $?
}


get_remote_qemu_image_list() {
    debug "get_remote_qemu_image_list():"
    # Requires host, image_path
    # Returns list of images from disk.info
    if [ $# -ne 1 ]; then return 1; fi
    local hv_image_path=${1}
    local hv_ip_address=$(echo "${hv_image_path}" | cut -d ':' -f1)
    local hv_image_path=$(echo "${hv_image_path}" | cut -d ':' -f2)
    local ssh_flags="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

    if ! local image_list_tmp=$(ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${hv_ip_address} \
                                "if ! cat ${hv_image_path}/disk.info; then exit 1; fi"); then
        debug "Failed to obtain list of images from ${hv_ip_address}:${hv_image_path}/disk.info"
        return 1
    fi
    if ! local image_list=$(echo ${image_list_tmp} | jq -r 'keys[]');then
        debug "Failed to parse image_list: ${image_list}"
        return 1
    fi
    debug "    image_list: ${image_list}"
    echo "${image_list}"
    return $?
}


get_remote_qemu_image_info() {
    debug "get_remote_qemu_image_info():"
    # Requires host, image_path
    # Returns image, disk size, virtual size, file format, backing image
    # call recurisively to get backing image info
    if [ $# -lt 2 ]; then return 1; fi
    local remote_host=${1}
    local image_path=${2}
    local ssh_flags="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

    ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${remote_host} \
        "qemu-img info ${image_path} --output=json --backing-chain"
    return $?
}


create_image_from_ephemeral_instance() {
    debug "create_image_from_ephemeral_instance():"
    if [ $# -lt 3 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}
    local snapshot_name=${3}
 
    local cmd="openstack server image create ${instance_name} --name ${snapshot_name}"
    debug "    cmd: ${cmd}"
    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd} | debug
    return $?
}


attach_volume() {
    debug "attach_volume():"
    if [ $# -lt 3 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}
    local volume_name=${3}

    if [ $# -eq 4 ]; then
        local cmd="openstack server add volume --device ${4} ${instance_name} ${volume_name}"
    debug "    cmd: ${cmd}"
    else
        local cmd="openstack server add volume ${instance_name} ${volume_name}"
    debug "    cmd: ${cmd}"
    fi

    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd} > /dev/null 2>&1
    return $?
}


attach_security_group() {
    debug "attach_security_group():"
    if [ $# -ne 3 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}
    local security_group=${3}

    source ${openstack_rc} > /dev/null 2>&1
    local cmd="openstack server add security group ${instance_name} ${security_group}"
    debug "    cmd: ${cmd}"
    eval ${cmd} | debug
    return $?
}

create_instance_from_volume() {
    debug "create_instance_from_volume($#):"
    if [ $# -lt 14 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}
    local instance_volume=${3}
    local instance_flavor=${4}
    local instance_sec_group=${5}
    local instance_netid=${6}
    local instance_fixed_ip=${7}
    local instance_az=${8}
    local instance_project_id=${9}
    local config_drive=${10}
    local ssh_keypair=${11}
    local server_group_uuid=${12}
    local hv_placement=${13}
    local instance_properties=${14}

    if [ $# -eq 15 ]; then
        local port_id=${15}
        net_flags="--nic port-id='${port_id}'"
    else
        net_flags="--network ${instance_netid}"
    fi

    if [ "${hv_placement}" != "use-scheduler" ]; then
        instance_az="${instance_az}::${hv_placement}"
    fi

    if [ "${server_group_uuid}" == "undefined" ]; then
        server_group_flags=""
    else
        server_group_flags="--hint group=${server_group_uuid}"
    fi

    if [ "${config_drive}" == "True" ]; then
        config_drive_flags="--config-drive True"
    else
        config_drive_flags=""
    fi

    source ${openstack_rc} > /dev/null 2>&1
    if [ "${ssh_keypair}" == "null" ]; then
	local cmd="openstack server create --volume ${instance_volume} --flavor ${instance_flavor} ${net_flags} --security-group ${instance_sec_group} --availability-zone ${instance_az} ${config_drive_flags} ${server_group_flags} ${instance_properties} ${instance_name}"
    else
	local cmd="openstack server create --volume ${instance_volume} --flavor ${instance_flavor} ${net_flags} --key-name ${ssh_keypair} --security-group ${instance_sec_group} --availability-zone ${instance_az} ${config_drive_flags} ${server_group_flags} ${instance_properties} ${instance_name}"
    fi
    debug "    cmd: ${cmd}"
    eval ${cmd} | debug
    return $?
}

create_instance_from_image() {
    debug "create_instance_from_image($#):"
    if [ $# -lt 14 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}
    local instance_image=${3}
    local instance_flavor=${4}
    local instance_sec_group=${5}
    local instance_netid=${6}
    local instance_fixed_ip=${7}
    local instance_az=${8}
    local instance_project_id=${9}
    local config_drive=${10}
    local ssh_keypair=${11}
    local server_group_uuid=${12}
    local hv_placement=${13}
    local instance_properties=${14}

    if [ $# -eq 15 ]; then
        local port_id=${15}
        net_flags="--nic port-id='${port_id}'"
    else
        net_flags="--network ${instance_netid}"
    fi

    if [ "${hv_placement}" != "use-scheduler" ]; then
        instance_az="${instance_az}::${hv_placement}"
    fi

    if [ "${server_group_uuid}" == "undefined" ]; then
        server_group_flags=""
    else
        server_group_flags="--hint group=${server_group_uuid}"
    fi

    if [ "${config_drive}" == "True" ]; then
        config_drive_flags="--config-drive True"
    else
        config_drive_flags=""
    fi

    source ${openstack_rc} > /dev/null 2>&1
    if [ "${ssh_keypair}" == "null" ]; then
    	local cmd="openstack --os-project-id ${instance_project_id} server create --flavor ${instance_flavor} --image ${instance_image} ${net_flags} --security-group ${instance_sec_group} --availability-zone ${instance_az} ${config_drive_flags} ${server_group_flags} ${instance_properties} ${instance_name}"
    else
    	local cmd="openstack --os-project-id ${instance_project_id} server create --flavor ${instance_flavor} --image ${instance_image} ${net_flags} --key-name ${ssh_keypair} --security-group ${instance_sec_group} --availability-zone ${instance_az} ${config_drive_flags} ${server_group_flags} ${instance_properties} ${instance_name}"
    fi
    debug "cmd: ${cmd}" 
    eval ${cmd} | debug
    return $?
}

instance_exists() {
    debug "instance_exists():"
    if [ $# -ne 3 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}
    local project_id=${3}
    local cmd="openstack --os-project-id ${project_id} server show -f json ${instance_name}"
    debug "    cmd: ${cmd}"

    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd} 2>/dev/null | debug
    return $?
}

get_projectName() {
    debug "get_projectName():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local project_id=${2}
    local cmd="openstack project show -c name -f value ${project_id}"
    debug "    cmd: ${cmd}"

    source ${openstack_rc} > /dev/null 2>&1
    output=$(${cmd}); (echo "${output}" | debug > /dev/null 2>&1)
    echo "${output}"
    return $?
}

get_server_list_all() {
    debug "get_server_list_all():"
    if [ $# -ne 1 ]; then return 1; fi
    local openstack_rc=${1}
    local cmd="openstack server list --all -f json"
    debug "    cmd: ${cmd}"

    source ${openstack_rc} > /dev/null 2>&1
    output=$(${cmd})
    echo "${output}"
    return $?
}

get_instance_uuid_name() {
    debug "get_instance_uuid_name():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local user_input=${2}

    if local os_server_list=$(get_server_list_all ${osrc_source}); then
	#debug "    os_server_list: ${os_server_list}"
	local instance_uuid_name=$(echo ${os_server_list} | jq -r '.[] | select((.ID == '\"$user_input\"') or .Name == '\"$user_input\"') | .ID, .Name')
	debug "    instance_uuid_name: ${instance_uuid_name}"
	if [[ -z "${instance_uuid_name[0]}" && -z "${instance_uuid_name[1]}" ]]; then
	    assert "Failed resolving UUID and instance name"; fi
	echo "${instance_uuid_name[@]}"
	return $?
    else
	assert "Failed to get source server list"; fi
}

get_volume() {
    debug "get_volume():"
    if [ $# -ne 3 ]; then return 1; fi
    local openstack_rc=${1}
    local volume_uuid=${2}
    local volume_db=${3}

    source ${openstack_rc} > /dev/null 2>&1
    openstack volume show -f json "${volume_uuid}" > ${volume_db}
    return $?
}

get_instance() {
    debug "get_instance():"
    if [ $# -ne 3 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}
    local instance_db=${3}

    source ${openstack_rc} > /dev/null 2>&1
    openstack server show -f json "${instance_name}" > ${instance_db}
    return $?
}

get_instanceName() {
    debug "get_instanceName():"
    if [ $# -ne 1 ]; then return 1; fi
    local instance_db=${1}

    cat ${instance_db} | jq '.name' | sed -e "s/\"//g"
}

get_config_drive() {
    if [ $# -ne 1 ]; then return 1; fi
    local instance_db=${1}

    cat ${instance_db} | jq '.config_drive' | sed -e "s/\"//g"
}

get_metadata() {
    if [ $# -ne 1 ]; then return 1; fi
    local instance_db=${1}

    cat ${instance_db} | jq '.properties' | sed -e "s/\"//g"
}

get_instanceId() {
    debug "get_instanceId():"
    if [ $# -ne 1 ]; then return 1; fi
    local instance_db=${1}

    cat ${instance_db} | jq '.id' | sed -e "s/\"//g"
}

get_projectId() {
    debug "get_projectId():"
    if [ $# -ne 1 ]; then return 1; fi
    local instance_db=${1}

    cat ${instance_db} | jq '.project_id' | sed -e "s/\"//g"
}

get_hypervisor() {
    debug "get_hypervisor():"
    if [ $# -ne 1 ]; then return 1; fi
    local instance_db=${1}

    cat ${instance_db} | jq '."OS-EXT-SRV-ATTR:hypervisor_hostname"' | sed -e "s/\"//g"
}

get_ssh_keyname() {
    debug "get_ssh_keyname():"
    if [ $# -ne 1 ]; then return 1; fi
    local instance_db=${1}

    cat ${instance_db} | jq '.key_name' | sed -e "s/\"//g"
}

get_availability_zone() {
    debug "get_availability_zone():"
    if [ $# -ne 1 ]; then return 1; fi
    local instance_db=${1}

    cat ${instance_db} | jq '."OS-EXT-AZ:availability_zone"' | sed -e "s/\"//g"
}

get_image() {
    debug "get_image():"
    if [ $# -ne 1 ]; then return 1; fi
    local instance_db=${1}

    cat ${instance_db} | jq '.image' | sed -e "s/\"//g"
}

get_image_size() {
    debug "get_image_size():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local image_uuid=${2}

    source ${openstack_rc} > /dev/null 2>&1
    openstack image show "${image_uuid}" -c size -f value
    return $?
}

get_image_format() {
    debug "get_image_format():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local image_uuid=${2}

    source ${openstack_rc} > /dev/null 2>&1
    openstack image show "${image_uuid}" -c disk_format -f value
    return $?
}

get_volume_id() {
    debug "get_volume_id():"
    if [ $# -lt 2 ]; then return 1; fi
    local openstack_rc=${1}
    local volume_name=${2}
    local project_name=""
    if [ $# -eq 3 ]; then project_name=${3}; fi

    if [ -n "${project_name}" ]; then
        cmd="openstack --os-project-name ${project_name} volume show '${volume_name}' -c id -f value"
    else
        cmd="openstack volume show '${volume_name}' -c id -f value"
    fi

    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd} 2>/dev/null
    return $?
}

get_image_id() {
    debug "get_image_id():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local image_name=${2}

    source ${openstack_rc} > /dev/null 2>&1
    openstack image show "${image_name}" -c id -f value
    return $?
}

get_image_min_disk() {
    debug "get_image_min_disk():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local image_uuid=${2}

    source ${openstack_rc} > /dev/null 2>&1
    openstack image show "${image_uuid}" -c properties -f value | sed -e "s/'/\"/g" | jq '.pf9_virtual_size'
    return $?
}

get_image_checksum() {
    debug "get_image_checksum():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local image_uuid=${2}

    source ${openstack_rc} > /dev/null 2>&1
    openstack image show "${image_uuid}" -c checksum -f value
    return $?
}

get_flavor() {
    debug "get_flavor():"
    if [ $# -ne 1 ]; then return 1; fi
    local instance_db=${1}

    cat ${instance_db} | jq '.flavor' | sed -e "s/\"//g" | cut -d ' ' -f1
}

start_instance() {
    debug "start_instance():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}

    source ${openstack_rc} > /dev/null 2>&1
    openstack server start ${instance_name} 
    return $?
}

stop_instance() {
    debug "stop_instance():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}

    source ${openstack_rc} > /dev/null 2>&1
    openstack server stop ${instance_name} 
    return $?
}

lock_instance() {
    debug "lock_instance():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}

    source ${openstack_rc} > /dev/null 2>&1
    openstack server lock ${instance_name} 
    return $?
}

get_instance_state() {
    debug "get_instance_state():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}

    source ${openstack_rc} > /dev/null 2>&1
    openstack server show -c status -f value ${instance_name}
    return $?
}

get_flavor_id() {
    debug "get_flavor_id():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local network_name=${2}

    source ${openstack_rc} > /dev/null 2>&1
    openstack flavor show -c id ${flavor} | grep " id " | cut -d '|' -f3 | awk -F ' ' '{print $1}'
    return $?
}

ssh_keypair_exists() {
    debug "ssh_keypair_exists():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local keypair_name=${2}

    source ${openstack_rc} > /dev/null 2>&1
    local cmd="openstack keypair show -c id -f value ${keypair_name}"
    debug "    cmd: ${cmd}"
    eval ${cmd} > /dev/null 2>&1
    return $?
}

get_network_id() {
    debug "get_network_id():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local network_name=${2}

    source ${openstack_rc} > /dev/null 2>&1
    openstack network show -c id ${network_name} | grep id | cut -d '|' -f3 | awk -F ' ' '{print $1}'
    return $?
}

get_volume_state() {
    debug "get_volume_state():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local volume_name=${2}

    source ${openstack_rc} > /dev/null 2>&1
    openstack volume show -c status -f value "${volume_name}" 2>/dev/null
    return $?
}

get_image_state() {
    debug "get_image_state():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local image_name=${2}

    source ${openstack_rc} > /dev/null 2>&1
    openstack image show -c status -f value "${image_name}" 2>/dev/null
    return $?
}

get_network() {
    debug "get_network():"
    if [ $# -ne 1 ]; then return 1; fi
    local instance_db=${1}

    cat ${instance_db} | jq '.addresses' | sed -e "s/\"//g" 
}


get_security_group_id() {
    debug "get_security_group_id():"
    if [ $# -ne 3 ]; then return 1; fi
    local openstack_rc=${1}
    local sg_name=${2}
    local project_name=${3}

    source ${openstack_rc} > /dev/null 2>&1
    openstack security group list --project ${project_name} | grep ${sg_name} | cut -d \| -f2 | awk -F ' ' '{print $1}'
    return $?
}

get_security_groups() {
    debug "get_security_groups():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_uuid=${2}

    # initialize tmpfile
    tmpfile=/tmp/secgroup.${instance_uuid}.tmp
    rm -f ${tmpfile}

    source ${openstack_rc} > /dev/null 2>&1
    openstack server show -c security_groups "${instance_uuid}" | grep 'name=' > ${tmpfile} 2>&1
    if [ $? -ne 0 ]; then exit 1; fi
    idx=0
    local line=""
    while read line; do
      group=$(echo "${line}" | cut -d '|' -f3 | cut -d '=' -f2 | awk -F ' ' '{print $1}' | sed -e "s/'//g")
      security_groups[(idx++)]=${group}
    done < ${tmpfile}
    rm -f ${tmpfile} 
}

get_volumes() {
    debug "get_volumes():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_uuid=${2}

    # initialize tmpfile
    tmpfile=/tmp/volumes.${instance_uuid}.tmp
    rm -f ${tmpfile}

    source ${openstack_rc} > /dev/null 2>&1
    openstack server show -c volumes_attached "${instance_uuid}" | grep 'id=' > ${tmpfile}
    if [ $? -ne 0 ]; then return 1; fi
    idx=0
    local line=""
    while read line; do
      volume=$(echo "${line}" | cut -d '|' -f3 | cut -d '=' -f2 | awk -F ' ' '{print $1}' | sed -e "s/'//g")
      volumes[(idx++)]=${volume}
    done < ${tmpfile}
    rm -f ${tmpfile}
}

wait_for_instance_state() {
    debug "wait_for_instance_state():"
    if [ $# -ne 3 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}
    local target_state=${3}
    case ${target_state} in
    ACTIVE|SHUTOFF)
        ;;
    *)
        return 1
        ;;
    esac

    # timeout loop: wait for target instance state
    local current_state=""
    local elapsed_time=0
    local start_time=$(date +%s)
    while [ ${elapsed_time} -lt ${TIMEOUT_INSTANCE_STATE} ]; do
        echo -n "."
        current_state=$(get_instance_state ${openstack_rc} ${instance_name})
        if [ "${current_state}" == "${target_state}" ]; then break; fi
        if [ "${current_state}" == "ERROR" ]; then return 2; fi
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        sleep ${WAIT_FOR_SLEEPTIME}
    done
    echo "$(format_time ${elapsed_time})"
    if [ ${elapsed_time} -ge ${TIMEOUT_INSTANCE_STATE} ]; then return 1; fi

    return 0
}


wait_for_image_state() {
    debug "wait_for_image_state():"
    if [ $# -ne 3 ]; then return 1; fi
    local openstack_rc=${1}
    local image_name=${2}
    local target_state=${3}
    case ${target_state} in
    active)
        ;;
    *)
        return 1
        ;;
    esac

    # timeout loop: wait for target instance state
    local elapsed_time=0
    local start_time=$(date +%s)
    while [ ${elapsed_time} -lt ${TIMEOUT_IMAGE_STATE} ]; do
        echo -n "."
        if [ "$(get_image_state ${openstack_rc} ${image_name})" == "${target_state}" ]; then break; fi
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        sleep ${WAIT_FOR_SLEEPTIME}
    done
    echo "$(format_time ${elapsed_time})"
    if [ ${elapsed_time} -ge ${TIMEOUT_IMAGE_STATE} ]; then return 1; fi

    return 0
}

wait_for_volume_state() {
    debug "wait_for_volume_state():"
    if [ $# -ne 3 ]; then return 1; fi
    local openstack_rc=${1}
    local volume_name=${2}
    local target_state=${3}
    case ${target_state} in
    available)
        ;;
    *)
        return 1
        ;;
    esac

    # timeout loop: wait for target volume state
    local elapsed_time=0
    local start_time=$(date +%s)
    while [ ${elapsed_time} -lt ${TIMEOUT_VOLUME_STATE} ]; do
        echo -n "."
        if [ "$(get_volume_state ${openstack_rc} ${volume_name})" == "${target_state}" ]; then break; fi
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        sleep ${WAIT_FOR_SLEEPTIME}
    done
    echo "$(format_time ${elapsed_time})"
    if [ ${elapsed_time} -ge ${TIMEOUT_VOLUME_STATE} ]; then return 1; fi

    return 0
}


snapshot_exists() {
    debug "snapshot_exists():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local snapshot_name=${2}

    source ${openstack_rc} > /dev/null 2>&1
    local cmd="openstack volume snapshot show ${snapshot_name} -c id -f value"
    debug "    cmd: ${cmd}"
    eval ${cmd} > /dev/null 2>&1
    return $?
}


volume_exists() {
    debug "volume_exists():"
    if [ $# -lt 2 ]; then return 1; fi
    local openstack_rc=${1}
    local snapshot_name=${2}
    local project_name=""
    local cmd=""
    if [ $# -eq 3 ]; then project_name=${3}; fi

    source ${openstack_rc} > /dev/null 2>&1
    if [ -n "${project_name}" ]; then
        cmd="openstack --os-project-name ${project_name} volume show ${snapshot_name} -c id -f value"
    else
        cmd="openstack volume show ${snapshot_name} -c id -f value"
    fi
    debug "    cmd: ${cmd}"
    eval ${cmd} > /dev/null 2>&1
    return $?
}


image_exists() {
    debug "image_exists():"
    if [ $# -ne 2 ]; then return 1; fi
    local openstack_rc=${1}
    local image_name=${2}

    source ${openstack_rc} > /dev/null 2>&1
    local cmd="openstack image show ${image_name} -c id -f value"
    debug "    cmd: ${cmd}"
    eval ${cmd} > /dev/null 2>&1
    return $?
}


volume_attached() {
    debug "volume_attached():"
    if [ $# -ne 3 ]; then return 1; fi
    local openstack_rc=${1}
    local instance_name=${2}
    local volume_uuid=${3}

    source ${openstack_rc} > /dev/null 2>&1
    local cmd="openstack server show ${instance_name} -c volumes_attached -f value"
    debug "    cmd: ${cmd}"
    eval ${cmd} | grep ${volume_uuid} > /dev/null 2>&1
    return $?
}


create_volume_from_image() {
    debug "create_volume_from_image():"
    if [ $# -ne 4 ]; then return; fi
    local openstack_rc=${1}
    local image_name=${2}
    local volume_name=${3}
    local volume_size=${4}

    local cmd="openstack volume create --image ${image_name} --size ${volume_size} ${volume_name}"
    debug "    cmd: ${cmd}"
    source ${openstack_rc} > /dev/null 2>&1
    eval ${cmd} > /dev/null 2>&1 &
    wait_for_pid $! 600
}


create_volume_from_snapshot() {
    debug "create_volume_from_snapshot():"
    if [ $# -ne 4 ]; then return; fi
    local openstack_rc=${1}
    local volume_name=${2}
    local snapshot_name=${3}
    local volume_size=${4}

    source ${openstack_rc} > /dev/null 2>&1
    local cmd="openstack volume create --snapshot ${snapshot_name} --size ${volume_size} ${volume_name}"
    debug "    cmd: ${cmd}"
    eval ${cmd} > /dev/null 2>&1 &
    wait_for_pid $! 300
}

detach_volume() {
    debug "detach_volume():"
    if [ $# -ne 3 ]; then return; fi
    local openstack_rc=${1}
    local instance_name=${2}
    local volume_uuid=${3}

    source ${openstack_rc} > /dev/null 2>&1
    local cmd="openstack server remove volume ${instance_name} ${volume_uuid}"
    debug "    cmd: ${cmd}"
    eval ${cmd} > /dev/null 2>&1
    return $?
}


create_image_from_volume() {
    debug "create_image_from_volume():"
    if [ $# -ne 3 ]; then return; fi
    local openstack_rc=${1}
    local image_name=${2}
    local volume_uuid=${3}

    local cmd="openstack image create --force --volume ${volume_uuid} ${image_name}"
    source ${openstack_rc} > /dev/null 2>&1
    debug "    cmd: ${cmd}"

    # retry loop
    local cnt=0
    while [ ${cnt} -lt ${RETRY_ATTEMPTS} ]; do
        openstack image create --force --volume ${volume_uuid} ${image_name} | debug
        if [ $? -eq 0 ]; then return 0; fi
        sleep ${RETRY_DELAY}
        ((cnt++))
    done
    if [ ${cnt} -ge ${RETRY_ATTEMPTS} ]; then return 1; fi
    return 1
}


create_snapshot() {
    debug "create_snapshot():"
    if [ $# -ne 3 ]; then return; fi
    local openstack_rc=${1}
    local snapshot_name=${2}
    local volume_uuid=${3}

    source ${openstack_rc} > /dev/null 2>&1
    local cmd="openstack volume snapshot create --volume ${volume_uuid} --force ${snapshot_name}"
    debug "    cmd: ${cmd}"
    eval ${cmd} > /dev/null 2>&1 &
    wait_for_pid $! 60
}


image_upload() {
    debug "image_upload():"
    if [ $# -lt 3 ]; then return; fi
    local openstack_rc=${1}
    local volume_name=${2}
    local image_path=${3}
    local image_size_bytes=${4}
    local start_time=$(date +%s)

    if [ $# -eq 5 ]; then
        disk_format=${5}
    else
        disk_format="raw"
    fi

    source ${openstack_rc} > /dev/null 2>&1
    local cmd="openstack image create --container-format bare --disk-format ${disk_format} --file ${image_path} ${volume_name}"
    debug "    cmd: ${cmd}"
    eval ${cmd} > /dev/null 2>&1 &
    wait_for_pid $! 7200

    # calculate transer rate
    local end_time=$(date +%s)
    local elsapsed_time=$((end_time - start_time))
    local transfer_rate=$(bc <<< "${image_size_bytes} / ${elsapsed_time}")
    local transfer_rate_mbs=$(bc <<< "scale=2; (${transfer_rate} * 8) / 1000000" | awk '{printf "%f.2", $0}')
    stdout "    Transfer Rate: ${transfer_rate_mbs} Mbps"
}

image_download() {
    debug "image_download():"
    if [ $# -lt 4 ]; then return; fi
    local openstack_rc=${1}
    local volume_id=${2}
    local image_path=${3}
    local image_size_bytes=${4}
    local start_time=$(date +%s)
    local glance_endpoint=""
    if [ $# -eq 5 ]; then
        glance_endpoint=${5}
    fi

    if [ -n "${glance_endpoint}" ]; then
        debug "INFO: using Curl for download instead of 'openstack image save', endpoint=${glance_endpoint}"
        local token=$(get_token ${openstack_rc})
        if [ $? -ne 0 ]; then return 1; fi
        local cmd="curl -H \"Content-Type: application/json\" -H \"X-Auth-Token: ${token}\" ${glance_endpoint}/v2/images/${volume_id}/file -o ${image_path}"
	debug "    cmd: ${cmd}"
        eval ${cmd} > /dev/null 2>&1 &
        wait_for_pid $! ${TIMEOUT_IMAGE_DOWNLOAD}
    else
        source ${openstack_rc} > /dev/null 2>&1
        local cmd="openstack image save --file ${image_path} ${volume_id}"
	debug "    cmd: ${cmd}"
        debug "image_download().image_size_bytes = ${image_size_bytes}"
        eval ${cmd} > /dev/null 2>&1 &
        wait_for_pid $! ${TIMEOUT_IMAGE_DOWNLOAD}
        if [ $? -ne 0 ]; then debug "image_dowload(): TIMEOUT exceeded (TIMEOUT=${TIMEOUT_IMAGE_DOWNLOAD})"; fi
        if [ ! -r ${image_path} ]; then return 1; fi
        debug "ls -l ${image_path}"
    fi

    # calculate transer rate
    local end_time=$(date +%s)
    local elsapsed_time=$((end_time - start_time))
    local transfer_rate=$(bc <<< "${image_size_bytes} / ${elsapsed_time}")
    local transfer_rate_mbs=$(bc <<< "scale=2; (${transfer_rate} * 8) / 1000000" | awk '{printf "%f.2", $0}')
    stdout "    Transfer Rate: ${transfer_rate_mbs} Mbps"
}

get_volume_size() {
    debug "get_volume_size():"
    if [ $# -ne 2 ]; then return; fi
    local openstack_rc=${1}
    local volume_name=${2}
    local volume_size=""

    source ${openstack_rc} > /dev/null 2>&1
    local cmd="openstack volume show ${volume_name} -c size -f value"
    debug "    cmd: ${cmd}"
    volume_size=$(eval ${cmd})
    if [ $? -eq 0 ]; then
        stdout "${volume_size}"
        return 0
    fi
    return 1
}

get_snapshot_size() {
    debug "get_snapshot_size():"
    if [ $# -ne 2 ]; then return; fi
    local openstack_rc=${1}
    local snapshot_name=${2}
    local volume_size=""

    source ${openstack_rc} > /dev/null 2>&1
    local cmd="openstack volume snapshot show ${snapshot_name} -c size -f value"
    debug "    cmd: ${cmd}"
    volume_size=$(eval ${cmd})
    if [ $? -eq 0 ]; then
        stdout "${volume_size}"
        return 0
    fi
    return 1
}

validate_openstack() {
    debug "validate_openstack():"
    if [ $# -ne 1 ]; then return 1; fi
    local configFile=${1}

    # read configuration file
    stdout "[Reading Configuration File]"
    if [ ! -r ${configFile} ]; then assert "ERROR: cannot open configuration file: ${configFile}"; fi
    eval local osrc_source=$(grep ^source-cloud ${configFile} | cut -d '|' -f2)
    eval local osrc_target=$(grep ^target-cloud ${configFile} | cut -d '|' -f2)

    stdout "[Validating OpenStack]"
    stdout "--> validating OpenStack CLI is installed"
    if !(openstack --version > /dev/null 2>&1); then assert "Error: openstack not installed"; fi

    stdout "--> validating login credentials for source cloud"
    if ! source ${osrc_source} > /dev/null 2>&1; then assert "ERROR: Cannot source ${osrc_source}"; fi
    if !(openstack token issue -c id -f value > /dev/null 2>&1); then assert "Error: failed to login to source cloud"; fi

    stdout "--> validating login credentials for target cloud"
    if ! source "${osrc_target}" > /dev/null 2>&1; then assert "ERROR: Cannot source ${osrc_target}"; fi
    if !(openstack token issue -c id -f value > /dev/null 2>&1); then assert "Error: failed to login to target cloud"; fi
}



migrate_volume() {
    debug "migrate_volume():"
    if [ $# -ne 5 ]; then return; fi
    local instance_name=${1}
    local volume_name=${2}
    local volume_uuid=${3}
    local source_rc=${4}
    local target_rc=${5}

    stdout "\n[Cinder Volume Migration: ${volume_name}, uuid = ${volume_uuid}]"
    stdout "--> Detaching volume from instance"
    volume_attached ${source_rc} ${instance_name} ${volume_uuid}
    if [ $? -eq 0 ]; then
        detach_volume ${source_rc} ${instance_name} ${volume_uuid}
        if [ $? -ne 0 ]; then return 1; fi
    fi

    # get size of volume being migrated
    source_volume_size=$(get_volume_size ${source_rc} ${volume_uuid})
    stdout "--> Source volume size = ${source_volume_size} GB"

    snapshot_name="${volume_name}_snapshot"
    stdout "--> Creating snapshot of ${volume_name}, snapshot name = ${snapshot_name}"
    if ! snapshot_exists ${source_rc} ${snapshot_name}; then
        create_snapshot ${source_rc} ${snapshot_name} ${volume_uuid} 
        if [ $? -ne 0 ]; then return 1; fi
    fi

    # re-attach volume
    stdout "--> Re-attaching volume to instance"
    volume_attached ${source_rc} ${instance_name} ${volume_uuid}
    if [ $? -ne 0 ]; then
        attach_volume ${source_rc} ${instance_name} ${volume_uuid}
        if [ $? -ne 0 ]; then return 1; fi
    fi

    stdout "--> Getting size of snapshot"
    snapshot_size=$(get_snapshot_size ${source_rc} ${snapshot_name})
    if [ $? -ne 0 ]; then return 1; fi
    stdout "--> Snapshot size = ${snapshot_size} GB"

    migration_volume_name="${volume_name}_migration_volume"
    stdout "--> Creating volume (from snapshot): volume name = ${migration_volume_name}"
    if ! volume_exists ${source_rc} ${migration_volume_name}; then
        create_volume_from_snapshot ${source_rc} ${migration_volume_name} ${snapshot_name} ${source_volume_size}
        if [ $? -ne 0 ]; then return 1; fi
    fi

    if ! volume_exists ${source_rc} ${migration_volume_name}; then
        stdout "ERROR: Failed to validate volume: ${migration_volume_name} not found"
        return 1
    fi

    vol_snap_id=$(get_volume_id ${source_rc} ${migration_volume_name})
    migration_image="${volume_name}"
    migration_image_local_path=/tmp/${migration_image}
    if [ -r ${migration_image_local_path} ]; then
        stdout "INFO: removing cached local file: ${migration_image_local_path}"
        rm -f ${migration_image_local_path}
        if [ $? -ne 0 ]; then
            stdout "ERROR: failed to remove cached local file"
            return 1
        fi
    fi
    stdout "--> Creating image from volume: ${migration_image}, source volume uuid = ${vol_snap_id}"
    if ! image_exists ${source_rc} ${migration_image}; then
        create_image_from_volume ${source_rc} ${migration_image} ${vol_snap_id}
    fi
 
    stdout -n "--> Waiting for image to become active"
    wait_for_image_state ${source_rc} ${migration_image} "active"
    if [ $? -ne 0 ]; then return 1; fi

    migration_image_uuid=$(get_image_id ${source_rc} ${migration_image})
    stdout -n "--> Downloading image: ${migration_image}"
    if [ -r ${migration_image_local_path} ]; then
        stdout " already downloaded"
    else
        if [ -n "${glance_endpoint}" ]; then
            image_download ${source_rc} ${migration_image_uuid} ${migration_image_local_path} $(convert_gb_to_bytes ${source_volume_size}) ${glance_endpoint}
            if [ $? -ne 0 ]; then return 1; fi
        else
            image_download ${source_rc} ${migration_image_uuid} ${migration_image_local_path} $(convert_gb_to_bytes ${source_volume_size})
            if [ $? -ne 0 ]; then return 1; fi
        fi
    fi
    if [ ! -r ${migration_image_local_path} ]; then return 1; fi

    stdout "--> Uploading image to target cloud:"
    if image_exists ${target_rc} ${migration_image}; then
        stdout " already uploaded"
    else
        image_upload ${target_rc} ${migration_image} ${migration_image_local_path} $(convert_gb_to_bytes ${source_volume_size})
        if [ $? -ne 0 ]; then return 1; fi
    fi

    stdout "--> Creating volume from image (on target cloud): volume name = ${volume_name}, image name = ${migration_image}"
    if ! volume_exists ${target_rc} ${volume_name}; then
        create_volume_from_image ${target_rc} ${migration_image} ${volume_name} ${source_volume_size}
        if [ $? -ne 0 ]; then return 1; fi
    fi

    stdout -n "--> Waiting for volume to become active (timeout = ${TIMEOUT_VOLUME_STATE} seconds)"
    wait_for_volume_state ${target_rc} ${volume_name} "available"
    if [ $? -ne 0 ]; then return 1; fi

    return 0
}

