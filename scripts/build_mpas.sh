#!/bin/bash
#
# Build MPAS-JEDI. Runs on the login node, or submits itself to one whole node.
#
#   ./build_mpas.sh                     fresh build here, auto-detected machine, spack-stack 2.1.1
#   ./build_mpas.sh -m hera -s 1.9.2    name the machine and stack
#   ./build_mpas.sh -i -j 16            incremental (keep build dir), 16 make jobs
#   ./build_mpas.sh -B /path/build2     build in another directory
#   ./build_mpas.sh -b [-t 03:00:00]    submit as a batch job (make -j 32 there)
#
# Options: -m machine  -s stack  -S source-dir  -B build-dir  -j make-jobs
#          -i incremental  -b submit  -t walltime  -h help
# Machines and their queue/module settings: mpas_machines.sh
# Paths: -S/-B, else MPAS_SRC / MPAS_BUILD, else the per-machine defaults.
# Logs: ecbuild.log and make.log in the build dir (plus mpas_build.<jobid>.log with -b).

set -o pipefail

usage() { sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# Directory holding setenv_mpas.sh. Self-submitted jobs get MPAS_SCRIPTS
# exported; a plain `sbatch build_mpas.sh` runs a spooled copy, so look up
# the submitted path, then the submit directory.
find_scripts() {
  local d cmd
  d=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
  [[ -f ${d}/setenv_mpas.sh ]] && { echo "${d}"; return; }
  if [[ -n ${SLURM_JOB_ID:-} ]]; then
    cmd=$(scontrol show job "${SLURM_JOB_ID}" 2>/dev/null | sed -n 's/^ *Command=\([^ ]*\).*/\1/p')
    [[ -f ${cmd} ]] && { dirname "$(readlink -f "${cmd}")"; return; }
    echo "${SLURM_SUBMIT_DIR}"; return
  fi
  echo "${PWD}"
}
MPAS_SCRIPTS=${MPAS_SCRIPTS:-$(find_scripts)}
[[ -f ${MPAS_SCRIPTS}/setenv_mpas.sh ]] || {
  echo "build_mpas.sh: setenv_mpas.sh not found in ${MPAS_SCRIPTS} (set MPAS_SCRIPTS)" >&2; exit 1; }

machine=${MPAS_MACHINE:-}
stack=${MPAS_STACK:-2.1.1}
clean=true
submit=false
jobs_set=false
walltime=02:00:00
if [[ -n ${SLURM_JOB_ID:-} ]]; then jobs=32; else jobs=8; fi  # be gentle on login nodes
while getopts ":m:s:S:B:j:ibt:h" opt; do
  case ${opt} in
    m) machine=${OPTARG} ;;
    s) stack=${OPTARG} ;;
    S) export MPAS_SRC=$(readlink -m "${OPTARG}") ;;
    B) export MPAS_BUILD=$(readlink -m "${OPTARG}") ;;
    j) jobs=${OPTARG}; jobs_set=true ;;
    i) clean=false ;;
    b) submit=true ;;
    t) walltime=${OPTARG} ;;
    h) usage 0 ;;
    *) usage 1 ;;
  esac
done

# --- submit mode: hand the same build to a compute node ---
if ${submit} && [[ -z ${SLURM_JOB_ID:-} ]]; then
  source "${MPAS_SCRIPTS}/mpas_machines.sh"
  MPAS_MACHINE=${machine:-$(mpas_detect_machine)}
  MPAS_STACK=${stack}
  mpas_machine_config "${MPAS_MACHINE}" "${MPAS_STACK}" || exit 1
  args=(-m "${MPAS_MACHINE}" -s "${MPAS_STACK}")
  [[ -n ${MPAS_SRC:-} ]] && args+=(-S "${MPAS_SRC}")
  [[ -n ${MPAS_BUILD:-} ]] && args+=(-B "${MPAS_BUILD}")
  ${clean} || args+=(-i)
  ${jobs_set} && args+=(-j "${jobs}")  # otherwise the job picks 32
  mpas_submit mpas_build "${walltime}" "$(readlink -f "$0")" "${args[@]}"
  exit $?
fi

setenv_args=(-s "${stack}")
[[ -n ${machine} ]] && setenv_args+=(-m "${machine}")
source "${MPAS_SCRIPTS}/setenv_mpas.sh" "${setenv_args[@]}" || exit 1

[[ -f ${MPAS_SRC}/CMakeLists.txt ]] || { echo "build_mpas.sh: no CMakeLists.txt in MPAS_SRC=${MPAS_SRC}" >&2; exit 1; }
case $(readlink -m "${MPAS_BUILD}") in
  /|"${HOME}"|$(readlink -m "${MPAS_SRC}")|"")
    echo "build_mpas.sh: refusing to use MPAS_BUILD=${MPAS_BUILD}" >&2; exit 1 ;;
esac

start=$(date +%s)
echo "=== build_mpas.sh  $(date)  host=$(hostname)  machine=${MPAS_MACHINE}  stack=${MPAS_STACK}  make -j ${jobs}"
echo "    src=${MPAS_SRC}"
echo "    build=${MPAS_BUILD}  ($(${clean} && echo fresh || echo incremental))"

if ${clean}; then
  rm -rf "${MPAS_BUILD}"   # an old CMakeCache.txt keeps stale (e.g. conda) paths
fi
mkdir -p "${MPAS_BUILD}" && cd "${MPAS_BUILD}" || exit 1

if [[ ! -f CMakeCache.txt ]]; then
  echo "=== ecbuild"
  ecbuild "${MPAS_SRC}" 2>&1 | tee ecbuild.log || { echo "ecbuild FAILED, see ${MPAS_BUILD}/ecbuild.log" >&2; exit 1; }
fi

echo "=== make -j ${jobs}"
make -j "${jobs}" 2>&1 | tee make.log
rc=$?

mins=$(( ($(date +%s) - start) / 60 ))
if [[ ${rc} -eq 0 ]]; then
  echo "=== build OK in ${mins} min. Run the tests with:  ${MPAS_SCRIPTS}/ctest_mpas.sh -m ${MPAS_MACHINE} -s ${MPAS_STACK} -B ${MPAS_BUILD}"
else
  echo "=== build FAILED (rc=${rc}) after ${mins} min. First errors:" >&2
  grep -n -m 10 -E 'error[: ]|undefined reference' make.log >&2
  echo "    full log: ${MPAS_BUILD}/make.log" >&2
fi
exit "${rc}"
