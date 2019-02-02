#!/bin/bash
################################################################################
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
################################################################################
#
# This script publishes the Kudu binary jars generated by the
# build_mini_cluster_binaries.sh script to a local or remote
# repository.
#
# Parameters:
#
#   -a, --action: (default "install")
#     Either install or deploy. If install, the jars will be
#     installed into the local Maven repository. If deploy, the jars
#     will be deployed to the remote Maven repository defined by MVN_REPO_URL.
#
#   -j, --jars: (default "build/mini-cluster")
#    Defines the Maven repository url to deploy to.
#     Only used when the --action is deploy.
#
#   -r, --repo: (default "https://repository.apache.org/content/repositories/snapshots")
#     Defines the Maven repository url to deploy to.
#     Only used when the --action is deploy.
#
#   -u, --username:
#     The username to the maven repository.
#     Only used when the --action is deploy.
#
#   -p, --password:
#     The password to the maven repository.
#     Only used when the --action is deploy.
#
#   --skipPom:
#     If this flag is passed, the pom is not published.
#
# Example:
#   publish_mini_cluster_binaries.sh -a=deploy -u="foo-user" -p="foo-pass"
#
################################################################################
set -e

SOURCE_ROOT=$(cd $(dirname $0)/../..; pwd)
BUILD_ROOT="$SOURCE_ROOT/build/mini-cluster"
VERSION=$(cat ${SOURCE_ROOT}/version.txt)

# Set the parameter defaults.
MVN_ACTION="install"
JAR_PATH="$BUILD_ROOT"
MVN_REPO_URL="https://repository.apache.org/content/repositories/snapshots"
PUBLISH_POM=1

# Parse the command line parameters.
for i in "$@"; do
  case ${i} in
      -a=*|--action=*)
      MVN_ACTION="${i#*=}"
      shift
      ;;
      -j=*|--jars=*)
      JAR_PATH="${i#*=}"
      shift
      ;;
      -r=*|--repo=*)
      MVN_REPO_URL="${i#*=}"
      shift
      ;;
      -u=*|--username=*)
      MVN_USERNAME="${i#*=}"
      shift
      ;;
      -p=*|--password=*)
      MVN_PASSWORD="${i#*=}"
      shift
      ;;
      --skipPom)
      PUBLISH_POM=0
      shift
      ;;
      *)  # unknown option
      ;;
  esac
done

# Validate the passed parameters.
if [[ "$MVN_ACTION" != "deploy" && "$MVN_ACTION" != "install" ]]; then
  echo "--action must be install or deploy"
  exit 1
fi
if [[ "$MVN_ACTION" == "deploy" ]]; then
  if [[ -z "$MVN_USERNAME" ]]; then
    echo "--username must be set when --action=deploy"
    exit 1
  fi
  if [[ -z "$MVN_PASSWORD" ]]; then
    echo "--password must be set when --action=deploy"
    exit 1
  fi
fi

# Validate Maven is installed.
if [[ -z $(which mvn) ]]; then
  echo "'mvn' was not found. Maven is required to publish the jars."
  exit 1
fi

# Static variables.
PROP_FILE="META-INF/apache-kudu-test-binary.properties"
ARTIFACT_GROUP="org.apache.kudu"
ARTIFACT_ID="kudu-binary"

# Common Maven arguments.
COMMON_MVN_ARGS="-DgeneratePom=false"
COMMON_MVN_ARGS="$COMMON_MVN_ARGS -DgroupId=$ARTIFACT_GROUP"
COMMON_MVN_ARGS="$COMMON_MVN_ARGS -DartifactId=$ARTIFACT_ID"
COMMON_MVN_ARGS="$COMMON_MVN_ARGS -Dversion=$VERSION"

# Attempts to read a property from the mini cluster properties file
# in the passed jar. If the property is not found, it prints an error
# and exits.
function read_prop_or_die() {
  local JAR=$1
  local KEY=$2
  if [[ ! -f "$JAR" ]]; then
    echo "Jar file not found: $JAR"
    exit 1
  fi
  local PROP=$(unzip -q -c ${JAR} ${PROP_FILE} | grep "$KEY" | cut -d'=' -f2)
  if [[ -z ${PROP} ]]; then
    echo "$KEY property not found in $JAR/$PROP_FILE"
    exit 1
  fi
  echo ${PROP}
}

# Executes the appropriate maven action based on MVN_ACTION with the
# passed parameters as arguments. When the action is 'deploy' additional
# arguments are added to handle the repository, username, and password.
function maven_action() {
  if [[ "$MVN_ACTION" == "install" ]]; then
    mvn install:install-file ${@}
  elif [[ "$MVN_ACTION" == "deploy" ]]; then
    ARGS=${@}
    ARGS="$ARGS -Durl=$MVN_REPO_URL"
    # Configure maven to pass the username and password with a custom settings.xml.
    ARGS="$ARGS --settings $SOURCE_ROOT/build-support/mini-cluster/settings.xml"
    ARGS="$ARGS -DrepositoryId=apache"
    ARGS="$ARGS -Drepo.username=$MVN_USERNAME"
    ARGS="$ARGS -Drepo.password=$MVN_PASSWORD"
    mvn deploy:deploy-file ${ARGS}
  fi
}

# Publish a generated pom.
if [[ "${PUBLISH_POM}" == "1" ]]; then
  # Create a minimal POM file.
  POM_FILE=${BUILD_ROOT}/pom.xml
  cat <<EOF > ${POM_FILE}
<?xml version="1.0" encoding="UTF-8"?>
<project xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd" xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <modelVersion>4.0.0</modelVersion>
  <groupId>${ARTIFACT_GROUP}</groupId>
  <artifactId>${ARTIFACT_ID}</artifactId>
  <version>${VERSION}</version>
  <description>An archive of Kudu binaries for use in a "mini cluster" environment for TESTING ONLY.</description>
  <url>https://kudu.apache.org/</url>
  <licenses>
    <license>
      <name>The Apache Software License, Version 2.0</name>
      <url>http://www.apache.org/licenses/LICENSE-2.0.txt</url>
      <distribution>repo</distribution>
    </license>
  </licenses>
</project>
EOF
  POM_MVN_ARGS="$COMMON_MVN_ARGS"
  POM_MVN_ARGS="$POM_MVN_ARGS -Dfile=$POM_FILE"
  POM_MVN_ARGS="$POM_MVN_ARGS -Dpackaging=pom"
  maven_action ${POM_MVN_ARGS}
fi

# Publish the generated jars that have the correct version.
for JAR in ${JAR_PATH}/${ARTIFACT_ID}-${VERSION}-*.jar; do
  JAR_ARCH=$(read_prop_or_die "$JAR" "artifact.arch")
  JAR_OS=$(read_prop_or_die "$JAR" "artifact.os")
  JAR_VERSION=$(read_prop_or_die "$JAR" "artifact.version")
  if [[ "$JAR_VERSION" != "$VERSION" ]]; then
    echo "The version ($VERSION) doesn't match the jar's artifact.version property ($JAR_VERSION)"
    exit 1
  fi
  JAR_CLASSIFIER="$JAR_OS-$JAR_ARCH"
  JAR_MVN_ARGS="$COMMON_MVN_ARGS"
  JAR_MVN_ARGS="$JAR_MVN_ARGS -Dclassifier=$JAR_CLASSIFIER"
  JAR_MVN_ARGS="$JAR_MVN_ARGS -Dfile=$JAR"
  JAR_MVN_ARGS="$JAR_MVN_ARGS -Dpackaging=jar"
  maven_action ${JAR_MVN_ARGS}
done
