#!/bin/bash


echo "Number of images: $1"
echo "PSF file: $2"

echo "Using CATDCD at $3"

for (( i = 0; i < ${1}; i+=1))
do

    $3 -o string_${i}.pdb -otype pdb -stype psf -s ${2} -namdbin string_${i}.coor 

done


