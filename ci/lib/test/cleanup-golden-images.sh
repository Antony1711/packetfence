#!/bin/bash
# Purge the pipeline-scoped golden image directory written by
# ci/lib/bake/bake-vagrant-img.sh. Run as a `when: always` job at the end
# of the pipeline so .box files don't accumulate on shared runner disks.

set -o nounset -o pipefail

SCRIPT_DIR=$(readlink -e "$(dirname "${BASH_SOURCE[0]}")")
PF_SRC_DIR=$(echo "${SCRIPT_DIR}" | grep -oP '.*?(?=\/ci\/)')

source "${PF_SRC_DIR}/ci/lib/common/functions.sh"

configure_and_check() {
    CI_PIPELINE_ID=${CI_PIPELINE_ID:?CI_PIPELINE_ID must be set}
    GOLDEN_BOX_DIR=${GOLDEN_BOX_DIR:-/var/local/gitlab-runner/golden_images/${CI_PIPELINE_ID}}
    declare -p CI_PIPELINE_ID GOLDEN_BOX_DIR
}

cleanup() {
    log_section "Cleanup golden image dir ${GOLDEN_BOX_DIR}"
    if [ -d "${GOLDEN_BOX_DIR}" ]; then
        rm -rf "${GOLDEN_BOX_DIR}"
        echo "Removed ${GOLDEN_BOX_DIR}"
    else
        echo "Nothing to remove: ${GOLDEN_BOX_DIR} does not exist"
    fi
}

configure_and_check
cleanup
