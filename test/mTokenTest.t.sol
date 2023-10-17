// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./helpers/BaseTest.sol";

contract mTokenTest is BaseTest {
    event Transfer(address, address, uint256);
    event AcrruedInterestEvent(address, uint256, uint256);
    event UpdateInterestEvent(uint96);
    event MintEvent(uint256);

    function setUp() public override {
        super.setUp();
    }

    function test_mint() public {
        token.mint(_wallet1.addr, 1 ether);
        assertGt(token.balanceOf(_wallet1.addr), 0, "mToken mint fail");
    }

    function test_transfer() public {
        uint256 transferAmount = 0.5 ether;
        token.mint(_wallet1.addr, 1 ether);

        vm.startPrank(_wallet1.addr);
        token.transfer(_wallet2.addr, transferAmount);

        assertEq(token.balanceOf(_wallet1.addr), transferAmount);
        assertEq(token.balanceOf(_wallet2.addr), transferAmount);
    }

    function test_transferFrom() public {
        uint256 transferAmount = 0.5 ether;
        token.mint(_wallet1.addr, 1 ether);

        vm.prank(_wallet1.addr);
        token.approve(address(this), 1 ether);

        token.transferFrom(_wallet1.addr, _wallet2.addr, transferAmount);
        assertEq(token.balanceOf(_wallet1.addr), transferAmount);
        assertEq(token.balanceOf(_wallet2.addr), transferAmount);
    }

    function test_burn() public {
        uint256 burnAmount = 1 ether;
        token.mint(_wallet1.addr, burnAmount);
        vm.startPrank(_wallet1.addr);
        token.burn(burnAmount);
        assertEq(token.balanceOf(_wallet1.addr), 0);
    }

    function test_fuzz_interest_rate(uint96 _newInterestRate) public {
        vm.assume(_newInterestRate > 0 && _newInterestRate < 10_000);
        uint256 transferAmount = 0.5 ether;
        uint256 period = 365 days;
        uint256 principal = 1 ether;

        token.mint(_wallet1.addr, principal);
        vm.warp(block.timestamp + period); // a year after

        vm.startPrank(_wallet1.addr);
        uint256 earnedBeforeTransfer = token.earned();

        token.transfer(_wallet2.addr, transferAmount);
        assertEq(token.balanceOf(_wallet1.addr), earnedBeforeTransfer + transferAmount);
        assertEq(token.balanceOf(_wallet2.addr), transferAmount);
        vm.stopPrank();

        vm.expectEmit(true, false, false, false);
        emit UpdateInterestEvent(_newInterestRate);
        token.updateIR(_newInterestRate);

        uint256 pastBalance = token.balanceOf(_wallet2.addr);
        vm.warp(block.timestamp + 365 days); // another year after
        vm.startPrank(_wallet2.addr);
        uint256 earned = token.earned();
        token.transfer(_wallet3.addr, 0.01 ether); // wallet2 accrues interest on transfer
        assertEq(token.balanceOf(_wallet2.addr), pastBalance + earned - 0.01 ether);
    }

    /// @notice update on Transfer to accrue 10% interest in 1 year
    function test_accrueOnTransfer() public {
        uint256 transferAmount = 0.5 ether;
        token.mint(_wallet1.addr, 1 ether);
        vm.warp(block.timestamp + 365 days);

        vm.startPrank(_wallet1.addr);
        uint256 earnedBeforeTransfer = token.earned();

        // comparing simple interest vs compund interest
        assertGt(token.balanceOf(_wallet1.addr) + earnedBeforeTransfer, token.balanceOf(_wallet1.addr) * interestRate / 10_000);

        token.transfer(_wallet2.addr, transferAmount);

        assertEq(token.balanceOf(_wallet1.addr), earnedBeforeTransfer + transferAmount);
        assertEq(token.balanceOf(_wallet2.addr), transferAmount);
    }

    /// @notice update on TransferFrom to accrue 10% interest in 1 year
    function test_accrue_on_transfer_from() public {
        uint256 transferAmount = 0.5 ether;
        token.mint(_wallet1.addr, 1 ether);
        vm.warp(block.timestamp + 365 days);

        vm.startPrank(_wallet1.addr);
        uint256 earnedBeforeTransfer = token.earned();
        token.approve(address(this), transferAmount);
        vm.stopPrank();

        vm.expectEmit(true, true, true, false);
        emit Transfer(address(0), _wallet1.addr, earnedBeforeTransfer); // mint to wallet1
        emit AcrruedInterestEvent(_wallet1.addr, earnedBeforeTransfer, block.timestamp);
        emit Transfer(_wallet1.addr, _wallet2.addr, transferAmount);

        token.transferFrom(_wallet1.addr, _wallet2.addr, transferAmount);

        assertEq(token.balanceOf(_wallet1.addr), earnedBeforeTransfer + transferAmount);
        assertEq(token.balanceOf(_wallet2.addr), transferAmount);
    }

    /// @notice User try to accrue twice on same block after 1 year
    function test_double_accrual_in_same_block() public {
        uint256 transferAmount = 0.5 ether;
        token.mint(_wallet1.addr, 1 ether);
        vm.warp(block.timestamp + 365 days);

        vm.startPrank(_wallet1.addr);
        uint256 earnedBeforeTransfer = token.earned();
        uint256 pastBalance = token.balanceOf(_wallet1.addr);

        // User tries to accrue twice on same block
        token.transfer(_wallet2.addr, transferAmount);
        assertEq(token.balanceOf(_wallet1.addr), earnedBeforeTransfer + pastBalance - transferAmount);
        token.transfer(_wallet3.addr, transferAmount);

        assertEq(token.balanceOf(_wallet1.addr), earnedBeforeTransfer);
        assertEq(token.balanceOf(_wallet2.addr), transferAmount);
    }

    /// @dev Accrue interest up to 25 years
    function test_fuzz_accrual_period(uint256 _period) public {
        vm.assume(_period > block.timestamp && _period < block.timestamp + (365 days * 25));
        uint256 transferAmount = 0.5 ether;
        token.mint(_wallet1.addr, 1 ether);
        vm.warp(block.timestamp + _period);

        vm.startPrank(_wallet1.addr);
        uint256 earnedBeforeTransfer = token.earned();

        token.approve(address(this), transferAmount);
        vm.stopPrank();

        token.transferFrom(_wallet1.addr, _wallet2.addr, transferAmount);
        assertEq(token.balanceOf(_wallet1.addr), earnedBeforeTransfer + transferAmount);
        assertEq(token.balanceOf(_wallet2.addr), transferAmount);
    }

    /// @dev User tries to accrue interest by transfering to itself
    function test_revert_transfer_to_same_sender() public {
        vm.expectRevert("Invalid Tranfer");
        token.transferFrom(address(this), address(this), 1 ether);
    }
    /// @dev User tries to accrue interest by transfering to zero amount

    function test_revert_transfer_zero_amount() public {
        vm.expectRevert("Invalid Tranfer");
        token.transfer(address(this), 0);
    }
    /// @dev test only admin

    function test_revert_when_caller_not_admin() public {
        vm.expectRevert("Only admin");
        vm.prank(address(1));
        token.updateIR(2000);
    }

    /// @dev new rate is greater than basis points denominator
    function test_revert_update_wrong_interest_rate() public {
        vm.expectRevert("Invalid interest rate");
        token.updateIR(11_000);
    }

    /// @dev No eth supported
    function test_revert_on_eth_sent() public {
        vm.expectRevert("Unsupported");
        (bool sent,) = address(token).call{value: 1}("");
        require(sent);
    }
}
