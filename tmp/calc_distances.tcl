set molID [ mol new ./setup/decarboxylase.0.psf] 
mol addfile ./SMD_Data/min_smd.dcd waitfor all molid $molID 


set numFrames [molinfo $molID get numframes]

puts "Number of frames: $numFrames"

set fpCVDat [open "./tmp/cv_data.csv" w]

puts $fpCVDat "dist0,dist1,dist2,dist3" 


for {set frame 0} {$frame < $numFrames} {incr frame} { 

    animate goto $frame
    
	# Distance 0: OMP C6 <-> OMP C7
	set dist0 [ measure bond {3311 3312} molid $molID ] 

	# Distance 1: OMP C6 <-> Lys61 HZ1
	set dist1 [ measure bond {3311 1020} molid $molID ] 

	# Distance 2: OMP OA <-> Asp59 OD2
	set dist2 [ measure bond {3314 980} molid $molID ] 

	# Distance 3: OMP OB <-> Asp59 OD1
	set dist3 [ measure bond {3313 979} molid $molID ] 

	puts $fpCVDat "$dist0,$dist1,$dist2,$dist3" 

}

close $fpCVDat 

