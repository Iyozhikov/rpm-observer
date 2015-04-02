#!/bin/bash
# requires yum-utils package installed!
#
declare -a INTERESTEDIN=("*openstack*" "python-*client")
DEPLVL=0
DEPLVL_STR=""
MAKE_DEPLVLFILES=false
MAX_DEPLVL=${MAX_DEPLVL:-2}
SEARCH_UPSTREAM=${SEARCH_UPSTREAM:-true}
START_WITH_OUR_REPO="${START_WITH_OUR_REPO:-centos-fuel-master}"
START_DIR="$(dirname "${0}" | pwd)"
LOGDIR="${START_DIR}/logs"

#Functions
function set_deplvl()
{
    DEPLVL=$1
    DEPLVL_STR=""
    case "${DEPLVL}" in
        [1-9])
            for i in $(seq "${DEPLVL}")
            do
                DEPLVL_STR+=" . "
            done
            ;;
        *)
            DEPLVL_STR=""
            ;;
    esac
}

function get_1st_level()
{
    local depregex="$*"
    local query_additional_params=""
    if [ ! -z "${START_WITH_OUR_REPO}" ]; then
        query_additional_params="--repoid=${START_WITH_OUR_REPO}"
    fi
    local query_format="%{name} %{version} %{release} %{repoid}"
    while read line
    do
        echo "${line}"
    done < <(repoquery  --qf "${query_format}" "${query_additional_params}" "${depregex}")
}

function get_next_level()
{
    local depregex="$*"
    local query_format="%{name} %{version} %{release} %{repoid}"
    local query_additional_params="--archlist=x86_64,noarch"
    if [ "${DEPLVL}" -ge "${MAX_DEPLVL}" ]; then
        return
    else
        set_deplvl $(( DEPLVL + 1 ))
    fi
    while read line
    do
        if [ ! -z "${line}" ]; then
            local pname=$(echo "${line}" | cut -d' ' -f1)
            local pver=$(echo "${line}" | cut -d' ' -f2)
            local prel=$(echo "${line}" | cut -d' ' -f3)
            local reponame=$(echo "${line}" | cut -d' ' -f4)
            local ext_pname=''
            local ext_pver=''
            local ext_prel=''
            local ext_reponame=''
            if [ "${SEARCH_UPSTREAM}" == true ]; then
                local extinfo=$(repoquery --disablerepo="${START_WITH_OUR_REPO}" --archlist=x86_64,noarch --qf "%{name} %{version} %{release} %{repoid}" "${pname}")
                if [ ! -z "${extinfo}" ]; then
                    ext_pname=$(echo "${extinfo}" | cut -d' ' -f1)
                    ext_pver=$(echo "${extinfo}" | cut -d' ' -f2)
                    ext_prel=$(echo "${extinfo}" | cut -d' ' -f3)
                    ext_reponame=$(echo "${extinfo}" | cut -d' ' -f4)
                fi
            fi
            log "${pname}, ${pver}, ${prel}, ${reponame}, ${ext_pname}, ${ext_pver}, ${ext_prel}, ${ext_reponame}"
            get_next_level "${pname}"
        fi
    done < <(repoquery  --qf "${query_format}" "${query_additional_params}" --requires --resolve "${depregex}")
    set_deplvl $(( DEPLVL - 1 ))
}

function process_interested()
{
    local input="$*"
    while read line
    do
        if [ ! -z "${line}" ]; then
            local pname=$(echo "${line}" | cut -d' ' -f1)
            local pver=$(echo "${line}" | cut -d' ' -f2)
            local prel=$(echo "${line}" | cut -d' ' -f3)
            local reponame=$(echo "${line}" | cut -d' ' -f4)
            log "${pname}, ${pver}, ${prel}, ${reponame}, , , ,"
            get_next_level "${pname}"
            log ""
        fi
        set_deplvl 0
    done < <(get_1st_level "${input}")
}

function log()
{
    local input="$*"
    if [ "${MAKE_DEPLVLFILES}" == "true" ]; then
        #local input="$*"
        local teefile="${DEPLVL}-packages.txt"
        local teefile_path="${LOGDIR}/${teefile}"
        if [ ! -d "${LOGDIR}" ]; then
            mkdir -p "${LOGDIR}"
        fi
        echo "${DEPLVL_STR}${input}"
        if [ ! -z "${input}" ]; then
            echo "${input}" >> "${teefile_path}"
        fi
    else
        echo "${DEPLVL_STR}${input}"
    fi
}

function get_uniqs_from_file()
{
    if [ ! -d "${LOGDIR}" ]; then
        echo "Log directory(\"${LOGDIR}\") does not exists!"
        exit 1
    fi
    while read line
    do
        if [ ! -z "${line}" ]; then
            local file_base_name="${line%.*}"
            local uniq_file_name="${file_base_name}-uniq.csv"
            sort -u < "${LOGDIR}/${line}" >> "${LOGDIR}/${uniq_file_name}"
        fi
    done < <(ls "${LOGDIR}")
}

function deduplicate()
{
    if [ ! -d "${LOGDIR}" ]; then
        echo "Log directory(\"${LOGDIR}\") does not exists!"
        exit 1
    fi
    local -a files_to_process
    while read line
    do
        if [ ! -z "${line}" ] & [ "${line##*.}" == "csv" ]; then
            files_to_process=("${files_to_process[@]}" "${line}")
        fi
    done < <(ls "${LOGDIR}")
    if [ "${#files_to_process[@]}" -ge 2 ]; then
        local file_pairs=$(( ${#files_to_process[@]} - 1 ))
        while [ ${file_pairs} -ne 0 ]
        do
            local last_file="${files_to_process[${file_pairs}]}"
            local first_file="${files_to_process[$(( file_pairs - 1 ))]}"
            echo "${first_file} ${last_file}"
            while read line
            do
                #echo "${line}"
                sed "/${line}/d" -i "${LOGDIR}/${last_file}"
            done < <(comm -1 "${LOGDIR}/${first_file}" "${LOGDIR}/${last_file}" | grep -E '^[[:space:]]' | grep -oE '\w+.*$')
            file_pairs=$(( file_pairs - 1 ))
        done
    fi
}

case "${1}" in
    "mklvlfiles")
        MAKE_DEPLVLFILES=true
        ;;
    *)
        ;;
esac
# Main runtime
for i in $(seq 0 $(( ${#INTERESTEDIN[@]} - 1 )))
do
    process_interested "${INTERESTEDIN[${i}]}"
done
get_uniqs_from_file
deduplicate
exit
