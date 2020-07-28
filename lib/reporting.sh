################################################################################
# Reporting Functions
################################################################################
# instance header
header_char='-'
IF1=20; IB1=$(printf '%*s' "$IF1" | tr ' ' "$header_char")
IF2=15; IB2=$(printf '%*s' "$IF2" | tr ' ' "$header_char")
IF3=37; IB3=$(printf '%*s' "$IF3" | tr ' ' "$header_char")
IF4=32; IB4=$(printf '%*s' "$IF4" | tr ' ' "$header_char")
IF5=20; IB5=$(printf '%*s' "$IF5" | tr ' ' "$header_char")

# volume header
VF1=36; VB1=$(printf '%*s' "$VF1" | tr ' ' "$header_char")
VF2=20; VB2=$(printf '%*s' "$VF2" | tr ' ' "$header_char")
VF3=16; VB3=$(printf '%*s' "$VF3" | tr ' ' "$header_char")
VF4=20; VB4=$(printf '%*s' "$VF4" | tr ' ' "$header_char")
VF5=10; VB5=$(printf '%*s' "$VF5" | tr ' ' "$header_char")
VF6=21; VB6=$(printf '%*s' "$VF6" | tr ' ' "$header_char")

print_instance_header() {
  printf "%-${IF1}s %-${IF2}s %-${IF3}s %-${IF4}s %-${IF5}s\n" \
         "${IB1}" "${IB2}" "${IB3}" "${IB4}" "${IB5}"
  printf "%-${IF1}s %-${IF2}s %-${IF3}s %-${IF4}s %-${IF5}s\n" \
         "${1}" "${2}" "${3}" "${4}" "${5}"
  printf "%-${IF1}s %-${IF2}s %-${IF3}s %-${IF4}s %-${IF5}s\n" \
         "${IB1}" "${IB2}" "${IB3}" "${IB4}" "${IB5}"
}

print_volume_header() {
  printf "%-${VF1}s %-${VF2}s %-${VF3}s %-${VF4}s %-${VF5}s %-${VF6}s\n" \
         "${VB1}" "${VB2}" "${VB3}" "${VB4}" "${VB5}" "${VB6}"
  printf "%-${VF1}s %-${VF2}s %-${VF3}s %-${VF4}s %-${VF5}s %-${VF6}s\n" \
         "${1}" "${2}" "${3}" "${4}" "${5}" "${6}"
  printf "%-${VF1}s %-${VF2}s %-${VF3}s %-${VF4}s %-${VF5}s %-${VF6}s\n" \
         "${VB1}" "${VB2}" "${VB3}" "${VB4}" "${VB5}" "${VB6}"
}

print_instance_row() {
  printf "%-${IF1}s %-${IF2}s %-${IF3}s %-${IF4}s %-${IF5}s\n" \
         "${1}" "${2}" "${3}" "${4}" "${5}"
}

print_voume_row() {
  printf "%-${VF1}s %-${VF2}s %-${VF3}s %-${VF4}s %-${VF5}s %-${VF6}s\n" \
         "${1}" "${2}" "${3}" "${4}" "${5}" "${6}"
}

format_time() {
  if [ $# -ne 1 ]; then echo "-- bad time format --"; fi

  # calculate time components
  local time_str="-"
  local elapsed_time=${1}
  if [ ! -z "${elapsed_time}" ]; then
    hour=$(( ${elapsed_time}/3600 ))
    min=$(( (${elapsed_time}/60) % 60 ))
    sec=$(( ${elapsed_time} % 60 ))
    time_str=`printf "%02dh:%02dm:%02ds" ${hour} ${min} ${sec}`
  fi

  echo "${time_str}"
}

format_int() {
  if [ $# -ne 1 ]; then return 1; fi
  printf "%'d" ${1}
}

wait_for_pid() {
    if [ $# -ne 2 ]; then return 1; fi
    local pid=${1}
    local timeout=${2}
    
    # timeout loop
    local elapsed_time=0
    local start_time=$(date +%s)
    while [ ${elapsed_time} -lt ${timeout} ]; do
        echo -n "."
        ps -q ${pid} > /dev/null 2>&1
        if [ $? -eq 1 ]; then break; fi
        sleep ${WAIT_FOR_SLEEPTIME}
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
    done
    echo "$(format_time ${elapsed_time})"
    if [ ${elapsed_time} -ge ${timeout} ]; then return 1; fi
    return 0
}


