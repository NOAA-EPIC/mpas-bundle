# MPAS-JEDI build and test scripts

Scripts to set up the environment, build MPAS-JEDI and run its ctests on
NOAA RDHPCS machines with spack-stack.

| file | what it does | how to use it |
|---|---|---|
| `setenv_mpas.sh` | removes conda, loads the spack-stack modules, checks the result | `source` it |
| `build_mpas.sh` | `ecbuild` + `make`, on the login node or as a batch job | run it |
| `ctest_mpas.sh` | runs ctest on one whole compute node | run it |
| `mpas_machines.sh` | per-machine settings (modules, Slurm options, default paths) | edit it |

Keep all four files in the same directory.

## Quick start (Ursa)

```bash
chmod +x build_mpas.sh ctest_mpas.sh

./build_mpas.sh                 # fresh build on the login node, spack-stack 2.1.1
./ctest_mpas.sh                 # submits all tests to one whole node
squeue -u $USER                 # watch the job
less mpas_ctest.<jobid>.log     # job log, in the directory you ran from
```

Default paths on Ursa:

- source: `/scratch4/NAGAPE/epic/$USER/mpas-jedi/mpas-bundle`
- build: `/scratch4/NAGAPE/epic/$USER/mpas-jedi/build`

## Common options

All three scripts accept these:

| option | meaning | default |
|---|---|---|
| `-m machine` | `ursa`, `hera`, `orion`, `hercules`, `gaeac5`, `gaeac6` | detected from the hostname |
| `-s stack` | spack-stack version: `2.1.1` or `1.9.2` | `2.1.1` |
| `-S dir` | mpas-bundle source directory | per-machine default |
| `-B dir` | build directory | per-machine default |

Relative paths are turned into absolute ones, so they still work inside batch
jobs. Paths can also come from the environment variables `MPAS_SRC` and
`MPAS_BUILD`. The order of precedence is option, then environment variable,
then machine default.

## setenv_mpas.sh: the environment

```bash
source setenv_mpas.sh                         # this machine, spack-stack 2.1.1
source setenv_mpas.sh -s 1.9.2                # older stack
source setenv_mpas.sh -m ursa -B ~/build2     # explicit machine and build dir
```

What it does:

1. Deactivates conda and removes `anaconda3`/`miniconda` from `PATH`,
   `LD_LIBRARY_PATH`, `LIBRARY_PATH`, `CPATH`, `PKG_CONFIG_PATH`,
   `CMAKE_PREFIX_PATH` and `PYTHONPATH`. It also unsets `MKLROOT`. Conda's
   MKL caused the `undefined reference to mkl_graph_...` link error.
2. Runs `module purge`, then `module use` and `module load` for that machine
   and stack. If a load fails, it stops and suggests `module spider`.
3. Warns if conda paths are still present, or if `MKLROOT`, `ecbuild`,
   `mpiexec` or `python3` is missing.

It must be **sourced**. Running it as `./setenv_mpas.sh` refuses, because
loaded modules would not stay in your shell.

The modules each stack loads on Ursa:

| stack | modules |
|---|---|
| 2.1.1 | `stack-intel-oneapi-compilers/2025.3.1` `stack-intel-oneapi-mpi/2021.17` `jedi-mpas-env` |
| 1.9.2 | `stack-oneapi/2024.2.1` `stack-intel-oneapi-mpi/2021.13` `jedi-mpas-env` |

## build_mpas.sh: build

```bash
./build_mpas.sh                        # fresh build here (make -j 8)
./build_mpas.sh -i                     # incremental: keep the build dir, re-run make
./build_mpas.sh -j 16                  # more make jobs
./build_mpas.sh -B /path/build-2.1.1   # build in another directory
./build_mpas.sh -s 1.9.2 -B /path/build-1.9.2
./build_mpas.sh -b                     # submit to a whole compute node (make -j 32)
./build_mpas.sh -b -t 03:00:00         # with a 3-hour limit (default 2 h)
```

| option | meaning |
|---|---|
| `-i` | incremental build; without it the build directory is **deleted first** |
| `-j N` | make jobs (8 on a login node, 32 in a batch job) |
| `-b` | submit as a batch job instead of building here |
| `-t HH:MM:SS` | walltime for `-b` |
| `-h` | help |

- A fresh build is the default because an old `CMakeCache.txt` keeps stale
  paths, which is how the conda MKL got into the link.
- The script refuses to delete a build directory set to `/`, your home
  directory or the source tree.
- Logs go to `ecbuild.log` and `make.log` in the build directory, and with
  `-b` also to `mpas_build.<jobid>.log` where you ran it.
- If the build fails, the script prints the first errors and the log path.

## ctest_mpas.sh: run the tests

From a login node the script **submits itself** to one whole node
(`--exclusive`). Inside a job, including an `salloc` session, it runs the
tests directly.

```bash
./ctest_mpas.sh                                # all tests
./ctest_mpas.sh -R mpasjedi -j 4               # only MPAS-JEDI tests
./ctest_mpas.sh -B /path/build-1.9.2 -s 1.9.2  # tests of another build
./ctest_mpas.sh -t 01:00:00 -I 471,2561 -j 8   # resume from test #471, 1-hour limit
./ctest_mpas.sh --rerun-failed -j 4            # only what failed last time
```

Put the script options (`-m`, `-s`, `-B`, `-t`) **first**. Everything after
them is passed to ctest; use `--` to separate them explicitly. With no ctest
arguments it runs `-j 8`. The default walltime is 4 hours.

Output files:

| file | where |
|---|---|
| `mpas_ctest.<jobid>.log` | the directory you ran from (the job's stdout) |
| `ctest_<jobid>.log` | build directory, the full ctest output |
| `ctest_<jobid>.failed` | build directory, names of failed tests (only if any failed) |

At the end the script prints the pass/fail summary and the command to rerun
only the failures.

Settings inside the job:

- `ulimit -s unlimited`
- `OMP_NUM_THREADS=1`, unless you set it
- per-test timeout of 1800 s; change it with `MPAS_CTEST_TIMEOUT=3600 ./ctest_mpas.sh`

### Why a whole node

A plain `salloc -N 32` on Ursa gave **1 CPU and about 2 GB per node**. ctest
runs on the first node only, ran out of memory, and the out-of-memory killer
stopped it with a bare `Killed`. The scripts always request
`-N 1 --exclusive`, and `ctest_mpas.sh` warns if it finds fewer than 8 CPUs.

For an interactive session, use:
```bash
salloc -A epic -p u1-compute -q batch -N 1 --exclusive -t 02:00:00
./ctest_mpas.sh -R mpasjedi -j 4      # runs directly inside the allocation
```

## Batch settings

| machine | Slurm options |
|---|---|
| ursa | `--qos=batch --partition=u1-compute` |
| hera | `--qos=batch` |
| orion, hercules | `--qos=batch --partition=<machine>` |
| gaeac5, gaeac6 | `--qos=normal --clusters=c5`/`c6` `--partition=batch` |

These come from ufs-weather-model `tests/rt.sh`.

- The account is `epic`; change it with `MPAS_ACCOUNT=myacct ./ctest_mpas.sh`.
- The QOS can be changed with `MPAS_QOS=debug`. On RDHPCS that QOS is usually limited to about 30 minutes, so pair it with `-t 00:30:00`.

## Adding a machine

Only **Ursa** has spack-stack module paths so far. On the other machines the
scripts stop with `no spack-stack <stack> modules configured for <machine>`.
To add one, edit `mpas_machines.sh`:

1. In `mpas_machine_config`, set `MPAS_CORE` (the spack-stack
   `modules/Core` directory) and `MPAS_MODULES` (the load order) for each
   stack. Copy the `ursa` block.
2. Optionally set `MPAS_WORK`, the directory that holds `mpas-bundle/` and
   `build/`. Without it you must give `-S`/`-B` or `MPAS_SRC`/`MPAS_BUILD`.
3. If the hostname isn't recognised, add it to `mpas_detect_machine`.
   Include the compute-node names too, because the job runs there.

To find the module names on a new machine:
```bash
module use <spack-stack>/envs/<env>/modules/Core
module avail stack-                      # compiler meta-module
module load stack-<compiler>/<ver>
module avail stack-                      # MPI meta-module appears now
module spider jedi-mpas-env              # what it needs loaded first
```

wcoss2 and derecho use PBS, which these scripts don't support yet.

## Troubleshooting

| symptom | cause and fix |
|---|---|
| `undefined reference to mkl_graph_...` in `anaconda3/lib` | conda's MKL got into the link. Do a fresh build (no `-i`); `setenv_mpas.sh` strips conda. To stop conda activating at login: `conda config --set auto_activate_base false` |
| `module(s) are unknown: "stack-oneapi"` | spack-stack 2.x renamed it `stack-intel-oneapi-compilers`. Use `-s 2.1.1`, which loads the right names |
| `jedi-mpas-env ... exist but cannot be loaded` | load the compiler and MPI meta-modules first; `setenv_mpas.sh` does this in order |
| ctest prints `Killed` | not enough CPUs or memory (see "Why a whole node"). Use `ctest_mpas.sh`, or `salloc --exclusive` |
| job ends with `TIMEOUT` | raise `-t`, resume with `-I <next>,<last>`, or run fewer tests with `-R` |
| `could not detect the machine` | pass `-m`, or add the hostname to `mpas_detect_machine` |
| `-Wvla-cxx-extension` warnings | harmless warnings from the newer `icpx` |
