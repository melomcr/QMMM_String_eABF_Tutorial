
source string_param.conf

replicaBarrier
set replica_id [myReplica]
source $namd_config_file

if { [info exists iters_per_output ] == 0 } {
	set iters_per_output 1
}
if { [info exists num_equil_steps] == 0 } {
	set num_equil_steps 50000
}
if { [info exists num_equil_stages] == 0 } {
	set num_equil_stages 5
}
if { [info exists equil_stage_expon] == 0 } {
	set equil_stage_expon 1
}
if { [info exists restart] == 0 } {
	set restart no
}
if { [info exists swarms_force_constant_min] == 0} {
    set swarms_force_constant_min 1
}
if { [info exists bias_param] == 0} {
    set bias_param 1
}
set equil_steps_per_stage [expr int($num_equil_steps / $num_equil_stages)]

# Find the image master
set image_rank [myReplica]
set num_replicas [numReplicas]

#set image_index [ expr ${image_rank}/${num_swarms} ]
set image_index ${image_rank}

# Set pi
set pi 3.1415926535897931

if { $restart } {
	source [format $output_root.restart.tcl $replica_id]
} else {
	set i_job 0
	set i_iter 0
	set i_step 0
}
if { $i_job == 0 } {
	if [info exists bincoor_file] {
		bincoordinates [format $bincoor_file $image_index]
# 		bincoordinates [format $bincoor_file $image_rank]
	}
	if [info exists xsc_file] {
		extendedSystem [format $xsc_file $image_index]
# 		extendedSystem [format $xsc_file $image_rank]
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

# Reads the colvars_##.conf file
# Swarms colvars will have a name that starts with "swarms_"
# Angle/dihedral colvars should start with "swarms_angle_"
proc read_colvars_conf { fname } {
	global swarm_colvars
	set fp [open $fname r]
	set lines [split [read $fp] "\n"]
	foreach line $lines {
		# Assign entries by colvar name
		set trimmed [string trim $line]
		set fields [split $trimmed]
		if {[lindex $fields 0] == "name" && [string range [lindex $fields 1] 0 5] == "swarms"} {
			set name_fields [split [lindex $fields 1] _]
			if {[lindex $name_fields 1] == "angle"} {
				set swarm_colvars([lindex $fields 1]) 1
			} else {
				set swarm_colvars([lindex $fields 1]) 0
			}
		}
	}
	close $fp
}

proc update_current_colvars { } {
	global swarm_colvars current_colvars pi	rank
	foreach { key is_angle } [array get swarm_colvars] {
		set val [colvarvalue $key]
		if $is_angle {
			set current_colvars($key) [list [expr sin($val * $pi / 180)] [expr cos($val * $pi / 180)]]
		} else {
			set current_colvars($key) $val
		}
	}
}

proc update_centers_from_drift { } {
	global drift
	foreach {key pos} [array get drift] {
		puts "Updating bias_$key"
		# Parse vector coordinates
		if { [llength $pos] > 1 } {
			set config "centers ( "
			for { set i 0 } { $i < [llength $pos] } { incr i } {
				if { $i != 0 } {
					append config ", "
				}
				append config [lindex $pos $i]
			}
			append config " )"
		} else {
			set config "centers $pos"
		}
		colvarbias changeconfig bias_$key $config
	}
}

set colvars_file [format $colvars_file $image_index]
#set colvars_file [format $colvars_file $image_rank]
colvarsConfig $colvars_file
read_colvars_conf $colvars_file

# collection_callback my_data received_data
proc binary_tree_callback { r nr offset skip data collection_callback process_callback } {
	# Use the callback only when collecting the data
	foreach i { 1 2 } {
		set p [expr 2 * $r + $i]
		if { $p < $nr } {
			set received [replicaRecv [expr ($p + $offset) * $skip]]
			set data [$collection_callback $data $received]
		}
	}
	# Now redistribute the collected and processed data
	if { $r } {
		if { ($r + 1) % 2 == 0 } {
			set p [expr ($r + 1) / 2 - 1]
		} else {
			set p [expr $r / 2 - 1]
		}
		replicaSend $data [expr ($p + $offset) * $skip]
		set data [replicaRecv [expr ($p + $offset) * $skip]]
	# The head node can process now
	} elseif { [llength [info commands $process_callback]] > 0 } {
		set data [$process_callback $data]
	}
	foreach i { 1 2 } {
		set p [expr 2 * $r + $i]
		if { $p < $nr } {
			replicaSend $data [expr ($p + $offset) * $skip]
		}
	}
	return $data
}


proc prepare_message { } {
	global current_colvars
	update_current_colvars
	return [array get current_colvars]
}

# TODO: How much performance loss by not setting all of the arrays once and then upvaring?
proc smooth_images { drifts smooth_param } {
	global num_images num_swarms
	array set drifts_array $drifts
	set smoothed [list 0 $drifts_array(0)]
	for {set i 1} {$i < ($num_images - 1)} {incr i} {
		array set left_image $drifts_array([expr $i - 1])

		array set right_image $drifts_array([expr $i + 1])
		set smooth [list]
		foreach { key val } $drifts_array($i) {
			set smooth [concat $smooth $key [list [vecadd [vecscale [expr 1.0 - $smooth_param] $val] [vecscale [expr $smooth_param / 2.0] [vecadd $left_image($key) $right_image($key)]]]]]
		}
		set smoothed [concat $smoothed [list $i $smooth]]
	}
	set smoothed [concat $smoothed [list [expr $num_images - 1] $drifts_array([expr $num_images - 1])]]
	return $smoothed
}

# TODO: How much performance loss by not setting all of the arrays once and then upvaring?
proc reparameterize_images { drifts } {
	global image_rank num_images
	array set drifts_array $drifts
	# Collect the cumulative length metric
	set arc_lengths [list 0.0]
	for { set i 1 } { $i < $num_images } { incr i } {
		array set previous $drifts_array([expr $i - 1])
		set sum 0.0
		foreach { key val } $drifts_array($i) {
			set norm [veclength [vecsub $val $previous($key)]]
			set sum [expr $sum + [expr $norm * $norm]]
		}
		set sum [expr sqrt($sum) + [lindex $arc_lengths [expr $i - 1]]]
		lappend arc_lengths $sum
	}
	# Now redistribute the images, keeping the endpoints fixed
	set reparam [list 0 $drifts_array(0)]
	for { set i 1 } { $i < [expr $num_images - 1] } { incr i } {
		set current_length [expr $i * [lindex $arc_lengths end] / ($num_images - 1)]
		# Find the correct arc-length
		for { set j 1 } { $j < [expr $num_images - 1] } { incr j } {
			if { [lindex $arc_lengths $j] > $current_length } {
				break
			}
		}
		# Use linear interpolation to propose new coordinates
		array set left_image $drifts_array([expr $j - 1])
		array set right_image $drifts_array([expr $j])
		set current [list]
		foreach { key } [array names left_image] {
			set vec [vecsub $right_image($key) $left_image($key)]
			set linear_factor [expr ($current_length - [lindex $arc_lengths [expr $j - 1]]) / ([lindex $arc_lengths $j] - [lindex $arc_lengths [expr $j - 1]])]
 			set current [concat $current $key [list [vecadd $left_image($key) [vecscale $linear_factor $vec]]]]
		}
		set reparam [concat $reparam [list $i $current]]
	}
	set reparam [concat $reparam [list [expr $num_images - 1] $drifts_array([expr $num_images - 1])]]
	return $reparam
}

# Set up the callbacks
proc sum_drifts { my_data received_data } {
	array set drifts $my_data
	foreach {key val} $received_data {
		set drifts($key) [vecadd $drifts($key) $val]
	}
	return [array get drifts]
}
proc average_smooth_reparam { data } {
	global swarm_colvars image_rank num_images num_swarms pi
	array set drifts $data
	# Average the drifts
	foreach { key is_angle } [array get swarm_colvars] {
		if $is_angle {
			set drifts($key) [expr 180 / $pi * atan2([lindex $drifts($key) 0], [lindex $drifts($key) 1])]
		} else {
			set drifts($key) [vecscale $drifts($key) [expr 1.0 / $num_swarms]]
		}
	}
	# Smooth and reparameterize
	array set new_images [binary_tree_callback $image_rank $num_images 0 1 [list $image_rank [array get drifts]] concat_images smooth_reparam_callback]
	# Only redistribute the correct image
	return $new_images($image_rank)
}
proc concat_images { my_data received_data } {
	return [concat $my_data $received_data]
}
proc smooth_reparam_callback { data } {
	global smooth_param
	set data [smooth_images $data $smooth_param]
	set data [reparameterize_images $data]
	return $data
}

# Swarm iterations
langevinTemp $temperature
firsttimestep $i_step
set target_iter [expr $i_iter + $num_iter]
while {$i_iter < $target_iter} {
	# Determine if coordinates will be written this step
	set write_output [expr ($i_iter % $iters_per_output) == 0 || $i_iter == ($target_iter - 1)]

	# Turn of the biases before the swarms
	foreach { key } [array names drift] {
		colvarbias changeconfig bias_$key "forceConstant 0.0"
	}

	# Run the individual swarms
	checkpoint
	colvarfreq $num_swarm_steps
	for {set swarm_rank 0} {$swarm_rank < $num_swarms} {incr swarm_rank} {
		revert
		run $num_swarm_steps
		if { $swarm_rank == 0 } {
			set sum_drifts [prepare_message]
		} else {
			set message [prepare_message]
			set sum_drifts [sum_drifts $sum_drifts $message]
		}
		# Output the swarms conformations
		if { $write_output } {
			set output_base [format "$job_output_root.drift%04d.iter%04d" $swarm_rank $i_iter]
			output $output_base
		}
	}
	incr i_step $num_swarm_steps

	replicaBarrier

	# Use a binary tree to distribute summed drifts to smooth/reparam
	array set drift [average_smooth_reparam $sum_drifts]

	# Equilibrate new images
	update_centers_from_drift
	colvarfreq $equil_steps_per_stage
	for { set i 1 } { $i <= $num_equil_stages } { incr i } {
		#set current_force_constant [expr pow(1.0 - ($num_equil_stages. - $i) / $num_equil_stages, $equil_stage_expon) * $swarms_force_constant]
		set current_force_constant [ expr $swarms_force_constant_min + [expr pow(1.0 - ($num_equil_stages. - $i) / $num_equil_stages, $equil_stage_expon) * $swarms_force_constant] ]
		foreach { key } [array names drift] {
			puts "Updating bias_$key"
			colvarbias changeconfig bias_$key "forceConstant $current_force_constant"
		}
		run $equil_steps_per_stage
		incr i_step $equil_steps_per_stage
	}

	# Output the new images and Tcl restart file
	set output_base [format "$job_output_root.image%04d.iter%04d" $image_rank $i_iter]
	incr i_iter
	if { $write_output } {
		output $output_base
		set rfile [open [format $output_root.restart.tcl $replica_id] "w"]
		puts $rfile [list set i_job [expr $i_job + 1]]
		puts $rfile [list set i_iter $i_iter]
		puts $rfile [list set i_step $i_step]
		puts $rfile [list colvarsInput $job_output_root.restart.colvars.state]
		close $rfile
	}
}
