#!/bin/bash
set -euo pipefail
source "$(dirname $(realpath ${0}))/common.sh"

readonly PLATFORMS=("instance-rhel8" "instance-rhel9" "instance-rhel10")

readonly SCENARIO_NAME=${SCENARIO_NAME:-'--all'} # This will now mean "all scenarios"
readonly JBOSS_NETWORK_API_CREDENTIAL_FILE=${JBOSS_NETWORK_API_CREDENTIAL_FILE:-'/var/jenkins_home/jboss_network_api.yml'}
readonly SCENARIO_DRIVER_NAME=$(determineMoleculeDriverName)

checkWorkspaceIsDefinedAndExists
checkWorkdirExistsAndSetAsDefault
cleanMoleculeCache
installPythonRequirementsIfAny
configureAnsible
ansibleGalaxyCollectionFromAllRequirementsFile
molecule --version
installErisCollection
setRequiredEnvVars

BASE_CONFIG_PATH="${WORKDIR}/.config/molecule/config.yml"
if [ -f "${BASE_CONFIG_PATH}" ]; then
  echo "INFO: Found base config at ${BASE_CONFIG_PATH}, using it."
  export MOLECULE_BASE_CONFIG="${BASE_CONFIG_PATH}"
else
  echo "INFO: No base config found at ${BASE_CONFIG_PATH}, running without one."
  unset MOLECULE_BASE_CONFIG
fi

readonly EXTRA_ARGS="$(loadJBossNetworkAPISecrets)"
export EXTRA_ARGS

# shellcheck disable=SC2231
for scenario_dir in ${WORKDIR}/molecule/*
do
  if [ -d "${scenario_dir}" ]; then
    deployHeraDriver "${scenario_dir}"
  fi
done

printEnv
echo "Running Molecule tests sequentially per platform..."

FINAL_STATUS=0
set +e

for platform in "${PLATFORMS[@]}"; do
  echo "### Running Molecule tests for ${SCENARIO_NAME} on platform '${platform}' ###"

  PLATFORM_ARGS="--platform-name ${platform}"

  runMoleculeScenario "${SCENARIO_NAME}" "${SCENARIO_DRIVER_NAME}" "${PLATFORM_ARGS} ${EXTRA_ARGS}"

  status=$?
  if [ $status -ne 0 ]; then
    echo "ERROR: Molecule test failed for platform '${platform}' with status ${status}"
    FINAL_STATUS=$status
  else
    echo "INFO: Molecule test succeeded for platform '${platform}'"
  fi
done

set -e
echo "### Molecule Test Summary ###"
if [ "${FINAL_STATUS}" -eq 0 ]; then
  echo "### ALL PLATFORMS PASSED ###"
else
  echo "### ONE OR MORE PLATFORMS FAILED ###"
fi
echo "MOLECULE_EXIT_CODE: ${FINAL_STATUS}."
exit "${FINAL_STATUS}"
