mol new 1X1Z
set sel [atomselect 0 "(protein and chain A)"]
$sel writepdb enzyme.pdb
exit

