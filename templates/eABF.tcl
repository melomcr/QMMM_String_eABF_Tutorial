
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



set combine_conf ""

set filestream [open $pathCV_file]
while {[gets $filestream line] >= 0} {

    if {[regexp OUTPATH $line] == 1} {
        set old_line $line
        set line [ string map [ list OUTPATH "${baseOutput}" ] "${old_line}" ]
    }

    append combine_conf "$line\n"

}

close $filestream

puts "Combine Conf: ${combine_conf} ;;;"

set filestream [open "${pathCV_file}_eABF_tmp" w]
puts $filestream "${combine_conf}"
close $filestream

colvarsConfig "${pathCV_file}_eABF_tmp"

#colvarsConfig $pathCV_file

set rank [myReplica]
set num_replicas [numReplicas]
set num_swarms [expr $num_replicas / $num_images]
set image_rank [expr int($rank / $num_swarms)]
set image_master [expr $image_rank * $num_swarms]
set swarm_rank [expr $rank % $num_swarms]

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
set job_output_root [format $output_root.job%04d $replica_id $i_job]
outputname $job_output_root

# Random seed
seed [expr int(0*srand(int(100000*rand()) + 100*$replica_id) + 100000*rand())]


source $namd_config_file
langevinTemp $temperature
firsttimestep $i_step

run $num_eABF_steps
incr i_step $num_eABF_steps

# Output the new images and Tcl restart file
set output_base [format "$job_output_root.image%04d.iter%04d" $image_rank $i_iter]
incr i_iter

output $output_base
set rfile [open [format $output_root.restart.tcl $replica_id] "w"]
puts $rfile [list set i_job [expr $i_job + 1]]
puts $rfile [list set i_iter $i_iter]
puts $rfile [list set i_step $i_step]
puts $rfile [list colvarsInput $job_output_root.restart.colvars.state]
close $rfile

