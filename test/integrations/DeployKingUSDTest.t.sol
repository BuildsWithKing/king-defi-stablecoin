// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployKingUSD} from "script/DeployKingUSD.s.sol";
import {KingUSD} from "src/KingUSD.sol";

contract DeployKingUSDTest is Test {
    DeployKingUSD public deployer;
    KingUSD public kingUSD;

    address public immutable USER = makeAddr("USER");
    uint256 public constant INITIAL_SUPPLY = 10000e18;

    function setUp() public {
        deployer = new DeployKingUSD();
        kingUSD = deployer.run();
    }

    // ================================== Constructor's Test ======================================
    function testConstructorInitializesCorrectly() public view {
        string memory name = "KingUSD";
        string memory symbol = "KUSD";

        assertEq(keccak256(abi.encodePacked(kingUSD.name())), keccak256(abi.encodePacked(name)));
        assertEq(keccak256(abi.encodePacked(kingUSD.symbol())), keccak256(abi.encodePacked(symbol)));
        assertEq(kingUSD.totalSupply(), 0);
    }

    // ==================================== Mint Function's Test ===================================
    function testMint_Succeeds() public {
        kingUSD.mint(address(this), INITIAL_SUPPLY);

        assertEq(kingUSD.totalSupply(), INITIAL_SUPPLY);
        assertEq(kingUSD.balanceOf(address(this)), INITIAL_SUPPLY);
    }

    function testMint_RevertsKingUSD__ZeroAddress() public {
        vm.expectRevert(KingUSD.KingUSD__ZeroAddress.selector);
        kingUSD.mint(address(0), INITIAL_SUPPLY);
    }

    function testMint_RevertsKingUSD__AmountMustBeGreaterThanZero() public {
        vm.expectRevert(KingUSD.KingUSD__AmountMustBeGreaterThanZero.selector);
        kingUSD.mint(USER, 0);
    }

    function testFuzzMint_RevertsForNonEngineAddress(address account) public {
        vm.assume(account != address(this));

        vm.expectRevert();
        vm.prank(account);
        kingUSD.mint(account, INITIAL_SUPPLY);
    }

    // ===================================== Burn Function's Test ==================================
    function testBurn_Succeeds() public {
        kingUSD.mint(address(this), INITIAL_SUPPLY);

        uint256 amount = 1000e18;
        kingUSD.burn(amount);

        assertEq(kingUSD.totalSupply(), INITIAL_SUPPLY - amount);
        assertEq(kingUSD.balanceOf(address(this)), INITIAL_SUPPLY - amount);
    }

    function testBurn_RevertKingUSD__AmountMustBeGreaterThanZero() public {
        vm.expectRevert(KingUSD.KingUSD__AmountMustBeGreaterThanZero.selector);
        kingUSD.burn(0);
    }

    function testBurn_RevertsKingUSD__BalanceTooLow() public {
        vm.expectRevert(KingUSD.KingUSD__BalanceTooLow.selector);
        kingUSD.burn(INITIAL_SUPPLY);
    }

    function testFuzzBurn_RevertsForNonEngineAddress(address account) public {
        vm.assume(account != address(this));

        vm.expectRevert();
        vm.prank(account);
        kingUSD.burn(INITIAL_SUPPLY);
    }
}