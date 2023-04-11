// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

contract Assembly {
    function addTestAssembly(uint256 x, uint256 y) public pure returns(uint256){
        assembly{
            let result := add(x, y)
            mstore(0x0, result)
            return(0x0, 32)
        }
    }
    function addTestSolidity(uint256 x, uint256 y) public pure returns(uint256){
        return x + y;
    }
    function setWithAssembly(uint256 x) public pure returns (uint256){
        assembly{
            let result := x
            mstore(0x0, result)
            return(0x0, 32)
        }
    }
    function setWithSolidity(uint256 x) public pure returns (uint256){
        uint256 result = x;
        return result;
    }
}
