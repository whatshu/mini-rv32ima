#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker/docker-compose.yml"
IMAGE_NAME="${MINIRV32IMA_DOCKER_IMAGE:-mini-rv32ima-dev:ubuntu}"
SERVICE_NAME="${MINIRV32IMA_DOCKER_SERVICE:-mini-rv32ima-dev}"
HASH_LABEL="org.mini-rv32ima.docker-context-hash"

FORCE_REBUILD=0
MODE="default"
CMD_STRING=""

usage() {
    cat <<EOF
Usage:
  ./build-docker.sh
      Build the Docker image only when needed, then run 'make everything' in /work.

  ./build-docker.sh --cmd
      Enter an interactive shell in /work.

  ./build-docker.sh --cmd 'make testdlimage'
      Run a command in /work.

Options:
  -r, --rebuild  Force rebuilding the Docker image.
  -h, --help     Show this help.
EOF
}

while (($#)); do
    case "$1" in
        --cmd)
            MODE="cmd"
            shift
            if (($#)); then
                CMD_STRING="$*"
            fi
            break
            ;;
        -r|--rebuild)
            FORCE_REBUILD=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

docker_context_hash() {
    (
        cd "${SCRIPT_DIR}"
        sha256sum docker/Dockerfile docker/entrypoint.sh | sha256sum | awk '{print $1}'
    )
}

image_hash() {
    docker image inspect \
        --format "{{ index .Config.Labels \"${HASH_LABEL}\" }}" \
        "${IMAGE_NAME}" 2>/dev/null || true
}

ensure_image() {
    local expected_hash
    local current_hash

    expected_hash="$(docker_context_hash)"
    current_hash="$(image_hash)"

    if [[ "${FORCE_REBUILD}" == "1" || "${current_hash}" != "${expected_hash}" ]]; then
        echo "[build-docker] building ${IMAGE_NAME}"
        docker build \
            --build-arg "MINIRV32IMA_DOCKER_CONTEXT_HASH=${expected_hash}" \
            -t "${IMAGE_NAME}" \
            -f "${SCRIPT_DIR}/docker/Dockerfile" \
            "${SCRIPT_DIR}"
    else
        echo "[build-docker] reusing ${IMAGE_NAME}"
    fi
}

ensure_image

if [[ "${MODE}" == "cmd" ]]; then
    if [[ -z "${CMD_STRING}" ]]; then
        exec docker compose -f "${COMPOSE_FILE}" run --rm "${SERVICE_NAME}" shell
    fi

    exec docker compose -f "${COMPOSE_FILE}" run --rm "${SERVICE_NAME}" bash -lc "${CMD_STRING}"
fi

exec docker compose -f "${COMPOSE_FILE}" run --rm "${SERVICE_NAME}"
