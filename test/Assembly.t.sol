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
    function testFuzz_AddAssembly(uint256 x, uint256 y) public {
        // Use uint248 to reduce the value range of x and y.
        // Or use assume in testFuzz_addSolidity to check the range.
        uint256 result = ass.addTestAssembly(x, y);
        unchecked{
            assertEq(uint256(x) + uint256(y), result);
        }
    }
    function testFuzz_AddSolidity(uint256 x, uint256 y) public {
        vm.assume(x < (2 ** 255));
        vm.assume(y < (2 ** 255));
        uint256 result = ass.addTestSolidity(x, y);
        assertEq(x + y, result);
    }
    function testFuzz_SetAssembly(uint256 x) public {
        uint256 result = ass.setWithAssembly(x);
        assertEq(x, result);
    }
    function testFuzz_SetSolidity(uint256 x) public {
        uint256 result = ass.setWithSolidity(x);
        assertEq(x, result);
    }

    function testFuzz_sumSolidity(uint256[] memory data) public {
        ass.sumSolidity(data);
    }
    function testFuzz_sumHalfAssembly(uint256[] memory data) public {
        ass.sumHalfAssembly(data);
    }
    function testFuzz_sumAssembly(uint256[] memory data) public {
        ass.sumAssembly(data);
    }
}



















