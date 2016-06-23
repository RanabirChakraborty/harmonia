readonly CONTAINER_ID=$(docker run -d -v "${WORKSPACE}:/workspace"  -v "${MAVEN_HOME}:/maven_home" -v $(pwd):/job_home "${DOCKER_IMAGE}")

which java
java -version

readonly LOCAL_REPO_DIR=/workspace/maven-local-repository
readonly MAVEN_HOME=/maven_home
export MAVEN_HOME

export PATH=${MAVEN_HOME}/bin:${PATH}
export MAVEN_OPTS="-Xmx1024m -Xms512m -XX:MaxPermSize=256m"
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.repo.local=${LOCAL_REPO_DIR}"

TESTSUITE_OPTS="${TESTSUITE_OPTS} -Dsurefire.forked.process.timeout=90000"
TESTSUITE_OPTS="${TESTSUITE_OPTS} -Dskip-download-sources -B"
TESTSUITE_OPTS="${TESTSUITE_OPTS} -Djboss.test.mixed.domain.dir=/opt/old-as-releases"
TESTSUITE_OPTS="${TESTSUITE_OPTS} -Dmaven.test.failure.ignore=false"

cd testsuite
chmod +x ../tools/maven/bin/mvn
../tools/maven/bin/mvn clean
cd ..

chmod +x ./integration-tests.sh
bash -x ./integration-tests.sh -DallTests ${TESTSUITE_OPTS}