# Copyright EMBL-EBI 2001
# Author: Alistair Rust
# Creation: 03.10.2001
# Last modified AGR 25.07.2001
#
# some of these options can be specified on the command line (e.g. to
# the test genome script) and will override these defaults.
# 
# just remember to change the *_dbpass settings for your own set-up
# unless you override them on the command line.


BEGIN {

package main;

%testgenomeConf = (
    'ref_host'     => 'ecs1a',
    'ref_dbname'   => 'alistair_db',
    'ref_port'     => '3306',
    'ref_dbclient' => 'mysql',
    'ref_dbuser'   => 'ensadmin',
    'ref_dbpass'   => 'XXXX',
    'new_host'     => 'ecs1a',
    'new_dbname'   => 'alistair_db',
    'new_port'     => '3306',
    'new_dbclient' => 'mysql',
    'new_dbuser'   => 'ensadmin',
    'new_dbpass'   => 'XXXX'
);
}

1;
