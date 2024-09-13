#!/bin/bash

# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

join_array() { local d=$1; shift; echo -n "$1"; shift; printf "%s" "${@/#/$d}"; }

# Find some initial paths, where is this script,
# what is the repos' parent directory, and where
# are our dependencies installed
HARNESS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PPWD="${PWD}/.."
ENSDIR="${ENSDIR:-$PPWD}"
setenv="$ENSDIR/ensembl/activate"

# Setup the paths and perl5lib
source $setenv -vv $ENSDIR
if [ "$ENSDIR" != "$PPWD" ]; then
    source $setenv -vvd $PWD
fi

export TEST_AUTHOR=$USER

# If there's a database configuration for this build type, link
# it in to place
if [ -f "modules/t/MultiTestDB.conf.$DB" ]; then
    (cd modules/t && ln -sf MultiTestDB.conf.$DB MultiTestDB.conf)
fi

# Build the PERL5OPT and SKIP_TESTS based on the environment
MATRIX=( "" "_$DB" "_COVERALLS_$COVERALLS" )
PERL5OPT_array=()
SKIP_TESTS_array=()

for h in "${MATRIX[@]}"
do

    PERL5OPT_var="PERL5OPT$h"
    if [ ! -z ${!PERL5OPT_var} ]; then
	PERL5OPT_array+=(${!PERL5OPT_var})
    fi

    SKIP_TESTS_var="SKIP_TESTS$h"
    if [ ! -z ${!SKIP_TESTS_var} ]; then
	SKIP_TESTS_array+=(${!SKIP_TESTS_var})
    fi
done

if [ ${#PERL5OPT_array[@]} -ne 0 ]; then
    PERL5OPT=$(join_array ' ' ${PERL5OPT_array[@]})
#    export PERL5OPT
    echo "Using PERL5OPT=$PERL5OPT"
fi

if [ ${#SKIP_TESTS_array[@]} -ne 0 ]; then
    SKIP_TESTS='--skip '
    SKIP_TESTS+=$(join_array ',' ${SKIP_TESTS_array[@]})
fi

echo "Running test suite"
echo "Executing: perl $ENSDIR/ensembl-test/scripts/runtests.pl modules/t $SKIP_TESTS"
PERL5OPT=$PERL5OPT perl $ENSDIR/ensembl-test/scripts/runtests.pl modules/t $SKIP_TESTS

rt=$?
if [ $rt -eq 0 ]; then
  if [ "$COVERALLS" = 'true' ]; then
    unset PERL5OPT
    echo "Running Devel::Cover coveralls report"
    cover --nosummary -report coveralls
  fi
  exit $?
else
  exit $rt
fi
