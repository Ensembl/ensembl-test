#!/bin/sh

script_dir=$( cd $( dirname $0 ); echo $PWD )
test_dir=${1:-modules/t}

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

for db_type in core empty; do
  convert_schema 'homo_sapiens' "${db_type}"
done

convert_schema 'circ' 'core'

exit 0

# EOF
