#!/usr/bin/env bats

# This file is used to test the tar gz package.

# WARNING: This testing file must be executed as root and can
# dramatically change your system. It should only be executed
# in a throw-away VM like those made by the Vagrantfile at
# the root of the Elasticsearch source code. This should
# cause the script to fail if it is executed any other way:
[ -f /etc/is_vagrant_vm ] || {
  >&2 echo "must be run on a vagrant VM"
  exit 1
}

# The test case can be executed with the Bash Automated
# Testing System tool available at https://github.com/sstephenson/bats
# Thanks to Sam Stephenson!

# Licensed to Elasticsearch under one or more contributor
# license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright
# ownership. Elasticsearch licenses this file to you under
# the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# Load test utilities
load $BATS_UTILS/utils.bash
load $BATS_UTILS/tar.bash
load $BATS_UTILS/plugins.bash

setup() {
    skip_not_tar_gz
    export ESHOME=/tmp/elassandra
    export_elasticsearch_paths
}


@test "[TAR] dummy test to cleanup" {
    rm -rf "/tmp/elassandra"
}

##################################
# Install TAR GZ package
##################################
@test "[TAR] tar command is available" {
    # Cleans everything for the 1st execution
    clean_before_test
    run tar --version
    [ "$status" -eq 0 ]
}

@test "[TAR] archive is available" {
    count=$(find . -type f -name 'elassandra*.tar.gz' | wc -l)
    [ "$count" -eq 1 ]
}

@test "[TAR] archive is not installed" {
    count=$(find /tmp -type d -name 'elassandra*' | wc -l)
    [ "$count" -eq 0 ]
}

@test "[TAR] install archive" {

    # Install the archive
    install_archive

    count=$(find /tmp -type d -name 'elassandra*' | wc -l)
    [ "$count" -eq 1 ]

    # Its simpler to check that the install was correct in this test rather
    # than in another test because install_archive sets a number of path
    # variables that verify_archive_installation reads. To separate this into
    # another test you'd have to recreate the variables.
    verify_archive_installation
}

@test "[TAR] verify elasticsearch-plugin list runs without any plugins installed" {
    # previously this would fail because the archive installations did
    # not create an empty plugins directory
    local plugins_list=`$ESHOME/bin/elasticsearch-plugin list`
    [[ -z $plugins_list ]]
}

@test "[TAR] elasticsearch fails if java executable is not found" {
  local JAVA="$(which java)"

  sudo chmod -x $JAVA
  [ -n "$JAVA_HOME" ] && SAVE_JAVA_HOME="$JAVA_HOME"
  unset JAVA_HOME
  run "$ESHOME/bin/cassandra"
  [ -n "$SAVE_JAVA_HOME" ] && export JAVA_HOME="$SAVE_JAVA_HOME"
  sudo chmod +x $JAVA

  [ "$status" -eq 1 ]
  local expected="Cassandra 3.0 and later require Java 8u40 or later."
  [[ "$output" == *"$expected"* ]] || {
    echo "Expected error message [$expected] but found: $output"
    false
  }
}

##################################
# Check that Elasticsearch is working
##################################
@test "[TAR] test elasticsearch" {
    # Install scripts used to test script filters and search templates before
    # starting Elasticsearch so we don't have to wait for elasticsearch to scan for
    # them.
    install_elasticsearch_test_scripts
    start_elasticsearch_service
    #run_elasticsearch_tests
    stop_elasticsearch_service
}

@test "[TAR] start Elasticsearch with custom JVM options" {
    local es_java_opts=$ES_JAVA_OPTS
    ls -l $ESHOME/conf
    cp $ESHOME/conf/jvm.options $ESHOME/conf/jvm.options.bak
    chown cassandra:cassandra "$ESHOME/conf/jvm.options.bak"
    echo "-Xms1024m" >> "$ESHOME/conf/jvm.options"
    echo "-Xmx1024m" >> "$ESHOME/conf/jvm.options"
    # we have to disable Log4j from using JMX lest it will hit a security
    # manager exception before we have configured logging; this will fail
    # startup since we detect usages of logging before it is configured
    echo "-Dlog4j2.disable.jmx=true" >> "$ESHOME/conf/jvm.options"
    export ES_JAVA_OPTS="-XX:-UseCompressedOops"
    start_elasticsearch_service
    curl -s -XGET localhost:9200/_nodes
    curl -s -XGET localhost:9200/_nodes | fgrep '"heap_init_in_bytes":1073741824'
    curl -s -XGET localhost:9200/_nodes | fgrep '"using_compressed_ordinary_object_pointers":"false"'
    stop_elasticsearch_service
    export ES_JAVA_OPTS=$es_java_opts
    mv $ESHOME/conf/jvm.options.bak $ESHOME/conf/jvm.options
}

# Unquoted JSON option is deprecated
#@test "[TAR] start Elasticsearch with unquoted JSON option" {
#    local es_java_opts=$ES_JAVA_OPTS
#    local es_jvm_options=$ES_JVM_OPTIONS
#    local temp=`mktemp -d`
#    touch "$temp/jvm.options"
#    chown -R elasticsearch:elasticsearch "$temp"
#    echo "-Delasticsearch.json.allow_unquoted_field_names=true" >> "$temp/jvm.options"
#    # we have to disable Log4j from using JMX lest it will hit a security
#    # manager exception before we have configured logging; this will fail
#    # startup since we detect usages of logging before it is configured
#    echo "-Dlog4j2.disable.jmx=true" >> "$temp/jvm.options"
#    export ES_JVM_OPTIONS="$temp/jvm.options"
#    start_elasticsearch_service
#    # unquoted field name
#    curl -s -XPOST localhost:9200/i/d/1 -d'{foo: "bar"}'
#    [ "$?" -eq 0 ]
#    curl -s -XDELETE localhost:9200/i
#    stop_elasticsearch_service
#    export ES_JVM_OPTIONS=$es_jvm_options
#    export ES_JAVA_OPTS=$es_java_opts
#}

@test "[TAR] remove tar" {
    rm -rf "/tmp/elassandra"
}