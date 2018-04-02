
set num_eABF_steps 0

set lastJobID 0 

source eABF.conf
source                 ./pathCV.tcl

namespace eval pathCV {
  set lambda     20.   
  set tolerance  1e-4  
  set freq       20    
  set min_images 4     
                       
}

replicaBarrier
set replica_id [myReplica]

if { [info exists restart] == 0 } {
	set restart no 
}

# The file will be modified before being passed to colvars
#colvarsConfig $pathCV_file

set rank [myReplica]
set num_replicas [numReplicas]
#set num_swarms [expr $num_replicas / $num_images]
#set image_rank [expr int($rank / $num_swarms)]
set image_rank 0


if { $restart } {
	source [format $output_root.restart.tcl $replica_id]
} else {
	set i_job 0
	set i_iter 0
	set i_step 0
}
if { $i_job == 0 } {
	if [info exists bincoor_file] {
		bincoordinates [format $bincoor_file $image_rank]
	}
	if [info exists xsc_file] {
		extendedSystem [format $xsc_file $image_rank]
	}
	temperature $temperature
} else {
	bincoordinates [format $output_root.job%04d.restart.coor $replica_id [expr $i_job - 1]]
	binvelocities [format $output_root.job%04d.restart.vel $replica_id [expr $i_job - 1]]
	if [info exists xsc_file] {
		extendedSystem [format $output_root.job%04d.restart.xsc $replica_id [expr $i_job - 1]]
	}
}
#set job_output_root [format $combine_output_root.job%04d $replica_id $i_job]
#outputname $job_output_root
outputname [ format ${output_root}_combined${lastJobID}.job%04d 0 $lastJobID ]

set prefix_list {}

set size [ expr ${num_images} * ${num_swarms} ]

for {set iRep 0} {$iRep < $size} {incr iRep} {
    set prefix_list [ lappend prefix_list [ format $output_root.job%04d $iRep $lastJobID  ] ]
}

set combine_conf ""

set abfBlock 0

set filestream [open $pathCV_file]
while {[gets $filestream line] >= 0} {
    
    if {[regexp "^ *abf *\{ *$" $line] == 1} {
        set abfBlock 1
    }
    
    if { [ expr $abfBlock == 1 ] && [ regexp "^ *\} *$" $line ] == 1 } {
        append combine_conf "
    inputPrefix \{ ${prefix_list} 
        \}
\} 
"
        set abfBlock 0
        continue
    } 
    
    if { [ expr $abfBlock == 1 ] && [ regexp "shared" $line ] == 1 } { 
        append combine_conf "shared off\n"
        continue
    }
    
    if {[regexp OUTPATH $line] == 1} {
        set old_line $line
        set line [ string map [ list OUTPATH "${baseOutput}" ] "${old_line}" ]
    }

    append combine_conf "$line\n"
    
}

close $filestream

puts "Combine Conf: ${combine_conf} ;;;"

set filestream [open "${pathCV_file}_tmp" w]
puts $filestream "${combine_conf}"
close $filestream

colvarsConfig "${pathCV_file}_tmp"
#cv config ${combine_conf}


# Random seed
seed [expr int(0*srand(int(100000*rand()) + 100*$replica_id) + 100000*rand())]


source $namd_config_file
langevinTemp $temperature
firsttimestep $i_step

run $num_eABF_steps

