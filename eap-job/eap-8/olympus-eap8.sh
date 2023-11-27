#!/bin/bash

full_path="$(realpath $0)"
dir_path="$(dirname $full_path)"
source "${dir_path}/eap8_job.sh"

get_vbe_jar() {
  readonly PARENT_JOB_DIR=${PARENT_JOB_DIR:-'/parent_job'}
  echo "$(ls "${PARENT_JOB_DIR}"/target/jboss-set-version-bump-extension-*[^sc].jar)"
}

post_build() {
  record_build_properties
}

pre_test() {
  # unzip artifacts from build job
  find . -maxdepth 1 -name '*.zip' -exec unzip -q {} \;

  TEST_JBOSS_DIST=$(find . -regextype posix-extended -regex '.*jboss-eap-[7-8]\.[0-9]+')
  if [ -z "$TEST_JBOSS_DIST" ]; then
    echo "No EAP distribution to be tested"
    exit 2
  else
    export TESTSUITE_OPTS="${TESTSUITE_OPTS} -Djboss.dist=${WORKSPACE}/${TEST_JBOSS_DIST}"
  fi

  # shellcheck disable=SC2154
  if [ "${ip}" == "ipv6" ];
  then
    export TESTSUITE_OPTS="${TESTSUITE_OPTS} -Dipv6"
  fi
}

readonly EAP_SOURCES_DIR=${EAP_SOURCES_DIR:-"${WORKSPACE}"}
readonly MAVEN_SETTINGS_XML=${MAVEN_SETTINGS_XML-'/home/master/settings.xml'}

setup ${@}
do_run ${PARAMS}