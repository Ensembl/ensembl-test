# Copyright EMBL-EBI 2001
# Author: Alistair Rust
# Creation: 04.10.2001
# Last modified:
#
# File name: test_genome_populate.sql
#
# This file should be used in conjunction with 
# test_genome_table.sql which generates the empty
# database into which the following data is stored.
#
# The current implementation is to grab 2Mbs from:
# - 233M to 224M from chr 2
# - 1 to 1M from chr 20
#
# The sql also modifies the Rule* tables to run a subset
# of jobs
#

use alistair_testgenome;
               

# create a temp table to store clone ids for those clones
# that we're interested in

create 	temporary table tmp1( 
	clone_id int(10) NOT NULL );


# find those clones present in some central, exciting
# 1Mbases on chromosome 2

insert	into tmp1
select	distinct(c.clone)
from 	human_live.contig c, human_live.static_golden_path s
where	s.raw_id = c.internal_id
and	chr_name = 'chr2'
and	chr_start > 223000000
and	chr_start < 224000001;


# find those clones present in the first
# 1Mbases on chromosome 20

insert	into tmp1
select	distinct(c.clone)
from 	human_live.contig c, human_live.static_golden_path s
where	s.raw_id = c.internal_id
and	chr_name = 'chr20'
and	chr_start > 0
and	chr_start < 1000000;


# slice out the relevant clones from the human_live
# clone table to create the test genome clone table
# need to add an insert statement here
insert 	into clone
select	h.* 
from 	human_live.clone h, tmp1 t
where	h.internal_id = t.clone_id;


# retrieve all contigs on the clones present in
# the first 1Mbases be they on the Golden Path
# or not

insert	into contig
select	h.*
from	human_live.contig h, tmp1 t
where	h.clone = t.clone_id;


# create the relevant dna table for the contigs
# in the test genome
# *** need to add an insert statement here like

insert	into dna
select	d.*
from	human_live.dna d, contig
where	d.id = contig.dna;



# copy the analysis table from the human_live db

insert	into analysis
select	*
from	human_live.analysis;


# copy the analysisprocess table from the human_live db

insert	into analysisprocess
select	*
from	human_live.analysisprocess;


#
# Create a modified 'RuleGoal' table
#
 
INSERT INTO RuleGoal VALUES (1,1);
INSERT INTO RuleGoal VALUES (2,2);
INSERT INTO RuleGoal VALUES (3,4);
INSERT INTO RuleGoal VALUES (4,5);
INSERT INTO RuleGoal VALUES (5,9);

# This was the rule for running dbESTs but this is looking
# like being too time consuming
#INSERT INTO RuleGoal VALUES (6,12);    



#
# Create a modified 'RuleConditions' table
#
 
INSERT INTO RuleConditions VALUES (1,'SubmitContig');
INSERT INTO RuleConditions VALUES (2,'RepeatMask');
INSERT INTO RuleConditions VALUES (3,'Genscan');
INSERT INTO RuleConditions VALUES (4,'Genscan');
INSERT INTO RuleConditions VALUES (5,'Genscan');

# Same reasoning as above for dbESTs
#INSERT INTO RuleConditions VALUES (6,'Genscan');      


#
# copy the static_golden_path table from human_live db
#

insert	into static_golden_path
select	*
from	human_live.static_golden_path;


#
# populate the InputIdAnalysis table
#
insert	into InputIdAnalysis(inputId)
select	contig.id
from	contig;


#
# set the InputIdAnalysis ready to run
#
update	InputIdAnalysis
set	class="contig",
	analysisId=3,
	created="2001-10-01 00:00:00";


# finally, drop the temporary table

drop	table tmp1;
