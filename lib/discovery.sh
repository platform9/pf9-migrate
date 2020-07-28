################################################################################
# Discovery Function
################################################################################

# Note: this script references global variables defined in pf9-discover

discover() {
    if [ $# -ne 1 ]; then return 1; fi
    local discovery_instanceName=$1
    local discovery_start=$(date +%s)
    local xfer_downloads=( )
    local xfer_uploads=( )
    local xfer_downloads_idx=0
    local xfer_uploads_idx=0
    local instance_type=""
    local image=""
    local image_id=""
    local image_name=""
    local target_image_id="-"
    local warn_network=0
    local warn_flavor=0
    local warn_project=0
    local warn_image=0
    local warn_sg=0
    local warn_ssh=0

    # read configuration file
    if [ ! -r ${pkg_configfile} ]; then assert "ERROR: cannot open configuration file: ${pkg_configfile}"; fi
    eval local osrc_source=$(grep ^source-cloud ${pkg_configfile} | cut -d '|' -f2)
    eval local osrc_target=$(grep ^target-cloud ${pkg_configfile} | cut -d '|' -f2)
    local backend_target=$(grep ^target-backend ${pkg_configfile} | cut -d '|' -f2)
    local pure_ipaddr=$(grep ^pure-ipaddr ${pkg_configfile} | cut -d '|' -f2)
    local pure_username=$(grep ^pure-username ${pkg_configfile} | cut -d '|' -f2)
    local pure_password=$(grep ^pure-password ${pkg_configfile} | cut -d '|' -f2 | base64 -d)

    stdout "SOURCE-CLOUD: Discovering instance: Name = ${discovery_instanceName}"

    # validate openstack RC files
    if [ ! -r ${osrc_source} ]; then assert "ERROR: missing RC file for source-cloud: ${osrc_source}"; fi
    if [ ! -r ${osrc_target} ]; then assert "ERROR: missing RC file for target-cloud: ${osrc_target}"; fi

    #  If user input not UUID call get_instance_uuid_name set $discovery_instanceName to UUID
    if [[ ! ${discovery_instanceName} =~ ^[0-9a-f]{8}\-[0-9a-f]{4}\-[0-9a-f]{4}\-[0-9a-f]{4}\-[0-9a-f]{12} ]]; then
        instance_uuid_name=($(get_instance_uuid_name ${osrc_source} ${discovery_instanceName}))
        # set UUID for $discovery_instanceName
        discovery_instanceName=${instance_uuid_name[0]}
    fi

    # manage instance discovery cache
    local instance_db=${pkg_basedir}/db/${discovery_instanceName}.json
    ensure_parent_dir ${instance_db}
    if [ -r ${instance_db} ]; then rm -f ${instance_db}; fi

    # get instance metadata (json)
    get_instance ${osrc_source} ${discovery_instanceName} ${instance_db}
    if [ $? -ne 0 ]; then assert "failed to get instance metadata"; fi

    # discover instance name
    local instance_name=$(get_instanceName ${instance_db})
    if [ -z "${instance_name}" ]; then assert "Instance not found in source cloud"; fi
    stdout "--> instance_name = ${instance_name}"

    # discover uuid
    local instance_uuid=$(get_instanceId ${instance_db})
    if [ -z "${instance_uuid}" ]; then assert "Instance not found in source cloud"; fi
    stdout "--> instance_uuid = ${instance_uuid}"

    # discover project
    local project_id=$(get_projectId ${instance_db})
    local project_name=$(get_projectName ${osrc_source} ${project_id})
    stdout "--> project_name/project_id = ${project_name}/${project_id}"
    
    # discover network
    if [ -z "${user_network_id}" ]; then
        network_info=$(get_network ${instance_db})
        network_name=$(echo ${network_info} | cut -d= -f1)
        fixed_ip=$(echo ${network_info} | cut -d= -f2 | sed -e 's/,//g')
        network_uuid=$(get_network_id ${osrc_source} ${network_name})

        # get neutron port metadata
        port_metadata=$(get_neutron_port_id ${osrc_source} ${fixed_ip} ${project_id})
        if [ $? -ne 0 ]; then assert "failed to get port uuid"; fi

        # parse port uuid
        port_uuid=$(echo "${port_metadata}" | cut -d ' ' -f1)
        if [ -z "${port_uuid}" ]; then assert "ERROR: failed to parse port uuid"; fi

        # parse mac address
        port_mac=$(echo "${port_metadata}" | cut -d ' ' -f2)
        if [ -z "${port_mac}" ]; then assert "ERROR: failed to parse mac address"; fi
    else
        fixed_ip=""
    fi
    stdout "--> network_name/network_uuid = ${network_name}/${network_uuid}"
    stdout "--> fixed_ip/port_mac = ${fixed_ip}/${port_mac}"

    # discover hypervisor
    local hypervisor=$(get_hypervisor ${instance_db})
    stdout "--> hypervisor = ${hypervisor}"

    # discover image
    image=$(get_image ${instance_db})
    if [ -n "${image}" ]; then
        instance_type="ephemeral"
        image_id=$(echo ${image} | awk -F '(' '{print $NF}' | awk -F ')' '{print $1}')
        nf=$(echo "${image}" | awk -F ' ' '{print NF-1}')
        image_name=$(echo "${image}" | cut -d ' ' -f1-${nf})
    else
        instance_type="volume-backed"
    fi
    stdout "--> instance_type = ${instance_type}"
    if [ "${instance_type}" == "ephemeral" ]; then
        stdout "--> image_name = ${image_name}"
        stdout "--> image_id = ${image_id}"
    fi
    
    # discover flavor
    local flavor=$(get_flavor ${instance_db})
    stdout "--> flavor = ${flavor}"
    
    # discover availability zone
    local availability_zone=$(get_availability_zone ${instance_db})
    stdout "--> availability_zone = ${availability_zone}"
    
    # discover ssh key
    local ssh_keyname=$(get_ssh_keyname ${instance_db})
    stdout "--> ssh_keyname = ${ssh_keyname}"
    
    # discover instance properties
    local instance_metadata=$(get_metadata ${instance_db})
    if [ $? -ne 0 ]; then assert "ERROR: failed to discover instance properties"; fi
    stdout "--> properties = [${instance_metadata}]"

    # discover config-drive
    local config_drive=$(get_config_drive ${instance_db})
    if [ $? -ne 0 ]; then assert "ERROR: failed to discover configuration drive"; fi
    if [ -z "${config_drive}" ]; then config_drive="False"; fi
    stdout "--> config_drive = [${config_drive}]"

    # implement override : user-defined fixed-ip
    if [ -n "${user_fixed_ip}" ]; then
        fixed_ip=${user_fixed_ip}
    fi
    stdout "--> fixed_ip = ${fixed_ip}"

    #############################################################################
    ## validate resource (by name) on target cloud
    #############################################################################
    stdout "\nTARGET-CLOUD: looking up UUIDs for named resources"

    # validate network exists in target cloud
    if [ -z "${user_network_id}"  ]; then
        target_network_id=$(get_network_id ${osrc_target} ${network_name})
        if [ -z "${target_network_id}" ]; then
            target_network_id="<network-id>"
            stdout "WARNING: network not found in target cloud (${network_name})"
            warn_network=1
        fi
    else
        target_network_id=${user_network_id}
    fi
    stdout "--> target_network_id = ${target_network_id}"

    # validate flavor exists in target cloud
    if [ ${flag_skip_validate_flavor} -eq 0 ]; then
        flavor_id=$(get_flavor_id ${osrc_target} ${flavor})
        if [ -z "${flavor_id}" ]; then
            flavor_id="<flavor-id>"
            stdout "WARNING: flavor not found in target cloud: ${flavor}"
            warn_flavor=1
        fi
    fi
    stdout "--> flavor_id = ${flavor_id}"

    # validate ssh key exists in target cloud
    if [ -z "${ssh_keyname}" ]; then
        target_ssh_key=${ssh_default_key}
    else
        ssh_keypair_exists ${osrc_target} ${ssh_keyname}
        if [ $? -eq 0 ]; then
            target_ssh_key=${ssh_keyname}
        else
            target_ssh_key="<target-ssh-key>"
            stdout "WARNING: SSH keypair not found in target cloud: ${ssh_keyname}"
            warn_ssh=1
        fi
    fi
    stdout "--> target_ssh_key = ${target_ssh_key}"

    # validate project
    target_project_id=$(get_project_id_byname ${osrc_target} ${project_name})
    if [ -z "${target_project_id}" ]; then
        target_project_id="<target-project-id>"
        stdout "WARNING: project not found in target cloud: ${target_project_id}"
        warn_project=1
    fi
    stdout "--> target_project_id = ${target_project_id}"

    # validate image exists on target cloud
    if [ "${instance_type}" == "ephemeral" ]; then
        target_image_id=$(get_image_id ${osrc_target} "${image_name}")
        if [ -z "${target_image_id}" ]; then
            target_image_id="<target-image-id>"
            stdout "WARNING: image not found in target cloud: ${image_name}"
            warn_image=1
        fi
        stdout "--> target_image_id = ${target_image_id}"
    fi

    # discover security group(s)
    declare -a security_groups
    get_security_groups ${osrc_source} ${instance_uuid}

    # validate security group(s)
    cnt=0
    for colval in "${security_groups[@]}"; do
        target_sg_id=$(get_security_group_id ${osrc_target} ${colval} ${project_name})
        if [ -z "${target_sg_id}" ]; then
            stdout "WARNING: security group not found in target cloud: ${colval}"
            warn_sg=1
        fi
        if [ ${cnt} -eq 0 ]; then
            target_sg_id="<target-sg-id>"
        fi
        ((cnt++))
    done

    # print instance header
    echo && print_instance_header "Instance Name" "Instance Type" "Image" "Network/Fixed IP" "Security Groups"

    # print security group(s)
    cnt=0
    for colval in "${security_groups[@]}"; do
        if [ ${cnt} -eq 0 ]; then
            print_instance_row "${instance_name}" "${instance_type}" "${image_name}" "${network_name}/${fixed_ip}" "${colval}"
        else
            print_instance_row "" "" "" "" "${colval}"
        fi
        ((cnt++))
    done
    
    # print volume header
    echo && print_volume_header "Volume ID" "Device Name" "Bootable" "Volume Type" "Size-GB" "Migration Time (Sec)"

    # initialize volume metadata
    declare -a extravol_metadata

    # discover volumes
    TIMEOUT=60
    extra_idx=0
    num_volumes=0
    bootvol_uuid=""
    bootvol_name=""
    declare -a volumes
    get_volumes ${osrc_source} ${instance_uuid}

    source ${osrc_source} > /dev/null 2>&1
    for colval in "${volumes[@]}"; do
        # get attachments
        local wait_t0=`date +%s`
        local wait_elapsedTime=0
        local volume_db=${pkg_basedir}/db/${colval}.json
        while [ ${wait_elapsedTime} -lt ${TIMEOUT} ]; do
            openstack volume show -f json "${colval}" > ${volume_db} 2>&1
            if [ $? -eq 0 ]; then break; fi
        
            # update elapsed time
            current_t=`date +%s`; wait_elapsedTime=$((current_t - wait_t0))
            sleep 2
        done
        if [ ${wait_elapsedTime} -ge ${TIMEOUT} ]; then assert "Error: discovery failed for attachments (TIMEOUT EXCEEDED)"; fi

        vol_device=$(cat ${volume_db} | jq '.attachments[0].device' | sed -e "s/\"//g")
        if [ -z "${vol_device}" ]; then
            stdout "WARNING: failed to discovery vol_device for volume ${colval}"
            continue
        fi

        vol_size_gb=$(cat ${volume_db} | jq '.size' | sed -e "s/\"//g")
        if [ -z "${vol_size_gb}" ]; then
            stdout "WARNING: failed to discovery vol_size_gb for volume ${colval}"
            continue
        fi

        vol_cinder_host=$(cat ${volume_db} | jq '.attachments[0].host_name' | sed -e "s/\"//g")
        if [ -z "${vol_cinder_host}" ]; then
            stdout "WARNING: failed to discovery vol_cinder_host for volume ${colval}"
            continue
        fi

        vol_cinder_backend=$(cat ${volume_db} | jq '."os-vol-host-attr:host"' | sed -e "s/\"//g")
        if [ -z "${vol_cinder_backend}" ]; then
            stdout "WARNING: failed to discovery vol_cinder_backend for volume ${colval}"
            continue
        fi

        vol_type=$(cat ${volume_db} | jq '.type' | sed -e "s/\"//g")
        if [ -z "${vol_type}" ]; then
            stdout "WARNING: failed to discovery vol_type for volume ${colval}"
            continue
        fi

        is_bootable=$(cat ${volume_db} | jq '.bootable' | sed -e "s/\"//g")
        if [ -z "${is_bootable}" ]; then
            stdout "WARNING: failed to discovery is_bootable for volume ${colval}"
            continue
        fi

        vol_size_bytes=$(bc <<< "${vol_size_gb} * (1024^3)")
        xfer_rate_down=$(bc <<< "${xfer_download_speed} * (1024^2)")
        xfer_rate_up=$(bc <<< "${xfer_upload_speed} * (1024^2)")
        xfer_time_down=$(bc <<< "scale=2; ${vol_size_bytes} / ${xfer_rate_down}")
        xfer_time_up=$(bc <<< "scale=2; ${vol_size_bytes} / ${xfer_rate_up}")
        vol_migration_time=$(bc <<< "scale=2; ${xfer_time_down} + ${xfer_time_up}")

        if [ "${is_bootable}" == "true" ]; then
            bootvol_uuid="${colval}"
            bootvol_device_short=$(echo ${vol_device} | cut -d '/' -f3)
            bootvol_name="${discovery_instanceName}_${bootvol_device_short}"
            bootvol_type="${vol_type}"
        fi

        extravol_metadata[(extra_idx++)]="${colval}|${vol_device}|${is_bootable}|${vol_type}|${vol_size_gb}"
        print_voume_row "${colval}" "${vol_device}" "${is_bootable}" "${vol_type}" "${vol_size_gb}" "${vol_migration_time}"
        ((num_volumes++))
    done
    if [ ${num_volumes} -eq 0 ]; then stdout "info: no volumes found"; fi
    
    ##
    ## build config file
    ##
    config_file=${pkg_basedir}/configs/${discovery_instanceName}
    stdout "\nBuilding Config File: ${config_file}"
    ensure_parent_dir ${config_file}

    # remove config (if exists)
    if [ -r ${config_file} ]; then rm -f ${config_file}; fi

    # lookup security group UUID
    sg_id=$(get_security_group_id ${osrc_target} ${security_groups[0]} ${project_name})

    # config -> neutron
    echo "[neutron]" >> ${config_file}
    echo "port|${fixed_ip}|${port_mac}|${network_name}|${network_uuid}|${target_network_id}" >> ${config_file}

    # config -> instance
    echo "[instance]" >> ${config_file}
    echo "instance|${instance_name}|${flavor_id}|${instance_type}|${target_network_id}|${sg_id}|${fixed_ip}|${target_image_id}|${target_project_id}|${availability_zone}|${hypervisor}|${instance_uuid}" >> ${config_file}

    # config -> properties
    echo "[properties]" >> ${config_file}
    if [ -n "${instance_metadata}" ]; then
        local prop_array=( )
        echo "${instance_metadata}" | grep ',' > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            prop_array[0]=${instance_metadata}
        else
            local field_idx=1
            local idx=0
            local field=$(echo "${instance_metadata}" | cut -d ',' -f${field_idx})
            while [ -n "${field}" ]; do
                prop_array[(idx++)]=${field}
                ((field_idx++))
                field=$(echo "${instance_metadata}" | cut -d ',' -f${field_idx})
            done
        fi
        for colval in "${prop_array[@]}"; do
            key=$(echo "${colval}" | cut -d '=' -f1 | awk -F ' ' '{print $1}')
            value=$(echo "${colval}" | cut -d '=' -f2)
            echo "property|${key}=${value}" >> ${config_file}
        done
    fi

    # config -> properties
    echo "config-drive|${config_drive}" >> ${config_file}
    echo "key-name|${target_ssh_key}" >> ${config_file}

    # config -> extra volumes
    echo "[additional-volumes]" >> ${config_file}
    for colval in "${extravol_metadata[@]}"; do
        extravol_uuid=$(echo ${colval} | cut -d '|' -f1)
        extravol_device=$(echo ${colval} | cut -d '|' -f2)
        extravol_is_bootable=$(echo ${colval} | cut -d '|' -f3)
        extravol_type=$(echo ${colval} | cut -d '|' -f4)

        extravol_device_short=$(echo ${extravol_device} | cut -d '/' -f3)
        extravol_name="${discovery_instanceName}-${extravol_device_short}"
        echo "instanceVol|${discovery_instanceName}|${extravol_name}|${extravol_type}|${extravol_uuid}|${project_name}|${extravol_device}|${extravol_is_bootable}" >> ${config_file}
    done

    # config -> extra security groups
    echo "[additional-security-groups]" >> ${config_file}
    cnt=0
    for colval in "${security_groups[@]}"; do
        if [ ${cnt} -gt 0 ]; then
            echo "securityGroup|${discovery_instanceName}|${colval}" >> ${config_file}
        fi
        ((cnt++))
    done

    # display complete message (and total time for discovery)
    local discovery_end=$(date +%s)
    local discovery_total=$((discovery_end - discovery_start))
    stdout "DISCOVERY COMPLETE: Execution Time: $(format_time ${discovery_total})"

    # display remediation messages
    if [ ${warn_network} -eq 1 -o ${warn_flavor} -eq 1 -o ${warn_project} -eq 1 -o ${warn_image} -eq 1 -o ${warn_sg} -eq 1 -o ${warn_ssh} -eq 1 ]; then
        stdout "\n======== WARNINGS ========"
    fi

    if [ ${warn_network} -eq 1 ]; then
        stdout "--> network not found on target cloud : edit configuration file and update '<network-id>'"
    fi

    # remediation message: flavor
    if [ ${warn_flavor} -eq 1 ]; then
        stdout "--> flavor not found on target cloud : edit configuration file and update '<flavor-id>'"
    fi

    # remediation message: ssh keypair
    if [ ${warn_ssh} -eq 1 ]; then
        stdout "--> SSH keypair not found on target cloud : edit configuration file and update '<target-ssh-key>'"
    fi

    # remediation message: project
    if [ ${warn_project} -eq 1 ]; then
        stdout "--> project not found on target cloud : edit configuration file and update '<target-project-id>'"
    fi

    # remediation message: image
    if [ ${warn_image} -eq 1 ]; then
        stdout "--> image not found on target cloud : edit configuration file and update '<target-image-id>'"
    fi

    # remediation message: security group
    if [ ${warn_sg} -eq 1 ]; then
        stdout "--> security group not found on target cloud : edit configuration file and update '<target-sg-id>'"
    fi

    if [ ${warn_network} -eq 1 -o ${warn_flavor} -eq 1 -o ${warn_project} -eq 1 -o ${warn_image} -eq 1 -o ${warn_sg} -eq 1 ]; then
        exit 1
    fi
}
