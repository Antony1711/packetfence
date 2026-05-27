#!/bin/bash
# Bake a "golden" Vagrant box for a PacketFence VM by booting the upstream
# Packer box, fully provisioning it via addons/vagrant/site.yml (scoped to
# the PF VM via -l), and running the Venom configurator scenario once. The
# resulting .box is consumed by all downstream test jobs in the same
# pipeline, so they skip site.yml and the configurator wizard.
#
# Required env: BAKE_ARCH (el8|deb12), PF_VM_NAME (pfel8dev|pfdeb12dev),
#               CI_PIPELINE_ID.
# Optional env: GOLDEN_BOX_DIR, VAGRANT_PF_DOTFILE_PATH, RESULT_DIR.

set -o nounset -o pipefail -o errexit

SCRIPT_DIR=$(readlink -e "$(dirname "${BASH_SOURCE[0]}")")
PF_SRC_DIR=$(echo "${SCRIPT_DIR}" | grep -oP '.*?(?=\/ci\/)')

source "${PF_SRC_DIR}/ci/lib/common/functions.sh"

configure_and_check() {
    BAKE_ARCH=${BAKE_ARCH:?BAKE_ARCH must be set (e.g. el8, deb12)}
    PF_VM_NAME=${PF_VM_NAME:?PF_VM_NAME must be set (e.g. pfel8dev, pfdeb12dev)}
    CI_PIPELINE_ID=${CI_PIPELINE_ID:?CI_PIPELINE_ID must be set}

    GOLDEN_BOX_DIR=${GOLDEN_BOX_DIR:-/var/local/gitlab-runner/golden_images/${CI_PIPELINE_ID}}
    GOLDEN_BOX_FILE="${GOLDEN_BOX_DIR}/pf${BAKE_ARCH}golden.box"

    VAGRANT_PF_DOTFILE_PATH=${VAGRANT_PF_DOTFILE_PATH:-/var/local/gitlab-runner/vagrant/bake-${CI_PIPELINE_ID}-${BAKE_ARCH}}
    VAGRANT_DIR="${PF_SRC_DIR}/addons/vagrant"
    VENOM_DIR="${PF_SRC_DIR}/t/venom"

    declare -p BAKE_ARCH PF_VM_NAME CI_PIPELINE_ID
    declare -p GOLDEN_BOX_DIR GOLDEN_BOX_FILE VAGRANT_PF_DOTFILE_PATH
    declare -p VAGRANT_DIR VENOM_DIR

    mkdir -p "${GOLDEN_BOX_DIR}"
}

# Delegate to test-wrapper.sh to boot the upstream box (Vagrant runs site.yml
# via its Ansible provisioner) and execute the configurator Venom scenario.
# Setting INT_TEST_VM_NAMES="" keeps the run PF-only.
provision_and_run_configurator() {
    log_section "Provision PF VM and run configurator scenario"
    # SITE_PROVISION_PLAYBOOK is intentionally unset: the default site.yml
    # invocation (scoped via Vagrant's -l to the PF VM) runs site_pf.yml
    # plays plus utils.yml; site_others.yml plays no-op for the PF VM since
    # no matching hosts are in scope.
    ( cd "${VENOM_DIR}" \
        && PF_VM_NAMES="${PF_VM_NAME}" \
           INT_TEST_VM_NAMES="" \
           SCENARIOS_TO_RUN="configurator" \
           VAGRANT_PF_DOTFILE_PATH="${VAGRANT_PF_DOTFILE_PATH}" \
           ./test-wrapper.sh run )
}

halt_pf_vm() {
    log_section "Halt PF VM ${PF_VM_NAME}"
    ( cd "${VAGRANT_DIR}" \
        && VAGRANT_DOTFILE_PATH="${VAGRANT_PF_DOTFILE_PATH}" \
           vagrant halt "${PF_VM_NAME}" )
}

# vagrant package needs the VM stopped; it produces a single .box file
# containing the libvirt qcow2 + Vagrantfile metadata. The .box lives on the
# shared runner FS at GOLDEN_BOX_DIR — test jobs running on the same runner
# pool (tags: test-shell-v7) read it directly; cleanup_golden_images purges
# it at the end of the pipeline. The file is too large (~5-10 GB) to upload
# as a GitLab artifact.
package_golden_box() {
    log_section "Package golden box to ${GOLDEN_BOX_FILE}"
    rm -f "${GOLDEN_BOX_FILE}"
    ( cd "${VAGRANT_DIR}" \
        && VAGRANT_DOTFILE_PATH="${VAGRANT_PF_DOTFILE_PATH}" \
           vagrant package --output "${GOLDEN_BOX_FILE}" "${PF_VM_NAME}" )
    ls -lh "${GOLDEN_BOX_FILE}"
}

destroy_pf_vm() {
    log_section "Destroy PF VM and remove dotfile path"
    ( cd "${VAGRANT_DIR}" \
        && VAGRANT_DOTFILE_PATH="${VAGRANT_PF_DOTFILE_PATH}" \
           vagrant destroy -f "${PF_VM_NAME}" || true )
    if [ -d "${VAGRANT_PF_DOTFILE_PATH}" ]; then
        rm -rf "${VAGRANT_PF_DOTFILE_PATH}"
    fi
}

run() {
    provision_and_run_configurator
    halt_pf_vm
    package_golden_box
    destroy_pf_vm
}

# Best-effort cleanup used as after_script when the main run aborts mid-flight.
teardown() {
    log_section "Teardown (best-effort cleanup)"
    destroy_pf_vm
}

configure_and_check

case ${1:-run} in
    run)      run ;;
    teardown) teardown ;;
    *)        die "Unknown argument: $1 (expected: run|teardown)" ;;
esac
