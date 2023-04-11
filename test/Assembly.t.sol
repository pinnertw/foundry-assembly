// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../src/Assembly.sol";
//        assertEq(counter.number(), 1);

contract TestAssembly is Test {
    Assembly public ass;
    function setUp() public {
        ass = new Assembly();
    }
    function testAddAssembly() public {
        ass.addTestAssembly(5, 6);
    }
    function testAddSolidity() public {
        ass.addTestSolidity(5, 6);
    }
}
