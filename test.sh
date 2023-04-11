if [[ $1 -eq 1 ]]; 
then
    forge snapshot --snap gas1.txt # Create snapshot
elif [[ $1 -eq 2 ]];
then
    forge test -vvvv #--match-test testAddAssembly
else
    forge snapshot --diff gas1.txt # Compare to snapshot
fi
