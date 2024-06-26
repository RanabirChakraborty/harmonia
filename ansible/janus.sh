#!/bin/bash
set -eo pipefail
# workaround for Ansible 2.14 issue https://github.com/NixOS/nixpkgs/issues/223151#
export LANG=C.UTF-8 ansible

source "$(dirname $(realpath ${0}))/common.sh"

readonly PLAYS_DIR=${PLAYS_DIR:-"${WORKDIR}/playbooks"}

checkWorkdirExistsAndSetAsDefault

ansible-galaxy collection install community.fqcn_migration

if [ "${PLAYBOOK}" == 'playbooks/janus.yml' ]; then
  echo "${PLAYS_DIR}/${PLAYBOOK}"
  ansible-playbook "${PLAYS_DIR}/${PLAYBOOK}"
else
  if [ -e "${PLAYBOOK}" ]; then
    echo "Using provided playbook: ${PLAYBOOK}."
    ansible-playbook "${WORKDIR}/${PLAYBOOK}"
  else
    echo "Provided ${PLAYBOOK} is not a path, computing default playbook name instead"
    echo "${PLAYS_DIR}/${PROJECT_NAME}.yml"
    ansible-playbook "${PLAYS_DIR}/${PROJECT_NAME}.yml"
  fi
fi
