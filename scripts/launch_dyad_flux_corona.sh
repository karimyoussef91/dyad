#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL_PREFIX=${DYAD_INSTALL_PREFIX:-${ROOT_DIR}/install/corona}
DYAD_MODULE=${DYAD_MODULE_PATH:-${INSTALL_PREFIX}/lib/dyad.so}
DYAD_WRAPPER=${DYAD_WRAPPER_PATH:-${INSTALL_PREFIX}/lib/libdyad_wrapper.so}
QUEUE=${QUEUE:-pdebug}
TIME=${TIME:-30}
NODES=${NODES:-2}
BROKERS_PER_NODE=${BROKERS_PER_NODE:-1}
KVS_NAMESPACE=${DYAD_KVS_NAMESPACE:-dyad}
DYAD_DTL_MODE=${DYAD_DTL_MODE:-UCX}
DYAD_KEY_DEPTH=${DYAD_KEY_DEPTH:-2}
DYAD_KEY_BINS=${DYAD_KEY_BINS:-256}
DYAD_PATH=${DYAD_PATH:-/tmp/${USER}/dyad}
LOG_DIR=${LOG_DIR:-${ROOT_DIR}/logs/dyad_flux}
USER_COMMAND=()

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [-- command ...]

Options:
  -N, --nodes <count>      Number of nodes to allocate (default: ${NODES})
  -q, --queue <queue>      Flux queue/partition (default: ${QUEUE})
  -t, --time <minutes>     Allocation time in minutes (default: ${TIME})
  -p, --path <path>        DYAD-managed data path (default: ${DYAD_PATH})
  -k, --kvs <namespace>    DYAD KVS namespace (default: ${KVS_NAMESPACE})
  -l, --log-dir <path>     Flux log directory (default: ${LOG_DIR})
  -h, --help               Show this help message

Environment overrides:
  DYAD_INSTALL_PREFIX, DYAD_MODULE_PATH, DYAD_WRAPPER_PATH,
  DYAD_DTL_MODE, DYAD_KEY_DEPTH, DYAD_KEY_BINS, BROKERS_PER_NODE

If no command is provided, an interactive shell is started inside the Flux
allocation with DYAD already loaded.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -N|--nodes)
            NODES="$2"
            shift 2
            ;;
        -q|--queue)
            QUEUE="$2"
            shift 2
            ;;
        -t|--time)
            TIME="$2"
            shift 2
            ;;
        -p|--path)
            DYAD_PATH="$2"
            shift 2
            ;;
        -k|--kvs)
            KVS_NAMESPACE="$2"
            shift 2
            ;;
        -l|--log-dir)
            LOG_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            USER_COMMAND=("$@")
            break
            ;;
        *)
            USER_COMMAND=("$@")
            break
            ;;
    esac
done

for required in "${DYAD_MODULE}" "${DYAD_WRAPPER}"; do
    if [[ ! -f "${required}" ]]; then
        echo "Missing required DYAD runtime artifact: ${required}" >&2
        exit 1
    fi
done

mkdir -p "${LOG_DIR}"

USER_COMMAND_ESCAPED=""
if [[ ${#USER_COMMAND[@]} -gt 0 ]]; then
    printf -v USER_COMMAND_ESCAPED '%q ' "${USER_COMMAND[@]}"
fi

read -r -d '' INNER_SCRIPT <<EOF || true
set -euo pipefail

export PATH="${INSTALL_PREFIX}/bin:\${PATH}"
export LD_LIBRARY_PATH="${INSTALL_PREFIX}/lib:\${LD_LIBRARY_PATH:-}"
export DYAD_DTL_MODE="${DYAD_DTL_MODE}"
export DYAD_KVS_NAMESPACE="${KVS_NAMESPACE}"
export DYAD_KEY_DEPTH="${DYAD_KEY_DEPTH}"
export DYAD_KEY_BINS="${DYAD_KEY_BINS}"
export DYAD_PATH="${DYAD_PATH}"
export DYAD_LD_PRELOAD="${DYAD_WRAPPER}"

cleanup() {
    local loaded
    loaded=\$(flux exec -r all flux module list 2>/dev/null | grep -w dyad || true)
    if [[ -n "\${loaded}" ]]; then
        flux exec -r all flux module remove dyad >/dev/null 2>&1 || true
    fi
    if flux kvs namespace list 2>/dev/null | grep -Fqx "${KVS_NAMESPACE}"; then
        flux kvs namespace remove "${KVS_NAMESPACE}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

flux exec -r all rm -rf "${DYAD_PATH}"
flux exec -r all mkdir -p "${DYAD_PATH}"
flux exec -r all chmod 775 "${DYAD_PATH}"

if flux kvs namespace list 2>/dev/null | grep -Fqx "${KVS_NAMESPACE}"; then
    flux kvs namespace remove "${KVS_NAMESPACE}"
fi
flux kvs namespace create "${KVS_NAMESPACE}"

loaded=\$(flux exec -r all flux module list 2>/dev/null | grep -w dyad || true)
if [[ -n "\${loaded}" ]]; then
    flux exec -r all flux module remove dyad || true
fi
flux exec -r all flux module load "${DYAD_MODULE}" "${DYAD_PATH}"

echo "DYAD is ready inside the Flux allocation."
echo "  install prefix : ${INSTALL_PREFIX}"
echo "  module         : ${DYAD_MODULE}"
echo "  wrapper        : ${DYAD_WRAPPER}"
echo "  data path      : ${DYAD_PATH}"
echo "  kvs namespace  : ${KVS_NAMESPACE}"
echo ""
echo "Launch DYAD-enabled tasks with:"
echo "  flux run -N 1 -n 1 env LD_PRELOAD=${DYAD_WRAPPER} <application> [args ...]"
echo ""

if [[ -n "${USER_COMMAND_ESCAPED}" ]]; then
    eval "${USER_COMMAND_ESCAPED}"
else
    /bin/bash -l
fi
EOF

flux alloc \
    -q "${QUEUE}" \
    -t "${TIME}" \
    -N "${NODES}" \
    -o per-resource.count="${BROKERS_PER_NODE}" \
    --exclusive \
    --broker-opts=--setattr=log-filename="${LOG_DIR}/flux.log" \
    bash -lc "${INNER_SCRIPT}"
