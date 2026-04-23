#!/usr/bin/env bash
set -euo pipefail

# 统一代理环境变量，避免不同工具只识别部分名字
export HTTP_PROXY="${HTTP_PROXY:-${http_proxy:-}}"
export HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy:-}}"
export ALL_PROXY="${ALL_PROXY:-${all_proxy:-}}"
export NO_PROXY="${NO_PROXY:-${no_proxy:-}}"

export http_proxy="${http_proxy:-${HTTP_PROXY:-}}"
export https_proxy="${https_proxy:-${HTTPS_PROXY:-}}"
export all_proxy="${all_proxy:-${ALL_PROXY:-}}"
export no_proxy="${no_proxy:-${NO_PROXY:-}}"

WORKDIR="${WORKDIR:-/work}"
TARGET="${1:-${MINIRV32IMA_TARGET:-everything}}"
FIX_WGET="${MINIRV32IMA_FIX_WGET:-1}"

cd "${WORKDIR}"

echo "[entrypoint] workdir: ${WORKDIR}"
echo "[entrypoint] target : ${TARGET}"

if [[ -n "${HTTP_PROXY}" ]]; then
    echo "[entrypoint] HTTP proxy detected"
fi

patch_wget_passive_ftp() {
    if [[ "${FIX_WGET}" != "1" ]]; then
        return 0
    fi

    if [[ -d buildroot ]]; then
        mapfile -t files < <(grep -RIl -- '--passive-ftp' buildroot 2>/dev/null || true)
        if (( ${#files[@]} > 0 )); then
            echo "[entrypoint] removing unsupported wget option: --passive-ftp"
            for f in "${files[@]}"; do
                sed -i 's/--passive-ftp//g' "$f"
            done
        fi
    fi
}

print_help() {
    cat <<'EOF'
Available targets:
  everything
  toolchain
  testdlimage
  testbare
  shell
EOF
}

case "${TARGET}" in
    everything|toolchain|testdlimage|testbare)
        patch_wget_passive_ftp
        exec make "${TARGET}"
        ;;
    shell|bash)
        patch_wget_passive_ftp
        exec bash
        ;;
    help|-h|--help)
        print_help
        exit 0
        ;;
    *)
        patch_wget_passive_ftp
        exec "$@"
        ;;
esac
