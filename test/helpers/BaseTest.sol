// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console, Vm} from "forge-std/Test.sol";
import {mToken} from "@src/mToken.sol";

contract BaseTest is Test {
    mToken public token;
    uint96 public interestRate;

    function setUp() public virtual {
        uint256 _initialSupply = 1_000_000_000 * 5 * 1e18; // 5 billion
        interestRate = 1000; // 10%  bp
        token = new mToken("mToken","mTKN",_initialSupply,interestRate);
    }

    Vm.Wallet internal _wallet1 = vm.createWallet("wallet::user1");
    Vm.Wallet internal _wallet2 = vm.createWallet("wallet::user2");
    Vm.Wallet internal _wallet3 = vm.createWallet("wallet::user3");
    Vm.Wallet internal _wallet4 = vm.createWallet("wallet::user4");
    Vm.Wallet internal _wallet5 = vm.createWallet("wallet::user5");
}
