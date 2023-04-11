if [[ $1 -eq 1 ]]; 
then
    forge snapshot --snap gas1.txt # Create snapshot
else
    forge snapshot --diff gas1.txt # Compare to snapshot
fi
