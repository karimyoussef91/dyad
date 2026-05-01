#!/bin/bash

module load python/3.9.12
module load openmpi/4.1.2

# Configurations
export DLIO_WORKLOAD=dyad_unet3d #dyad_unet3d_large # unet3d_base dyad_unet3d dyad_unet3d_small resnet50_base dyad_resnet50 unet3d_base_large mummi_base dyad_mummi
export NUM_NODES=8
export PPN=8
export QUEUE=pbatch
export TIME=$((30))
export BROKERS_PER_NODE=1
export GENERATE_DATA="0"

export DYAD_INSTALL_PREFIX=/usr/workspace/youssef2/dyad_corona/install
export DYAD_KVS_NAMESPACE=dyad
export DYAD_DTL_MODE=UCX
export DYAD_PATH="/l/ssd/youssef2/dyad_data"
#export DYAD_PATH=/dev/shm/youssef2/dyad
export GITHUB_WORKSPACE=/usr/workspace/youssef2/dyad_corona
export SPACK_DIR=/usr/workspace/youssef2/spack
export SPACK_ENV=/usr/workspace/youssef2/dyad_corona/env/spack
export PYTHON_ENV_BASE=/usr/workspace/youssef2/dlio_corona_ompi
export PYTHON_ENV=/tmp/dlio_corona_ompi
export DLIO_DATA_DIR=/p/lustre3/youssef2/dlio_data/unet3d_dyad_320 #  dyad_resnet50 dyad_unet3d_basic
#export DLIO_DATA_DIR=/p/lustre2/youssef2/dyad/dlio_benchmark/dyad_unet3d_basic #  dyad_resnet50

# DLIO Profiler Configurations
export DFTRACER_ENABLE=0
export DFTRACER_INC_METADATA=1
export DFTRACER_DATA_DIR=${DLIO_DATA_DIR}:${DYAD_PATH}
export DFTRACER_LOG_FILE=/usr/workspace/youssef2/dyad_corona/tests/integration/dlio_benchmark/profiler/dyad

export DYAD_LOG_DIR=/usr/workspace/youssef2/dyad_corona/tests/integration/dlio_benchmark/logs
export DFTRACER_LOG_LEVEL=ERROR
#export GOTCHA_DEBUG=3

export DFTRACER_BIND_SIGNALS=0
export MV2_BCAST_HWLOC_TOPOLOGY=0
export HDF5_USE_FILE_LOCKING=0

mkdir -m 775 -p ${DYAD_PATH}
mkdir -p ${DFTRACER_LOG_FILE}

# Stage the Python environment to node-local /tmp to avoid loading issues from the shared filesystem.

if [ ! -d "${PYTHON_ENV_BASE}" ]; then
    echo "Base Python environment does not exist: ${PYTHON_ENV_BASE}" >&2
    exit 1
fi

export PYTHON_ENV_TAR=/tmp/${USER}/$(basename ${PYTHON_ENV_BASE}).tar

if [ -n "${FLUX_URI:-}" ]; then
    echo "Running within a Flux allocation; staging Python environment to node-local storage." >&2
    flux exec -r all bash -c "
        mkdir -p /tmp/${USER}
        if [ ! -f '${PYTHON_ENV_TAR}' ]; then
            tar -C '$(dirname ${PYTHON_ENV_BASE})' -cf '${PYTHON_ENV_TAR}' '$(basename ${PYTHON_ENV_BASE})'
        fi
        rm -rf '${PYTHON_ENV}'
        tar -C '$(dirname ${PYTHON_ENV})' -xf '${PYTHON_ENV_TAR}'
    "
else
    echo "Not running within a Flux allocation; skipping staging of Python environment to node-local storage." >&2
    bash -c "
        mkdir -p /tmp/${USER}
        if [ ! -f '${PYTHON_ENV_TAR}' ]; then
            tar -C '$(dirname ${PYTHON_ENV_BASE})' -cf '${PYTHON_ENV_TAR}' '$(basename ${PYTHON_ENV_BASE})'
        fi
        rm -rf '${PYTHON_ENV}'
        tar -C '$(dirname ${PYTHON_ENV})' -xf '${PYTHON_ENV_TAR}'
    "
fi

# Activate Environments
# . ${SPACK_DIR}/share/spack/setup-env.sh
# spack env activate -p ${SPACK_ENV}
source ${PYTHON_ENV}/bin/activate 

# Derived Configurations
export DYAD_DLIO_RUN_LOG=dyad_${DLIO_WORKLOAD}_${NUM_NODES}_${PPN}_${BROKERS_PER_NODE}.log
export CONFIG_ARG="--config-dir=${GITHUB_WORKSPACE}/tests/integration/dlio_benchmark/configs"
#export CONFIG_ARG=""

# Derived PATHS
export PATH=${PATH}:${DYAD_INSTALL_PREFIX}/bin:${DYAD_INSTALL_PREFIX}/sbin
export LD_LIBRARY_PATH=/usr/lib64:${DYAD_INSTALL_PREFIX}/lib:${LD_LIBRARY_PATH}
export PYTHONPATH=${GITHUB_WORKSPACE}/tests/integration/dlio_benchmark:${GITHUB_WORKSPACE}/pydyad:$PYTHONPATH

unset LUA_PATH
unset LUA_CPATH
