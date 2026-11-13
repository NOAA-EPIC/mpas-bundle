# MPAS-JEDI environment (modules only).  SOURCE this file:
#
#   source setenv_mpas.sh                      # this machine (auto-detected), spack-stack 2.1.1
#   source setenv_mpas.sh -s 1.9.2             # older stack
#   source setenv_mpas.sh -m hera -s 2.1.1     # name the machine explicitly
#   source setenv_mpas.sh -B /path/build2      # build dir (-S for the mpas-bundle source)
#   source setenv_mpas.sh 1.9.2                # old form, still works
#
# Machine settings live in mpas_machines.sh (same directory).
# Defaults can also come from MPAS_MACHINE / MPAS_STACK. Paths can be set first:
#   MPAS_SRC=/path/to/mpas-bundle MPAS_BUILD=/path/to/build source setenv_mpas.sh

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "setenv_mpas.sh: source it instead:  source ${0} [-m machine] [-s stack]" >&2
  exit 1
fi

_mpas_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "${_mpas_dir}/mpas_machines.sh" || return 1

_mpas_args=("$@")
_mpas_i=0
while [[ ${_mpas_i} -lt ${#_mpas_args[@]} ]]; do
  case ${_mpas_args[_mpas_i]} in
    -m) MPAS_MACHINE=${_mpas_args[_mpas_i+1]}; _mpas_i=$((_mpas_i + 2)) ;;
    -s) MPAS_STACK=${_mpas_args[_mpas_i+1]};   _mpas_i=$((_mpas_i + 2)) ;;
    -S) MPAS_SRC=$(readlink -m "${_mpas_args[_mpas_i+1]}");   _mpas_i=$((_mpas_i + 2)) ;;
    -B) MPAS_BUILD=$(readlink -m "${_mpas_args[_mpas_i+1]}"); _mpas_i=$((_mpas_i + 2)) ;;
    [0-9]*.*) MPAS_STACK=${_mpas_args[_mpas_i]}; _mpas_i=$((_mpas_i + 1)) ;;
    *) echo "setenv_mpas.sh: unknown argument '${_mpas_args[_mpas_i]}' (use -m machine -s stack -S src -B build)" >&2
       return 1 ;;
  esac
done

MPAS_STACK=${MPAS_STACK:-2.1.1}
MPAS_MACHINE=${MPAS_MACHINE:-$(mpas_detect_machine)}
if [[ ${MPAS_MACHINE} == unknown ]]; then
  echo "setenv_mpas.sh: could not detect the machine from '$(hostname)'; use -m (${MPAS_MACHINES[*]})" >&2
  return 1
fi
mpas_machine_config "${MPAS_MACHINE}" "${MPAS_STACK}" || return 1

if [[ -n ${MPAS_WORK} ]]; then
  MPAS_SRC=${MPAS_SRC:-${MPAS_WORK}/mpas-bundle}
  MPAS_BUILD=${MPAS_BUILD:-${MPAS_WORK}/build}
elif [[ -z ${MPAS_SRC:-} || -z ${MPAS_BUILD:-} ]]; then
  echo "setenv_mpas.sh: set MPAS_SRC and MPAS_BUILD for ${MPAS_MACHINE}" >&2
  return 1
fi

# --- 1. get conda out of the way (its MKL/python broke the link before) ---
conda deactivate 2>/dev/null; conda deactivate 2>/dev/null
for _v in PATH LD_LIBRARY_PATH LIBRARY_PATH CPATH PKG_CONFIG_PATH CMAKE_PREFIX_PATH PYTHONPATH; do
  _val=$(printenv "${_v}" | tr ':' '\n' | grep -v -e anaconda3 -e miniconda -e '/conda/' | paste -sd: -)
  if [[ -n ${_val} ]]; then export "${_v}=${_val}"; else unset "${_v}"; fi
done
unset CONDA_PREFIX CONDA_DEFAULT_ENV CONDA_PYTHON_EXE CONDA_SHLVL CONDA_EXE MKLROOT
hash -r

# --- 2. modules ---
if ! type module >/dev/null 2>&1; then  # batch jobs may start without Lmod
  for _f in /apps/lmod/lmod/init/bash /usr/share/lmod/lmod/init/bash /etc/profile.d/lmod.sh /etc/profile.d/modules.sh; do
    [[ -f ${_f} ]] && { source "${_f}"; break; }
  done
fi
module purge
module use "${MPAS_CORE}"
for _m in "${MPAS_MODULES[@]}"; do
  if ! module load "${_m}"; then
    echo "setenv_mpas.sh: 'module load ${_m}' failed; try: module spider ${_m%%/*}" >&2
    return 1
  fi
done

# --- 3. sanity checks ---
_mpas_ok=true
if env | grep -q -e anaconda3 -e miniconda; then
  echo "WARNING: conda paths still in the environment:" >&2
  env | grep -e anaconda3 -e miniconda | cut -c1-120 >&2
  _mpas_ok=false
fi
[[ -z ${MKLROOT:-} ]] && { echo "WARNING: MKLROOT not set by the modules" >&2; _mpas_ok=false; }
for _x in ecbuild mpiexec python3; do
  command -v "${_x}" >/dev/null || { echo "WARNING: ${_x} not found" >&2; _mpas_ok=false; }
done

echo "MPAS-JEDI env: ${MPAS_MACHINE} | spack-stack ${MPAS_STACK} | build=${MPAS_BUILD} | python3=$(command -v python3) | MKLROOT=${MKLROOT:-unset}"
${_mpas_ok} || echo "MPAS-JEDI env: loaded with warnings (see above)" >&2
MPAS_SCRIPTS=${MPAS_SCRIPTS:-${_mpas_dir}}
export MPAS_MACHINE MPAS_STACK MPAS_SRC MPAS_BUILD MPAS_SCRIPTS
unset _v _val _m _x _f _mpas_ok _mpas_args _mpas_i _mpas_dir
