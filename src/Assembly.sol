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
      unchecked{
        return x + y;
      }
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
    function sumSolidity(uint256[] memory data) public pure returns (uint256 sum) {
        for (uint256 i=0; i<data.length; ++i){
            unchecked{
                sum += data[i];
            }
        }
    }
    function sumHalfAssembly(uint256[] memory data) public pure returns (uint256 sum) {
        for (uint256 i=0; i<data.length; ++i){
            assembly{
                sum := add(sum, mload(add(add(data, 0x20), mul(i, 0x20))))
            }
        }
    }
    function sumAssembly(uint256[] memory data) public pure returns (uint256 sum){
        assembly{
            let len := mload(data)
            let dataElementLocation := add(data, 0x20)
            for
                { let end := add(dataElementLocation, mul(len, 0x20)) }
                lt(dataElementLocation, end)
                { dataElementLocation := add(dataElementLocation, 0x20) }
            {
                sum := add(sum, mload(dataElementLocation))
            }
        }
    }
}
