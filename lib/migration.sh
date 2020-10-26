################################################################################
# Migration Functions
################################################################################

# Note: this script references global variables defined in pf9-migrate

migrate() {
    local migration_start=$(date +%s)

    # validate config file for migration
    if [ ! -r ${pkg_configfile} ]; then assert "ERROR: cannot open configuration file: ${pkg_configfile}"; fi

    # read configuration file
    eval local osrc_source=$(grep ^source-cloud ${pkg_configfile} | cut -d '|' -f2)
    eval local osrc_target=$(grep ^target-cloud ${pkg_configfile} | cut -d '|' -f2)
    local backend_target=$(grep ^target-backend ${pkg_configfile} | cut -d '|' -f2)
    local pure_ipaddr=$(grep ^pure-ipaddr ${pkg_configfile} | cut -d '|' -f2)
    local pure_username=$(grep ^pure-username ${pkg_configfile} | cut -d '|' -f2)
    local pure_password=$(grep ^pure-password ${pkg_configfile} | cut -d '|' -f2 | base64 -d)
    local glance_endpoint=$(grep ^source-glance-ep ${pkg_configfile} | cut -d '|' -f2)
    local source_ssh_username=$(grep ^source-ssh-username ${pkg_configfile} | cut -d '|' -f2)
    local source_ssh_privatekey=$(grep ^source-ssh-privatekey ${pkg_configfile} | cut -d '|' -f2)
    local target_ssh_username=$(grep ^target-ssh-username ${pkg_configfile} | cut -d '|' -f2)
    local target_ssh_privatekey=$(grep ^target-ssh-privatekey ${pkg_configfile} | cut -d '|' -f2)
    local rsync_flags=$(grep ^rsync-flags ${pkg_configfile} | cut -d '|' -f2)
    local instance_migration_user=$(grep ^instance-migration-user ${pkg_configfile} | cut -d '|' -f2)
    local instance_migration_group=$(grep ^instance-migration-group ${pkg_configfile} | cut -d '|' -f2)
    local instance_volume=""
    local line=""

    # get/validate instance migration strategy
    local instance_migration_type=$(grep ^instance-migration-type ${pkg_configfile} | cut -d '|' -f2)
    case ${instance_migration_type} in
    openstack|rsync-qemu)
        ;;
    *)
        assert "ERROR: invalid value for volume-migration-type in config file: ${pkg_configfile}"
        ;;
    esac

    # get volume migration strategy
    local volume_migration_type=$(grep ^volume-migration-type ${pkg_configfile} | cut -d '|' -f2)
    case ${volume_migration_type} in
    openstack|rsync-lvm)
        ;;
    *)
        assert "ERROR: invalid value for volume-migration-type in config file: ${pkg_configfile}"
        ;;
    esac

    # validate openstack RC files
    if [ ! -r ${osrc_source} ]; then assert "ERROR: missing RC file for source-cloud: ${osrc_source}"; fi
    if [ ! -r ${osrc_target} ]; then assert "ERROR: missing RC file for target-cloud: ${osrc_target}"; fi

    # Get user input for instance to migrate
    if [ $# -ne 1 ]; then return 1; fi

    # Check if config file exist for input provided (name/uuid)
    if [[ ! -f ${pkg_basedir}/configs/$1 ]]; then
        #  If config file exist call get_instance_uuid_name
        if ! instance_uuid_name=($(get_instance_uuid_name ${osrc_source} $1)); then
            assert "Failed resolving UUID and instance name"
        fi
        if [[ -f ${pkg_basedir}/configs/${instance_uuid_name[0]} ]]; then # Try UUID
            local migration_config=${pkg_basedir}/configs/${instance_uuid_name[0]}
        elif [[ -f ${pkg_basedir}/configs/${instance_uuid_name[1]} ]]; then # Try Name
            local migration_config=${pkg_basedir}/configs/${instance_uuid_name[1]}
        else
            assert "No config file found for ${instance_name} or ${instance_uuid}"
        fi
    else
        local migration_config=${pkg_basedir}/configs/$1
    fi

    # start migration
    local config=${migration_config}
    local migration_instanceName=$(basename ${migration_config})
    stdout "#### STARTING MIGRATION: Instance Name = ${migration_instanceName}"

    # create array of config files
    local config_array=( )
    config_idx=0
    while read line; do
        config_array[((config_idx++))]="${line}"
    done < ${config}

    # manage instance discovery cache
    local instance_db_source=${pkg_basedir}/db/${migration_instanceName}.json
    if [ -r ${instance_db_source} ]; then rm -f ${instance_db_source}; fi

    # Initialize Logger
    log_file=${pkg_basedir}/log/${migration_instanceName}.log
    init_log_file
    debug "Logger Started: ${log_file}"

    # migrate ephemeral image
    if [ ${FLAG_SKIP_EPHEMERAL_MIGRATION} -eq 0 ]; then
        stdout "\n[Source Instance Prep]"
        while read line; do
            # skip comments and blank lines
            if [ "${line:0:1}" == "#" -o -z "${line}" ]; then continue; fi

            lineArgs=($(parse_config_line "${line}"))
            if [ "${lineArgs[0]}" == "instance" ]; then
                source_instanceName=${lineArgs[1]}
                instance_type=${lineArgs[3]}
                target_instanceUuid=${lineArgs[11]}
                ephemeral_image_id=${lineArgs[7]}
                instance_project_id=${lineArgs[8]}

                # check if instance already exists on target cloud
                instance_exists ${osrc_target} ${source_instanceName} ${instance_project_id}
                if [ $? -eq 0 ]; then assert "ERROR: instance ${source_instanceName} already exists on target cloud"; fi

                # stop instance
                stdout "--> Power-off and Lock Source Instance"
                instance_status=$(get_instance_state ${osrc_source} ${target_instanceUuid})

                # stop instance
                if [ "${instance_status}" != "SHUTOFF" ]; then
                    stop_instance ${osrc_source} ${target_instanceUuid}
                    if [ $? -ne 0 ]; then assert "ERROR: failed to stop instance"; fi

                    # Poll for Instance to stop
                    wait_for_instance_state ${osrc_source} "${target_instanceUuid}" "SHUTOFF"
                    if [ $? -ne 0 ]; then assert "TIMEOUT: waiting for instance to shutdown"; fi
                fi

                # lock instance
                lock_instance ${osrc_source} ${target_instanceUuid}
                if [ $? -ne 0 ]; then assert "ERROR: failed to lock instance"; fi

                if [ "${instance_type}" == "ephemeral" ]; then
                    # create snapshot of ephemeral disk image
                    local ephemeral_instance_image="${source_instanceName}_ephemeral.img"
                    local ephemeral_instance_backing_image="${source_instanceName}_backing.img"
                    local tmp_image_file=/tmp/${ephemeral_instance_image}
                    local tmp_image_backing_file=/tmp/${ephemeral_instance_backing_image}
                    case ${instance_migration_type} in
                    openstack)
                        stdout "--> Creating Image from Ephemeral Instance: ${ephemeral_instance_image}"
                        image_exists ${osrc_source} ${ephemeral_instance_image}
                        if [ $? -ne 0 ]; then
                            create_image_from_ephemeral_instance ${osrc_source} ${source_instanceName} ${ephemeral_instance_image}
                            if [ $? -ne 0 ]; then assert "ERROR: failed to download image"; fi
                        fi

                        stdout -n "--> Waiting for image to become active:"
                        wait_for_image_state ${osrc_source} ${ephemeral_instance_image} "active"
                        if [ $? -ne 0 ]; then return 1; fi

                        # get image metadata
                        image_uuid=$(get_image_id ${osrc_source} ${ephemeral_instance_image})
                        image_format=$(get_image_format ${osrc_source} ${ephemeral_instance_image})
                        image_size=$(get_image_size ${osrc_source} ${ephemeral_instance_image})
                        image_checksum=$(get_image_checksum ${osrc_source} ${ephemeral_instance_image})
                        
                        # download snapshot of ephemeral disk image
                        stdout -n "--> Downloading Ephemeral Disk Image (Size = $(format_int ${image_size}) Bytes):"
                        if [ -r ${tmp_image_file} ]; then
                            stdout " already downloaded"
                        else
                            ensure_parent_dir ${tmp_image_file}
                            if [ -n "${glance_endpoint}" ]; then
                                image_download ${osrc_source} ${image_uuid} ${tmp_image_file} ${image_size} ${glance_endpoint}
                                if [ $? -ne 0 ]; then return 1; fi
                            else
                                image_download ${osrc_source} ${image_uuid} ${tmp_image_file} ${image_size}
                                if [ $? -ne 0 ]; then return 1; fi
                            fi

                            # validate checksum of downloaded image
                            downloaded_checksum=$(get_file_checksum ${tmp_image_file})
                            if [ "${image_checksum}" != "${downloaded_checksum}" ]; then
                                stdout "INFO: downloaded file checksum failed"
                            fi
                        fi

                        # upload disk image (to target cloud)
                        stdout -n "--> Uploading Ephemeral Disk Image to Target Cloud:"
                        image_exists ${osrc_target} ${ephemeral_instance_image}
                        if [ $? -eq 0 ]; then
                            stdout " already uploaded"
                        else
                            image_upload ${osrc_target} ${ephemeral_instance_image} ${tmp_image_file} ${image_size} ${image_format}
                            if [ $? -ne 0 ]; then return 1; fi
                        fi
                        ;;
                    rsync-qemu)
                        ;;
                    esac
                fi
            fi
        done < ${config}
    fi


    # migrate server group
    stdout "\n[Migrating/Remapping Server Group]"
    target_project_id=$(get_config_line "instance" ${INSTANCE_TARGET_PROJECT_ID} ${config_array[@]})
    remapped_server_group_id="undefined"
    num_sg_migrated=0
    for line in "${config_array[@]}"; do
        # skip comments and blank lines
        if [ "${line:0:1}" == "#" -o -z "${line}" ]; then continue; fi

        lineArgs=($(parse_config_line "${line}"))
        if [ "${lineArgs[0]}" == "property" ]; then
            property_key=$(echo "${lineArgs[1]}" | cut -d '=' -f1)
            if [ "${property_key}" == "group_name" ]; then
                source_sg_groupname=$(echo "${lineArgs[1]}" | cut -d '=' -f2 | sed "s/'//g")
                if [ -z "${source_sg_groupname}" ]; then assert "ERROR: failed to lookup server group name on source cloud"; fi

                # get server group id (on source cloud)
                source_sg_id=$(get_server_group_id ${osrc_source} ${source_sg_groupname})
                if [ -z "${source_sg_id}" ]; then assert "ERROR: failed to lookup server group id on source cloud"; fi

                # get server affinity rule
                affinity_rule=$(get_server_group_affinity ${osrc_source} ${source_sg_id})
                if [ $? -ne 0 ]; then assert "ERROR: failed to lookup server group affinity rule on source cloud"; fi

                # display source server group
                stdout "--> Source Server Group: ${source_sg_groupname} (policy=${affinity_rule}, uuid=${source_sg_id})"
                
                # create server group on target (if not exist)
                server_group_exists ${osrc_target} ${source_sg_groupname}
                if [ $? -ne 0 ]; then
                    stdout "--> Creating server group: ${source_sg_groupname}"
                    create_server_group ${osrc_target} ${source_sg_groupname} ${affinity_rule} ${target_project_id}
                    if [ $? -ne 0 ]; then assert "ERROR: failed to create server group on target cloud"; fi
                fi

                # get server group id (on target cloud)
                remapped_server_group_id=$(get_server_group_id ${osrc_target} ${source_sg_groupname})
                if [ -z "${remapped_server_group_id}" ]; then assert "ERROR: failed to lookup server group id on target cloud"; fi

                # save mappings for new server group
                stdout "--> Target (Re-mapped) Server Group: ${source_sg_groupname} (policy=${affinity_rule}, uuid=${remapped_server_group_id})"
                ((num_sg_migrated++))
            fi
        fi
    done
    if [ ${num_sg_migrated} -eq 0 ]; then
        stdout "info: no server group to migrate"
    fi

    # migrate volumes
    volumes_to_attach=( )
    volumes_to_attach_idx=0
    num_migrated_volumes=0
    for line in "${config_array[@]}"; do
        # skip comments and blank lines
        if [ "${line:0:1}" == "#" -o -z "${line}" ]; then continue; fi

        lineArgs=($(parse_config_line "${line}"))
        if [ "${lineArgs[0]}" == "instanceVol" ]; then
            # parse linaArgs using ordinal values in globals.sh
            SOURCE_INSTANCE_UUID=${lineArgs[$INSTANCEVOL_SOURCE_INSTANCE_UUID]}
            TARGET_VOLUME_NAME=${lineArgs[$INSTANCEVOL_TARGET_VOLUME_NAME]}
            SOURCE_VOLTYPE=${lineArgs[$INSTANCEVOL_SOURCE_VOLTYPE]}
            SOURCE_UUID=${lineArgs[$INSTANCEVOL_SOURCE_UUID]}
            SOURCE_PROJECT_NAME=${lineArgs[$INSTANCEVOL_SOURCE_PROJECT_NAME]}
            SOURCE_DEVICE_PATH=${lineArgs[$INSTANCEVOL_SOURCE_DEVICE_PATH]}
            SOURCE_MIG_STAT=${lineArgs[$INSTANCEVOL_SOURCE_MIG_STAT]}
            SOURCE_MIG_NAME_ID=${lineArgs[$INSTANCEVOL_SOURCE_MIG_NAME_ID]}
            IS_BOOTABLE=${lineArgs[$INSTANCEVOL_IS_BOOTABLE]}
            if [ "${IS_BOOTABLE}" == "true" ]; then instance_volume=${TARGET_VOLUME_NAME}; fi

            # call configuration-specific volume migration function
            case ${volume_migration_type} in
            openstack)
                migrate_volume ${SOURCE_INSTANCE_UUID} ${TARGET_VOLUME_NAME} ${SOURCE_UUID} ${osrc_source} ${osrc_target}
                if [ $? -ne 0 ]; then
                    stdout "WARNING: failed to migrate volume, volume name = ${lineArgs[1]}:${lineArgs[2]}"
                else
                    volumes_to_attach[((volumes_to_attach_idx++))]="${lineArgs[2]}"
                fi
                ;;
            rsync-lvm)
                migrate_volume_lvm_rsync ${SOURCE_INSTANCE_UUID} ${TARGET_VOLUME_NAME} ${SOURCE_UUID} ${SOURCE_MIG_STAT} ${SOURCE_MIG_NAME_ID} ${IS_BOOTABLE} ${SOURCE_PROJECT_NAME} ${osrc_source} ${osrc_target}
                if [ $? -ne 0 ]; then
                    stdout "WARNING: failed to migrate volume, volume name = ${lineArgs[1]}:${lineArgs[2]}"
                else
                    volumes_to_attach[((volumes_to_attach_idx++))]="${TARGET_VOLUME_NAME}"
                fi
                ;;
            esac
            ((num_migrated_volumes++))
        fi
    done
    if [ ${num_migrated_volumes} -eq 0 ]; then
        stdout "\n[Cinder Volume Migration]"
        stdout "info: no volumes to migrate"
    fi

    # read instance properties
    stdout "\n[Reading Instance Properties]"
    local prop_idx=0
    local config_drive="False"
    local instance_property_str=""
    while read line; do
        # skip comments and blank lines
        if [ "${line:0:1}" == "#" -o -z "${line}" ]; then continue; fi

        lineArgs=($(parse_config_line "${line}"))
        if [ "${lineArgs[0]}" == "property" ]; then
            property_key=$(echo "${lineArgs[1]}" | cut -d '=' -f1)
            property_val=$(echo "${lineArgs[1]}" | cut -d '=' -f2 | sed "s/'//g")
            if [ "${property_key}" == "group_id" ]; then
                property_val=${remapped_server_group_id}
            fi

            stdout "--> property : ${property_key}='${property_val}'"
            if [ -z "${instance_property_str}" ]; then
                instance_property_str="--property ${property_key}='${property_val}'"
            else
                instance_property_str="${instance_property_str} --property ${property_key}='${property_val}'"
            fi
            ((prop_idx++))
        elif [ "${lineArgs[0]}" == "config-drive" ]; then
            config_drive="${lineArgs[1]}"
        fi
    done < ${config}
    if [ ${prop_idx} -eq 0 ]; then stdout "info: no properties to migrate"; fi


    # start target instance
    stdout "\n[Start Target Instance]"
    while read line; do
        # skip comments and blank lines
        if [ "${line:0:1}" == "#" -o -z "${line}" ]; then continue; fi

        lineArgs=($(parse_config_line "${line}"))
        if [ "${lineArgs[0]}" == "instance" ]; then
            flag_fixedIp=""
            instance_type=${lineArgs[3]}
            instance_project_id=${lineArgs[8]}
            if [ ${#lineArgs[@]} -ge 7 ]; then
                if [ -n "${lineArgs[6]}" ]; then
                    flag_fixedIp=",v4-fixed-ip=${lineArgs[6]}"
                fi
            fi

            # configure launch parameters
            instance_name=${lineArgs[$INSTANCE_NAME]}
            instance_flavor=${lineArgs[$INSTANCE_TARGET_FLAVOR_ID]}
            instance_sec_group=${lineArgs[$INSTANCE_TARGET_SG_ID]}
            instance_netid=${lineArgs[$INSTANCE_TARGET_NETWORK_ID]}
            instance_fixed_ip=${flag_fixedIp}
            instance_project_id=${lineArgs[$INSTANCE_TARGET_PROJECT_ID]}
            instance_az=${lineArgs[$INSTANCE_SOURCE_AZ]}

            # configure SSH keypair
            keypair_config=$(get_config_line "key-name" 0 ${config_array[@]})
            if [ $? -ne 0 ]; then assert "ERROR: failed to get SSH keypair"; fi
            keypairArgs=($(parse_config_line "${keypair_config}"))
            instance_keypair=${keypairArgs[1]}

            # check az exception map
            az_exception=$(lookup_az_exception ${instance_az})
            if [ $? -eq 0 ]; then
                stdout "--> Exception found: re-mapping Availability Zone from ${instance_az} to ${az_exception}"
                instance_az=${az_exception}
            fi

            # migrate IP and/or MAC
            local target_port_uuid=""
            if [ ${flag_preserve_ip} -eq 1 ]; then
                stdout "--> Migrating IP/Mac address (creating port on target cloud)"
                port_config=$(get_config_line "port" 0 ${config_array[@]})
                if [ $? -ne 0 ]; then assert "ERROR: failed to get port configuration"; fi

                portArgs=($(parse_config_line "${port_config}"))
                port_fixed_ip=${portArgs[$PORT_FIXED_IP]}
                port_mac=${portArgs[$PORT_MAC]}
                port_net_id=${portArgs[$PORT_TARGET_NETWORK_UUID]}
                port_name="${instance_name}-port"

                # check if port exists (by programatically-assigned name)
                if ! port_exists ${osrc_target} ${port_name} ${instance_project_id}; then
                    # create port on target cloud
                    create_port ${osrc_target} ${port_net_id} ${port_fixed_ip} ${port_mac} ${instance_project_id} ${port_name}
                    if [ $? -ne 0 ]; then assert "ERROR: failed to create the Neutron port"; fi
                fi

                # get uuid for port just created
                target_port_metadata=$(get_neutron_port_id ${osrc_target} ${port_fixed_ip} ${instance_project_id})
                if [ $? -ne 0 ]; then assert "failed to get port uuid"; fi

                target_port_uuid=$(echo "${target_port_metadata}" | cut -d ' ' -f1)
                if [ -z "${target_port_uuid}" ]; then assert "ERROR: failed to parse target_port_uuid"; fi
                stdout "--> target_port_uuid = ${target_port_uuid}"
            fi

            # launch instance
            if [ "${instance_type}" == "ephemeral" ]; then
                # check if instance already exists
                instance_exists ${osrc_target} ${lineArgs[1]} ${instance_project_id}
                if [ $? -eq 0 ]; then assert "ERROR: instance ${lineArgs[1]} already exists on target cloud"; fi

                # configure image (differs based on migration type)
                if [ "${instance_migration_type}" == "openstack" ]; then
                    instance_image=${ephemeral_instance_image}
                elif [ "${instance_migration_type}" == "rsync-qemu" ]; then
                    instance_image=${lineArgs[7]}
                fi

                # lookup security group uuid -OR- implement user-defined security group
                if [ -n "${user_defined_sg}" ]; then instance_sec_group=${user_defined_sg}; fi

                # implement user-defined availability zone
                if [ -n "${user_defined_az}" ]; then instance_az=${user_defined_az}; fi

                # for ephemeral instances
                stdout "--> Starting ephemeral instance '${lineArgs[1]}'"
                create_instance_from_image ${osrc_target} ${instance_name} ${instance_image} ${instance_flavor} \
                    ${instance_sec_group} ${instance_netid} ${instance_fixed_ip} ${instance_az} \
                    ${instance_project_id} ${config_drive} ${instance_keypair} ${remapped_server_group_id} ${user_defined_hv} "${instance_property_str}" ${target_port_uuid}
                if [ $? -ne 0 ]; then assert "ERROR: instance failed to launch"; fi

                # get instance uuid (in a retry loop, to account for instance launch)
                local cnt=0
                while [ ${cnt} -lt ${RETRY_ATTEMPTS} ]; do
                    target_instance_uuid=$(get_instance_id ${osrc_target} ${instance_name} ${instance_project_id})
                    if [ $? -eq 0 ]; then break; fi
                    sleep ${RETRY_DELAY}
                    ((cnt++))
                done
                if [ ${cnt} -ge ${RETRY_ATTEMPTS} ]; then assert "ERROR: failed to get instance uuid"; fi
                stdout "--> target_instance_uuid = ${target_instance_uuid}"

                # Poll for Instance to start
                stdout -n "--> Waiting for instance to start:"
                wait_for_instance_state ${osrc_target} "${target_instance_uuid}" "ACTIVE"
                exit_status=$?
                if [ ${exit_status} -eq 0 ]; then
                    :
                elif [ ${exit_status} -eq 2 ]; then
                    assert "TIMEOUT: the instance is in an ERROR state"
                else
                    assert "TIMEOUT: waiting for instance to become active"
                fi

                # get instance metadata (json)
                stdout "--> Looking up metadata for target instance"
                local instance_db_target=${pkg_basedir}/db/${instance_name}.target.json
                get_instance ${osrc_target} ${target_instance_uuid} ${instance_db_target}
                if [ $? -ne 0 ]; then assert "failed to get instance metadata"; fi

                if [ "${instance_migration_type}" == "rsync-qemu" ]; then
                    stdout "\n[Post-Launch Image Update]"
                    stdout -n "--> Stopping instance on target cloud"
                    stop_instance ${osrc_target} ${target_instance_uuid}
                    if [ $? -ne 0 ]; then assert "ERROR: failed to stop instance"; fi

                    # Poll for Instance to stop
                    wait_for_instance_state ${osrc_target} "${target_instance_uuid}" "SHUTOFF"
                    if [ $? -ne 0 ]; then assert "TIMEOUT: waiting for instance to shutdown"; fi

                    ##############################################################################
                    ## lookup instance metadata on TARGET CLOUD
                    ##############################################################################
                    # discover hypervisor
                    local target_hypervisor=$(get_hypervisor ${instance_db_target})
                    stdout "--> target hypervisor = ${target_hypervisor}"

                    # map & validate ephemeral image on hypervisor
                    local target_hv_ip_image_path=$(get_ephemeral_image_path_on_hv ${target_hypervisor} ${target_instance_uuid})
                    if [ -z "${target_hv_ip_image_path}" ]; then
                        assert "ERROR: filed to map hypervisor: ${target_hypervisor} (map file = ${hv_map})"
                    fi
                    if ! validate_ephemeral_image_path_on_hv ${target_hv_ip_image_path}; then
                        assert "ERROR: failed to validate image path on hypervisor"
                    fi

                    # parse image_path_hv
                    local target_hv_ip=$(echo "${target_hv_ip_image_path}" | cut -d ':' -f1)
                    local target_hv_image_path=$(echo "${target_hv_ip_image_path}" | cut -d ':' -f2)
                    stdout "--> image path on target: ${target_hv_ip}:${target_hv_image_path}"

                    ##############################################################################
                    ## lookup instance metadata on SOURCE CLOUD
                    ##############################################################################
                    # map & validate ephemeral image on hypervisor
                    stdout "--> Looking up metadata for source cloud"
                    local source_hv_ip_image_path=$(get_ephemeral_image_path_on_hv ${lineArgs[10]} ${lineArgs[11]})
                    if [ -z "${source_hv_ip_image_path}" ]; then
                        assert "ERROR: filed to map hypervisor: ${lineArgs[10]} (map file = ${hv_map})"
                    fi
                    if ! validate_ephemeral_image_path_on_hv ${source_hv_ip_image_path}; then
                        assert "ERROR: failed to validate image path on hypervisor"
                    fi
                    # Get list of all images mounted on instance returns array
                    image_list=($(get_remote_qemu_image_list ${source_hv_ip_image_path}))
                    for image in ${image_list[@]}; do
                        if [ "$(basename ${image})" == "disk.config" ]; then continue; fi

                        # initialize flag (for detecting if backing images were converted)
                        local flag_cleanup_converted_file=0

                        # parse image_path_hv
                        local source_hv_ip=$(echo "${source_hv_ip_image_path}" | cut -d ':' -f1)
                        local source_hv_image=${image}
                        local target_hv_image=${target_hv_image_path}/$(basename ${source_hv_image})
                        local image_metadata_tmpfile=/tmp/vol-metadata.$$.dat
                        stdout "--> image path on source: ${source_hv_ip}:${source_hv_image}"

                        # get image metadata from qemu on target hypervisor
                        if ! get_remote_qemu_image_info ${source_hv_ip} ${source_hv_image} > ${image_metadata_tmpfile}; then
                            assert "ERROR: failed to get image metadata (from QEMU)"
                        fi
                        local image_size=$(jq -r '.[0]."actual-size"' ${image_metadata_tmpfile})

                        # copy images from SOURCE hypervisor to TARGET hypervisor
                        stdout "--> performing direct transfer of ephemeral image, file size = ${image_size} bytes"
                        scp_target_to_source ${source_hv_ip} ${source_hv_image} ${target_hv_ip} ${target_hv_image} ${source_ssh_username} ${source_ssh_privatekey} ${image_size}
                        if [ $? -ne 0 ]; then assert "ERROR: Failed to transfer ephemeral image to target hypervisor"; fi

                        stdout "    Checking for backing image"
                        if $(jq -r '.[1] != null'); then
                            # Check if backing image is raw or qcow
                            if $(jq -r '.[1]."format" == "raw"' ${image_metadata_tmpfile}); then
                                # If backing file is raw, convert to qcow2 before migration
                                flag_cleanup_converted_file=1
                                local orig_backing_image_path=$(jq -r '.[1]."filename"' ${image_metadata_tmpfile})
                                local orig_backing_image_basename=$(basename ${orig_backing_image_path})
                                local backing_image_path=/tmp/migrate_${orig_backing_image_basename}
                                stdout "    RAW backing image found"
                                stdout "        ${orig_backing_image_path}"
                                stdout "        Original Size: $(jq -r '.[1]."virtual-size"' ${image_metadata_tmpfile}) bytes"
                                stdout -n "    Converting to qcow2:"
                                if ! convert_image_raw_qcow2_on_hv ${source_hv_ip} ${orig_backing_image_path} ${backing_image_path}; then
                                    assert "Failed converting backing image to qcow2"
                                fi
                                stdout " Complete"
                                stdout "        ${backing_image_path}"
                                if ! local backing_image_size=$(get_remote_filesize ${source_hv_ip} ${backing_image_path}); then
                                    assert "Failed getting filesize of converted backing image"
                                fi
                                stdout "        New Image Size: ${backing_image_size} bytes"
                            else
                                local backing_image_size=$(jq -r '.[1]."virtual-size"' ${image_metadata_tmpfile})
                                local backing_image_path=$(jq -r '.[1]."filename"' ${image_metadata_tmpfile})
                            fi
                            local merged_path=$(update_image_path ${target_hv_image} ${backing_image_path})
                            stdout "--> performing direct transfer of backing image, file size = ${backing_image_size} bytes"
                            scp_target_to_source ${source_hv_ip} ${backing_image_path} ${target_hv_ip} ${merged_path} ${source_ssh_username} ${source_ssh_privatekey} ${backing_image_size}
                            if [ $? -ne 0 ]; then assert "ERROR: Failed to transfer backing image to target hypervisor"; fi

                            # if backing file was coverted, remove the temp file
                            if [ ${flag_cleanup_converted_file} -eq 1 ]; then
                                stdout "--> removing converted backing image on source hypervisor (${backing_image_path})"
                                if ! delete_remote_file ${source_hv_ip} ${backing_image_path}; then
                                    stdout "WARNING (non-fatal): failed to remove converted backing image on source hypervisor"
                                fi
                            fi
                        fi

                        # update image metadata (qemu) to point to correct backing-image location
                        set_image_backingstore_metadata ${target_hv_ip} ${target_hv_image} ${merged_path}
                    done

                    # start instance
                    stdout "--> Re-starting instance with updated image"
                    start_instance ${osrc_target} ${target_instance_uuid}
                    if [ $? -ne 0 ]; then assert "ERROR: failed to stop instance"; fi

                    # poll for Instance to start
                    stdout "--> Waiting for instance to start"
                    wait_for_instance_state ${osrc_target} "${target_instance_uuid}" ACTIVE
                    if [ $? -ne 0 ]; then assert "TIMEOUT: waiting for instance to become active"; fi
                fi
            else
                # validate that a boot volume was migrated
                if [ -z "${instance_volume}" ]; then assert ""; fi

                # lookup security group uuid -OR- implement user-defined security group
                if [ -n "${user_defined_sg}" ]; then instance_sec_group=${user_defined_sg}; fi

                # implement user-defined availability zone
                if [ -n "${user_defined_az}" ]; then instance_az=${user_defined_az}; fi

                # for volume-backed instances
                stdout "--> Starting volume-backed instance '${lineArgs[$INSTANCE_NAME]}'"
                create_instance_from_volume ${osrc_target} ${instance_name} ${instance_volume} ${instance_flavor} \
                    ${instance_sec_group} ${instance_netid} ${instance_fixed_ip} ${instance_az} \
                    ${instance_project_id} ${config_drive} ${instance_keypair} ${remapped_server_group_id} ${user_defined_hv} "${instance_property_str}" ${target_port_uuid}
                if [ $? -ne 0 ]; then assert "ERROR: instance failed to launch"; fi

                # Poll for Instance to start
                stdout "--> Waiting for instance to start"
                wait_for_instance_state ${osrc_target} "${instance_name}" ACTIVE
                if [ $? -ne 0 ]; then assert "TIMEOUT: waiting for instance to become active"; fi
            fi
        fi
    done < ${config}

    # attach additional volumes
    stdout "\n[Attach Additional Volumes]"
    v=0
    while read line; do
        # skip comments and blank lines
        if [ "${line:0:1}" == "#" -o -z "${line}" ]; then continue; fi

        lineArgs=($(parse_config_line "${line}"))
        if [ "${lineArgs[0]}" == "instanceVol" ]; then
            # parse linaArgs using ordinal values in globals.sh
            SOURCE_INSTANCE_UUID=${lineArgs[$INSTANCEVOL_SOURCE_INSTANCE_UUID]}
            TARGET_VOLUME_NAME=${lineArgs[$INSTANCEVOL_TARGET_VOLUME_NAME]}
            SOURCE_VOLTYPE=${lineArgs[$INSTANCEVOL_SOURCE_VOLTYPE]}
            SOURCE_UUID=${lineArgs[$INSTANCEVOL_SOURCE_UUID]}
            SOURCE_PROJECT_NAME=${lineArgs[$INSTANCEVOL_SOURCE_PROJECT_NAME]}
            SOURCE_DEVICE_PATH=${lineArgs[$INSTANCEVOL_SOURCE_DEVICE_PATH]}
            IS_BOOTABLE=${lineArgs[$INSTANCEVOL_IS_BOOTABLE]}

            # skip bootable volumes
            if [ "${IS_BOOTABLE}" == "true" ]; then continue; fi

            # skip volumes that failed to migrate
            in_array "${TARGET_VOLUME_NAME}" "${volumes_to_attach[@]}"
            if [ $? -ne 0 ]; then
                stdout "--> Skipping volume attachment due to migration failure: ${TARGET_VOLUME_NAME}"
                continue
            fi

            # attach volume
            if [ ${flag_preserve_deviceNames} -eq 1 ]; then
                stdout "--> Attaching volume '${TARGET_VOLUME_NAME}' to ${instance_name} as device '${SOURCE_DEVICE_PATH}'"
                attach_volume ${osrc_target} ${target_instance_uuid} $(get_volume_id ${osrc_target} ${TARGET_VOLUME_NAME} ${SOURCE_PROJECT_NAME}) ${SOURCE_DEVICE_PATH}
                if [ $? -ne 0 ]; then assert "ERROR: failed to attach volume to instance"; fi
            else
                stdout "--> Attaching volume '${TARGET_VOLUME_NAME}' to ${instance_name} as device 'auto-assign'"
                attach_volume ${osrc_target} ${target_instance_uuid} $(get_volume_id ${osrc_target} ${TARGET_VOLUME_NAME} ${SOURCE_PROJECT_NAME})
                if [ $? -ne 0 ]; then assert "ERROR: failed to attach volume to instance"; fi
            fi

            ((v++))
        fi
    done < ${config}
    if [ ${v} -eq 0 ]; then stdout "--- no additional volumes ---"; fi

    # attach additional security groups
    stdout "\n[Attach Additional Securty Groups]"
    s=0
    while read line; do
        # skip comments and blank lines
        if [ "${line:0:1}" == "#" -o -z "${line}" ]; then continue; fi

        lineArgs=($(parse_config_line "${line}"))
        if [ "${lineArgs[0]}" == "securityGroup" ]; then
            stdout "--> Adding Security Group '${lineArgs[2]}'"
            attach_security_group ${osrc_target} ${lineArgs[1]} ${lineArgs[2]}
            if [ $? -ne 0 ]; then assert "ERROR: failed to attach security group instance"; fi
            ((s++))
        fi
    done < ${config}
    if [ ${s} -eq 0 ]; then stdout "--- no additional security groups ---"; fi

    # display complete message (and total time for migration)
    local migration_end=$(date +%s)
    local migration_total=$((migration_end - migration_start))
    stdout "\n[MIGRATION COMPLETE]"
    stdout "--> Total Time for migration: $(format_time ${migration_total})"
}
