#!/bin/bash
#
# Run the MPAS-JEDI ctests on one whole node. From a login node this
# submits itself with sbatch; inside a job (sbatch or salloc) it runs.
#
#   ./ctest_mpas.sh                                 all tests, auto-detected machine
#   ./ctest_mpas.sh -m ursa -s 1.9.2                name the machine and stack
#   ./ctest_mpas.sh -B /path/build2 -R mpasjedi     tests of another build dir
#   ./ctest_mpas.sh -R mpasjedi -j 4                only MPAS-JEDI tests
#   ./ctest_mpas.sh -t 01:00:00 -I 471,2561 -j 8    resume from test 471, 1 h limit
#   ./ctest_mpas.sh --rerun-failed -j 4             only last run's failures
#
# Script options (must come first): -m machine  -s stack  -B build-dir
#                                   -t walltime (default 04:00:00)
# Everything after them, or after "--", is passed to ctest (default: -j 8).
# Output: mpas_ctest.<jobid>.log where you ran this, plus ctest_<jobid>.log and
# ctest_<jobid>.failed in the build dir. MPAS_CTEST_TIMEOUT = per-test timeout
# in seconds (default 1800).

set -o pipefail

find_scripts() {  # see build_mpas.sh
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
  echo "ctest_mpas.sh: setenv_mpas.sh not found in ${MPAS_SCRIPTS} (set MPAS_SCRIPTS)" >&2; exit 1; }

machine=${MPAS_MACHINE:-}
stack=${MPAS_STACK:-2.1.1}
walltime=04:00:00
while [[ $# -gt 0 ]]; do
  case $1 in
    -m) machine=$2; shift 2 ;;
    -s) stack=$2; shift 2 ;;
    -t) walltime=$2; shift 2 ;;
    -B) export MPAS_BUILD; MPAS_BUILD=$(readlink -m "$2"); shift 2 ;;
    -h|--help) sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --) shift; break ;;
    *) break ;;   # first ctest argument
  esac
done
[[ $# -eq 0 ]] && set -- -j 8

# --- not in a job yet: submit this script to a whole node ---
if [[ -z ${SLURM_JOB_ID:-} ]]; then
  source "${MPAS_SCRIPTS}/mpas_machines.sh"
  MPAS_MACHINE=${machine:-$(mpas_detect_machine)}
  MPAS_STACK=${stack}
  mpas_machine_config "${MPAS_MACHINE}" "${MPAS_STACK}" || exit 1
  mpas_submit mpas_ctest "${walltime}" "$(readlink -f "$0")" \
    -m "${MPAS_MACHINE}" -s "${MPAS_STACK}" ${MPAS_BUILD:+-B "${MPAS_BUILD}"} -- "$@"
  exit $?
fi

# --- in a job: run ---
ncpu=$(nproc)
if [[ ${ncpu} -lt 8 ]]; then
  echo "WARNING: only ${ncpu} CPU(s) in this job; heavy tests will run out of memory." >&2
  echo "         Run from a login node (it submits with --exclusive) or use salloc --exclusive." >&2
fi

setenv_args=(-s "${stack}")
[[ -n ${machine} ]] && setenv_args+=(-m "${machine}")
source "${MPAS_SCRIPTS}/setenv_mpas.sh" "${setenv_args[@]}" || exit 1

cd "${MPAS_BUILD}" 2>/dev/null && [[ -f CTestTestfile.cmake ]] || {
  echo "ctest_mpas.sh: no built tests in MPAS_BUILD=${MPAS_BUILD}; run build_mpas.sh first" >&2
  exit 1
}

ulimit -s unlimited 2>/dev/null || true   # JEDI/MPAS need a large stack
export OMP_NUM_THREADS=${OMP_NUM_THREADS:-1}

log=ctest_${SLURM_JOB_ID}.log
start=$(date +%s)
echo "=== ctest_mpas  $(date)  job=${SLURM_JOB_ID}  host=$(hostname)  cpus=${ncpu}"
echo "    machine=${MPAS_MACHINE}  stack=${MPAS_STACK}  build=${MPAS_BUILD}"
echo "    ctest --output-on-failure --timeout ${MPAS_CTEST_TIMEOUT:-1800} $*"

ctest --output-on-failure --timeout "${MPAS_CTEST_TIMEOUT:-1800}" "$@" 2>&1 | tee "${log}"
rc=$?

mins=$(( ($(date +%s) - start) / 60 ))
echo "=== finished in ${mins} min (ctest rc=${rc})"
grep -E 'tests passed|tests failed' "${log}" | tail -1
if [[ ${rc} -ne 0 && -s Testing/Temporary/LastTestsFailed.log ]]; then
  cut -d: -f2- Testing/Temporary/LastTestsFailed.log > "ctest_${SLURM_JOB_ID}.failed"
  echo "    failed tests ($(wc -l < "ctest_${SLURM_JOB_ID}.failed")): ${MPAS_BUILD}/ctest_${SLURM_JOB_ID}.failed"
  echo "    rerun only those:  ${MPAS_SCRIPTS}/ctest_mpas.sh -m ${MPAS_MACHINE} -s ${MPAS_STACK} -B ${MPAS_BUILD} --rerun-failed -j 4"
fi
echo "    full log: ${MPAS_BUILD}/${log}"
exit "${rc}"
