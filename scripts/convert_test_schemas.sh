#!/bin/bash

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2024] EMBL-European Bioinformatics Institute
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

script_dir=$( cd $( dirname $0 ); echo $PWD )
test_dir=$1

if [ ! -d "${test_dir}" ]; then
    echo "Cannot find: ${test_dir}"
    exit 1;
fi

dumped_schema='Bio-EnsEMBL-Test-Schema-0.1-SQLite.sql'
dest_schema='table.sql'

convert_schema() {
  local species db_type
  species="$1"
  db_type="$2"

  schema_dir="${test_dir}/test-genome-DBs/${species}/${db_type}"
  if [ ! -d "${schema_dir}" ]; then
    echo "Cannot find: ${schema_dir}"
    exit 1;
  fi

  echo "Dumping '$species' - '$db_type'"
  "${script_dir}/dump_test_schema.pl" --species "${species}" --db_type "${db_type}" --test_dir "${test_dir}"

  dest_dir="${schema_dir}/SQLite"
  mkdir -v -p "${dest_dir}"
  mv -v "${dumped_schema}" "${dest_dir}/${dest_schema}"
  echo
}

(
    cd "${test_dir}/test-genome-DBs"
    for species in *; do
        (
            cd "${species}"
            for db_type in *; do
		if [[ "${db_type}" == *"variation"* ]]; then
		    echo "We don't dump variation databases as SQLite, bye."
		    continue
		fi
                convert_schema "${species}" "${db_type}"
            done
        )
    done
)

exit 0

# EOF
