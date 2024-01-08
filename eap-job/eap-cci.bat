@echo off

echo Set the environment variables for Maven and Java
set "PATH=%M2_HOME%\bin;%JAVA_HOME%\bin;%PATH%"

echo Java version is
java -version

echo Maven version is
call mvn -v

echo Expand all .zip files in the current directory
for %%F in (*.zip) do (
    powershell -Command "Expand-Archive -Path '%%~F' -DestinationPath 'eap' -Force"
)

REM Check if EAP_VERSION is set
IF "%EAP_VERSION%"=="" (
    echo EAP_VERSION is not set!
    exit /b 1
)

REM Printing all the variables
echo Workspace is: %WORKSPACE%
echo EAP version is: jboss-eap-%EAP_VERSION%
echo Current ip version is: %ip%

REM pre-run the ClientCompatibilityUnitTestCase to download the depedencies using IPv4.
REM the test is then run again using IPv6 without the need to reach outside the IPv6 network
echo Pre build of tests
cd %WORKSPACE%\eap\eap-sources\testsuite\integration\basic
cmd /c "mvn clean install -Dtest=ClientCompatibilityUnitTestCase -Djboss.dist=%WORKSPACE%\eap\jboss-eap-%EAP_VERSION%"

REM Where JBoss EAP stores
cd %WORKSPACE%\eap\eap-sources

REM Check if %ip% is defined and run the testsuite accordingly
if "%ip%"=="ipv6" (
    echo Using IPv6
    cmd /c "mvn clean install -fae -DallTests -DfailIfNoTests=false -Dipv6"
) else (
    echo Using IPv4
    cmd /c "mvn clean install -fae -DallTests -DfailIfNoTests=false -Dipv4"
)

REM Check if the build was successful or not
IF %ERRORLEVEL% NEQ 0 (
    echo Build failed!
    exit /b %ERRORLEVEL%
)

echo Build successful!