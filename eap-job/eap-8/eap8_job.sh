#!/bin/bash
#
#
# Build Wildlfy/EAP
#
set -eo pipefail

usage() {
  local -r script_name=$(basename "${0}")
  echo "${script_name} <build|testsuite> [extra-args]"
  echo
  echo "ex: ${script_name} 'testsuite' -Dcustom.args"
  echo
  echo Note that if no arguments is provided, it default to 'build'. To run the testsuite, you need to provide 'testsuite' as a first argument. All arguments beyond this first will be appended to the mvn command line.
  echo
  echo 'Warning: This script also set several mvn args. Please refer to its content before adding some extra maven arguments.'
}

is_dirpath_defined_and_exists() {
  local dir_path=${1}
  local var_name=${2}

  if [ "${dir_path}" = '' ]; then
    echo "Directory path provided by ${var_name} is not set."
    return 1
  fi

  if [ ! -d "${dir_path}" ]; then
    echo "Following dir_path does not exists: ${dir_path}."
    return 2
  fi
}

check_java() {
  # ensure provided JAVA_HOME, if any, is first in PATH
  if [ -n "${JAVA_HOME}" ]; then
    export PATH=${JAVA_HOME}/bin:${PATH}
  fi

  command -v java
  java -version
  # shellcheck disable=SC2181
  if [ "${?}" -ne 0 ]; then
     echo "No JVM provided - aborting..."
     exit 1
  fi
}

configure_mvn_home() {
  if [ -z "${MAVEN_HOME}" ] || [ ! -e "${MAVEN_HOME}/bin/mvn" ]; then
    echo "No Maven Home defined - setting to default: ${DEFAULT_MAVEN_HOME}"
    export MAVEN_HOME=${DEFAULT_MAVEN_HOME}
    if [ ! -d  "${DEFAULT_MAVEN_HOME}" ]; then
      echo "No maven install found (${DEFAULT_MAVEN_HOME}) - downloading one:"
      cd "$(pwd)/tools" || exit "${FOLDER_DOES_NOT_EXIST_ERROR_CODE}"
      MAVEN_HOME="$(pwd)/maven"
      export MAVEN_HOME
      bash ./download-maven.sh
      chmod +x ./*/bin/*
      cd - || exit "${FOLDER_DOES_NOT_EXIST_ERROR_CODE}"
      readonly IS_MAVEN_LOCAL=${IS_MAVEN_LOCAL:-'true'}
      export IS_MAVEN_LOCAL
    fi
  fi
  configure_mvn_vbe_if_required

  #export PATH="${MAVEN_HOME}"/bin:"${PATH}"
  readonly MAVEN_BIN_DIR="${MAVEN_HOME}"/bin
  export MAVEN_BIN_DIR
  echo "Adding ${MAVEN_BIN_DIR} to PATH:${PATH}."
  export PATH="${MAVEN_BIN_DIR}":"${PATH}"

  command -v mvn
  mvn -version
  # shellcheck disable=SC2181
  if [ "${?}" -ne 0 ]; then
    echo "No MVN provided - aborting..."
    exit 2
  fi
}

configure_mvn_vbe_if_required(){
  if [ -n "${VBE_EXTENSION}" ]; then
	  	#copy, into local, if its dwn, dont copy, just alter
	  	echo "------------------ SETTING UP Version Bump Extension ------------------"
      readonly VBE_JAR=$(get_vbe_jar)

		echo "VBE_JAR: ${VBE_JAR}"

		if [ -z "${IS_MAVEN_LOCAL}" ]; then
			#Not local, we need one
			mkdir "$(pwd)/maven"
			cp -r "$MAVEN_HOME"/* "$(pwd)/maven"
			readonly MAVEN_HOME="$(pwd)/maven"
			export MAVEN_HOME
		fi
		mkdir -p "$MAVEN_HOME/lib/ext"
		cp "$VBE_JAR" "$MAVEN_HOME/lib/ext/"
		if [ -n "${VBE_CHANNELS}" ]; then
	            export MAVEN_OPTS="${MAVEN_OPTS} -Dvbe.channels=${VBE_CHANNELS}"
		fi
		if [ -n "${VBE_LOG_FILE}" ]; then
	            export MAVEN_OPTS="${MAVEN_OPTS} -Dvbe.log.file=${VBE_LOG_FILE}"
		fi
		if [ -n "${VBE_REPOSITORY_NAMES}" ]; then
	            export MAVEN_OPTS="${MAVEN_OPTS} -Dvbe.repository.names=${VBE_REPOSITORY_NAMES}"
		fi
		echo "------------------ DONE SETTING UP Version Bump Extension ------------------"
	else
		readonly MAVEN_HOME="${MAVEN_HOME}"
		export MAVEN_HOME
  fi
}

configure_mvn_opts() {
  if [ -n "${LOCAL_REPO_DIR}" ]; then
    mkdir -p "${LOCAL_REPO_DIR}"
  fi
  export MAVEN_OPTS="${MAVEN_OPTS} ${MEMORY_SETTINGS}"
  # workaround wagon issue - https://projects.engineering.redhat.com/browse/SET-20
  export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.wagon.http.pool=${MAVEN_WAGON_HTTP_POOL}"
  export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.wagon.httpconnectionManager.maxPerRoute=${MAVEN_WAGON_HTTP_MAX_PER_ROUTE}"
  # using project's maven repository
  export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.repo.local=${LOCAL_REPO_DIR}"
}

record_build_properties() {
  touch 'umb-build.properties'
  readonly PROPERTIES_FILE='umb-build.properties'
  # shellcheck disable=SC2155
  readonly EAP_VERSION=$(grep -r '<full.dist.product.release.version>' "$EAP_SOURCES_DIR/pom.xml" | sed 's/.*>\(.*\)<.*/\1/')

  # shellcheck disable=SC2129
  echo "BUILD_URL=${BUILD_URL}" >> ${PROPERTIES_FILE}
  echo "SERVER_URL=${BUILD_URL}artifact/jboss-eap-dist-${GIT_COMMIT:0:7}.zip" >> ${PROPERTIES_FILE}
  echo "SOURCE_URL=${BUILD_URL}artifact/jboss-eap-src-${GIT_COMMIT:0:7}.zip" >> ${PROPERTIES_FILE}
  echo "VERSION=${EAP_VERSION}-${GIT_COMMIT:0:7}" >> ${PROPERTIES_FILE}
  echo "BASE_VERSION=${EAP_VERSION}" >> ${PROPERTIES_FILE}
  echo "BUILD_ID=${BUILD_ID}" >> ${PROPERTIES_FILE}
  echo "SCM_URL=${GIT_URL}" >> ${PROPERTIES_FILE}
  echo "SCM_REVISION=${GIT_COMMIT}" >> ${PROPERTIES_FILE}

  cat ${PROPERTIES_FILE}

}

configure_mvn_settings() {
  if [ -n "${MAVEN_SETTINGS_XML}" ]; then
    readonly MAVEN_SETTINGS_XML_OPTION="-s ${MAVEN_SETTINGS_XML}"
  else
    readonly MAVEN_SETTINGS_XML_OPTION=''
  fi
  export MAVEN_SETTINGS_XML_OPTION
}

setup() {
  BUILD_COMMAND=${1}

  if [ "${BUILD_COMMAND}" = '--help' ] || [ "${BUILD_COMMAND}" = '-h' ]; then
    usage
    exit 0
  fi

  if [ "${BUILD_COMMAND}" != 'build' ] && [ "${BUILD_COMMAND}" != 'testsuite' ]; then
    readonly BUILD_COMMAND='build'
  else
    readonly BUILD_COMMAND="${BUILD_COMMAND}"
    shift
  fi

  readonly MAVEN_VERBOSE=${MAVEN_VERBOSE}
  readonly GIT_SKIP_BISECT_ERROR_CODE=${GIT_SKIP_BISECT_ERROR_CODE:-'125'}

  readonly LOCAL_REPO_DIR=${LOCAL_REPO_DIR:-${WORKSPACE}/maven-local-repository}
  readonly MEMORY_SETTINGS=${MEMORY_SETTINGS:-'-Xmx2048m -Xms1024m'}
  readonly SUREFIRE_MEMORY_SETTINGS=${SUREFIRE_MEMORY_SETTINGS:-'-Xmx1024m'}

  readonly BUILD_OPTS=${BUILD_OPTS:-'-Drelease'}

  readonly MAVEN_WAGON_HTTP_POOL=${WAGON_HTTP_POOL:-'false'}
  readonly MAVEN_WAGON_HTTP_MAX_PER_ROUTE=${MAVEN_WAGON_HTTP_MAX_PER_ROUTE:-'3'}
  readonly SUREFIRE_FORKED_PROCESS_TIMEOUT=${SUREFIRE_FORKED_PROCESS_TIMEOUT:-'90000'}
  readonly FAIL_AT_THE_END=${FAIL_AT_THE_END:-'-fae'}
  readonly RERUN_FAILING_TESTS=${RERUN_FAILING_TESTS:-'0'}

  readonly OLD_RELEASES_FOLDER=${OLD_RELEASES_FOLDER:-/opt/old-as-releases}

  readonly FOLDER_DOES_NOT_EXIST_ERROR_CODE='3'
  readonly ZIP_WORKSPACE=${ZIP_WORKSPACE:-'false'}

  # use PARAMS to account for shift
  readonly PARAMS=${@}

  if [ -n "${EXECUTOR_NUMBER}" ]; then
    echo -n "Job run by executor ID ${EXECUTOR_NUMBER} "
  fi

  if [ -n "${WORKSPACE}" ]; then
    echo -n "inside workspace: ${WORKSPACE}"
  fi
  echo '.'

  check_java
  configure_mvn_home
  configure_mvn_opts
  configure_mvn_settings
}

pre_build() {
  :
}

post_build() {
  :
}

pre_test() {
  :
}

do_run() {
  if [[ "${JOB_NAME}" == "eap-8.0.x-align-core" ]]; then

    # Run Maven commands for upgrading dependencies and injecting repositories
    mvn -s /opt/tools/settings.xml org.wildfly:wildfly-channel-maven-plugin:upgrade \
      -DignorePropertiesPrefixedWith=legacy. \
      -DmanifestFile=../eap8-manifest-proposed.yaml

    mvn -s /opt/tools/settings.xml org.wildfly:wildfly-channel-maven-plugin:inject-repositories \
      -DfromChannelFile=../eap-channel-file.yaml

    git diff -C "${PWD}" | tee "../core-align.diff"

  elif [[ "${JOB_NAME}" == "eap-8.0.x-align-eap-8.0" ]]; then

    # Run Maven commands for upgrading dependencies and injecting repositories
    mvn -s /opt/tools/settings.xml org.wildfly:wildfly-channel-maven-plugin:upgrade \
        -DmanifestFile=../eap8-manifest-proposed.yaml \
        -DignoreModules=org.jboss.eap:wildfly-legacy-ee-bom \
        -DignorePropertiesPrefixedWith=legacy. \
        -DignoreProperties=version.org.glassfish.jaxb.jaxb-runtime

    mvn -s /opt/tools/settings.xml org.wildfly:wildfly-channel-maven-plugin:inject-repositories \
        -DfromChannelFile=../eap-channel-file.yaml

    git diff -C "${PWD}" | tee "../eap-align.diff"

    elif [[ "${JOB_NAME}" == "eap-8.0.x-aligned-core-testsuite" ]]; then
      pre_test

      mvn -s /opt/tools/settings.xml clean install -DallTests -fae -Dverifier.failOnError=false -Dserver.startup.timeout=60000

    elif [[ "${JOB_NAME}" == "eap-8.0.x-aligned-eap-8.0.-build" ]]; then

      # shellcheck disable=SC2086,SC2068
      echo mvn clean install ${MAVEN_VERBOSE}  "${FAIL_AT_THE_END}" ${MAVEN_SETTINGS_XML_OPTION} -B -Dverifier.failOnError=false
      # shellcheck disable=SC2086,SC2068
      mvn clean install ${MAVEN_VERBOSE}  "${FAIL_AT_THE_END}" ${MAVEN_SETTINGS_XML_OPTION} -B -Dverifier.failOnError=false

      cd ${WORKSPACE}
      zip -r "eap-sources.zip" .

      post_build
    elif [[ "${JOB_NAME}" == "eap-8.0.x-aligned-eap-8.0-testsuite" ]]; then
      pre_test

      set -x  # Enable debugging
      unset JBOSS_HOME
      export TESTSUITE_OPTS="${TESTSUITE_OPTS} -Dsurefire.forked.process.timeout=${SUREFIRE_FORKED_PROCESS_TIMEOUT}"
      export TESTSUITE_OPTS="${TESTSUITE_OPTS} -Dskip-download-sources -B"
      export TESTSUITE_OPTS="${TESTSUITE_OPTS} -Djboss.test.mixed.domain.dir=${OLD_RELEASES_FOLDER}"
      export TESTSUITE_OPTS="${TESTSUITE_OPTS} -Dmaven.test.failure.ignore=${MAVEN_IGNORE_TEST_FAILURE}"
      export TESTSUITE_OPTS="${TESTSUITE_OPTS} -Dsurefire.rerunFailingTestsCount=${RERUN_FAILING_TESTS}"
      export TESTSUITE_OPTS="${TESTSUITE_OPTS} -Dsurefire.memory.args=${SUREFIRE_MEMORY_SETTINGS}"

      export TESTSUITE_OPTS="${TESTSUITE_OPTS} ${MAVEN_SETTINGS_XML_OPTION}"

      export TEST_TO_RUN=${TEST_TO_RUN:-'-DallTests'}
      cd "${EAP_SOURCES_DIR}/testsuite" || exit "${FOLDER_DOES_NOT_EXIST_ERROR_CODE}"
      mvn clean
      cd ..

      # shellcheck disable=SC2086,SC2068
      # bash -x ./integration-tests.sh -Dts.timeout.factor=900 "${TEST_TO_RUN}" ${MAVEN_VERBOSE} "${FAIL_AT_THE_END}" ${TESTSUITE_OPTS} ${@}
      bash -x ./integration-tests.sh -Djboss.as.management.blocking.timeout=90000 -Dserver.startup.timeout=90000 "${TEST_TO_RUN}" ${MAVEN_VERBOSE} "${FAIL_AT_THE_END}" ${TESTSUITE_OPTS} ${@}
      exit "${?}"
    elif [[ "${JOB_NAME}" == "eap-8.0.x-repository-build" ]]; then

      #!/bin/bash -x

      # Download latest prospero-extras release
      readonly PROSPERO_EXTRAS_VERSION=$(curl -I https://github.com/wildfly-extras/prospero-extras/releases/latest | awk -F '/' '/^location/ {print  substr($NF, 1, length($NF)-1)}')
      echo "Downloading prospero-extras version: ${PROSPERO_EXTRAS_VERSION}"
      curl -L "https://github.com/wildfly-extras/prospero-extras/releases/download/${PROSPERO_EXTRAS_VERSION}/prospero-extras-${PROSPERO_EXTRAS_VERSION}-shaded.jar" -o prospero-extras.jar

      # Checkout and build bom-generator if RUNTIME_ONLY is not set to true
      if [ "$RUNTIME_ONLY" = false ]; then
          # Checkout and build bom-generator
          # TODO: replace with release or a separate job
          git clone -b main https://gitlab.cee.redhat.com/bspyrkos/bom-generator
          cd "${WORKSPACE}/bom-generator" && mvn clean install -DskipTests && cd "${WORKSPACE}"

          # TODO: use proposed channel when it is published
          if [ -n "${EAP_CHANNEL}" ]; then
              curl "${EAP_CHANNEL}" -o eap8-channel.yaml
          else
              # TODO: generate this channel or use a template
              cat > eap8-channel.yaml << EOL
---
schemaVersion: 2.0.0
name: "eap8-channel"
manifest:
    maven:
      groupId: org.jboss.eap.channels
      artifactId: eap-8.0
        version: ${EAP_MANIFEST_VERSION}
repositories:
    - id: "brew"
      url: "https://download.eng.bos.redhat.com/brewroot/repos/jb-eap-8.0-maven-build/latest/maven/"
    - id: "central"
      url: "https://repo1.maven.org/maven2/"
EOL
          fi

          OPTION_ARGS='--include-sources --include-poms'
      else
          OPTION_ARGS=''
      fi

      java -jar ${WORKSPACE}/prospero-extras.jar repository download from-channel \
          --out maven-repository \
          --channel eap8-channel.yaml \
          ${OPTION_ARGS}

      if [ "$RUNTIME_ONLY" = false ]; then
          # Generate the pom resolving all the BOM dependencies
          mkdir "${WORKSPACE}/eap-bom-downloader" && cd "${WORKSPACE}/eap-bom-downloader"
          "${WORKSPACE}/bom-generator/bom-generator" \
              --channel "${BOMS_CHANNEL}" \
              --out pom.xml

          # Build the project to resolve all dependencies. dependency:resolve misses some boms
          mvn clean install dependency:sources -Dmaven.repo.local="${WORKSPACE}/maven-repository"

          cd "${WORKSPACE}"

          find "${WORKSPACE}/maven-repository" -not -name '*redhat-*' -type f -exec rm {} \;
          find "${WORKSPACE}/maven-repository" -name '*\.lastUpdated' -type f -exec rm {} \;
          find "${WORKSPACE}/maven-repository" -type d -empty -delete
      fi

      # Add licenses, remove maven-metadata.xml, etc.
      cd "${WORKSPACE}/"
      zip -qr maven-repository.zip maven-repository/
      # Generate list of files in repository
      find maven-repository \
        -type f -name '*' \
        -exec sha256sum {} \; \
        | sed -E 's/  */,/' | sed 's/maven-repository//' \
        | sort -k 2 -t ',' > maven-repository-content-with-sha256-checksums.txt

      post_build
  else
    echo "Unsupported JOB_NAME: ${JOB_NAME}"
    exit 1
  fi
}