# locking functions
get_lock() {
    if [ $# -ne 1 ]; then return 1; fi
    mkdir ${lockdir}/`basename ${1}` > /dev/null 2>&1 && return 0
    return 1
}

release_lock() {
    if [ $# -ne 1 ]; then return 1; fi
    rmdir ${lockdir}/`basename ${1}` > /dev/null 2>&1 && return 0
    return 1
}

wait_for_lock() {
    if [ $# -ne 1 ]; then return 1; fi
    local timeout=10
    local t0=`date +%s`
    local elapsed_time=0
    local t1
    while [ ${elapsed_time} -lt ${timeout} ]; do
        get_lock "${lockdir}/`basename ${1}`" && return 0
        sleep 0.1; t1=`date +%s`; elapsed_time=$((${t1} - ${t0}))
    done
    return 1
}
