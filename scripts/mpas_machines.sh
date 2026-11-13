# Per-machine settings for the MPAS-JEDI scripts. Sourced by setenv_mpas.sh.
#
# To add or update a machine, edit only this file:
#   * mpas_detect_machine: hostname patterns (login AND compute nodes)
#   * mpas_machine_config: spack-stack module path + module list per stack,
#     Slurm options, default work directory
#
# Only Ursa's spack-stack paths are known so far. The other machines have
# their queue settings (taken from ufs-weather-model tests/rt.sh) but no
# module paths yet: fill in MPAS_CORE / MPAS_MODULES for them.

MPAS_MACHINES=(ursa hera orion hercules gaeac5 gaeac6)

mpas_detect_machine() {
  case $(hostname -f 2>/dev/null || hostname) in
    ufe0[1-9]*|uecflow0*|u[0-9][0-9]c[0-9][0-9]*)       echo ursa ;;
    hfe0[1-9]*|hfe1[0-2]*|hecflow0*|h[0-9]*c[0-9]*)    echo hera ;;
    [Oo]rion-login-*|orion-[0-9]*)                     echo orion ;;
    [Hh]ercules-login-*|hercules-[0-9]*)               echo hercules ;;
    gaea5[0-9]*|c5n[0-9]*)                             echo gaeac5 ;;
    gaea6[0-9]*|c6n[0-9]*)                             echo gaeac6 ;;
    *)                                                 echo unknown ;;
  esac
}

# mpas_machine_config MACHINE STACK
# Sets: MPAS_CORE, MPAS_MODULES (array), MPAS_SBATCH (array), MPAS_WORK
mpas_machine_config() {
  local machine=$1 stack=$2
  MPAS_CORE='' MPAS_MODULES=() MPAS_SBATCH=() MPAS_WORK=''
  local account=${MPAS_ACCOUNT:-epic}

  case ${machine} in
    ursa)
      MPAS_SBATCH=(--account="${account}" --qos="${MPAS_QOS:-batch}" --partition=u1-compute)
      MPAS_WORK=/scratch4/NAGAPE/epic/${USER:-$(id -un)}/mpas-jedi
      case ${stack} in
        2.1.1)
          MPAS_CORE=/contrib/spack-stack/spack-stack-2.1.1/envs/ue-oneapi-2025.3.1/modules/Core
          MPAS_MODULES=(stack-intel-oneapi-compilers/2025.3.1 stack-intel-oneapi-mpi/2021.17 jedi-mpas-env) ;;
        1.9.2)
          MPAS_CORE=/contrib/spack-stack/spack-stack-1.9.2/envs/ue-oneapi-2024.2.1/install/modulefiles/Core
          MPAS_MODULES=(stack-oneapi/2024.2.1 stack-intel-oneapi-mpi/2021.13 jedi-mpas-env) ;;
      esac ;;

    hera)
      MPAS_SBATCH=(--account="${account}" --qos="${MPAS_QOS:-batch}")
      # TODO: MPAS_CORE / MPAS_MODULES for spack-stack on Hera
      ;;

    orion|hercules)
      MPAS_SBATCH=(--account="${account}" --qos="${MPAS_QOS:-batch}" --partition="${machine}")
      # TODO: MPAS_CORE / MPAS_MODULES for spack-stack on ${machine}
      ;;

    gaeac5|gaeac6)
      MPAS_SBATCH=(--account="${account}" --qos="${MPAS_QOS:-normal}"
                   --clusters="${machine#gaea}" --partition=batch)
      # TODO: MPAS_CORE / MPAS_MODULES for spack-stack on Gaea ${machine#gaea}
      ;;

    *)
      echo "mpas_machines.sh: unknown machine '${machine}' (known: ${MPAS_MACHINES[*]})" >&2
      return 1 ;;
  esac

  if [[ -z ${MPAS_CORE} || ${#MPAS_MODULES[@]} -eq 0 ]]; then
    echo "mpas_machines.sh: no spack-stack ${stack} modules configured for ${machine}." >&2
    echo "  Add MPAS_CORE and MPAS_MODULES for it in mpas_machine_config." >&2
    return 1
  fi
}

# mpas_submit JOBNAME WALLTIME SCRIPT [ARGS...]
# Submit SCRIPT on one whole node of the current machine (MPAS_SBATCH from
# mpas_machine_config). The job log goes to ./JOBNAME.<jobid>.log.
mpas_submit() {
  local name=$1 wall=$2 script=$3
  shift 3
  local opts=(--job-name="${name}" --nodes=1 --exclusive --time="${wall}"
              --output="${PWD}/${name}.%j.log"
              --export="ALL,MPAS_MACHINE=${MPAS_MACHINE},MPAS_STACK=${MPAS_STACK},MPAS_SCRIPTS=${MPAS_SCRIPTS}"
              "${MPAS_SBATCH[@]}")
  echo "sbatch ${opts[*]} ${script} $*"
  sbatch "${opts[@]}" "${script}" "$@"
}
