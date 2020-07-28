################################################################################
# Functions for performing LVM operations
################################################################################

lvm_deactivate_lv() {
    debug "lvm_deactivate_lv():"
    if [ $# -ne 3 ]; then return 1; fi
    local cinder_ip=${1}
    local volume_group=${2}
    local source_lv_name=${3}
    local ssh_flags="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

    stdout "--> Deactivating logical volume: ${volume_group}/${source_lv_name}"
    ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${cinder_ip} \
        "sudo lvchange -an ${volume_group}/${source_lv_name}" |& debug
    lv_attrs=$(ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${cinder_ip} "sudo lvs | grep '^  ${source_lv_name}'")
    stdout "    Attributes = ${lv_attrs}"
}

lvm_activate_lv() {
    debug "lvm_activate_lv():"
    if [ $# -ne 3 ]; then return 1; fi
    local cinder_ip=${1}
    local volume_group=${2}
    local source_lv_name=${3}
    local ssh_flags="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

    stdout "--> Activating logical volume: ${volume_group}/${source_lv_name}"
    ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${cinder_ip} \
        "sudo lvchange -ay ${volume_group}/${source_lv_name}" |& debug
    lv_attrs=$(ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${cinder_ip} "sudo lvs | grep '^  ${source_lv_name}'")
    stdout "    Attributes = ${lv_attrs}"
}

lvm_snapshot_exists() {
    debug "lvm_snapshot_exists():"
    if [ $# -ne 2 ]; then return 1; fi
    local cinder_ip=${1}
    local snapshot_name=${2}
    local ssh_flags="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

    ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${cinder_ip} \
        "sudo lvs | grep ${snapshot_name}" |& debug
}

lvm_create_snapshot() {
    if [ $# -ne 4 ]; then return 1; fi
    local cinder_ip=${1}
    local snapshot_name=${2}
    local source_path=${3}
    local lvm_snapshot_buffer_size=${4}
    local ssh_flags="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

    cmd="sudo lvcreate -L${lvm_snapshot_buffer_size} -s -n ${snapshot_name} ${source_path}"
    stdout "--> Taking snapshot of LV"
    ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${cinder_ip} ${cmd} |& debug
}

lvm_delete_snapshot() {
    if [ $# -ne 3 ]; then return 1; fi
    local cinder_ip=${1}
    local volume_group=${2}
    local snapshot_name=${3}
    local ssh_flags="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

    ssh ${ssh_flags} -i ${source_ssh_privatekey} ${source_ssh_username}@${cinder_ip} \
        "sudo lvremove -y ${volume_group}/${snapshot_name}" |& debug
}

