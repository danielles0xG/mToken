// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import "@src/mToken.sol";
contract mTokenDeploy is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        uint256 _initialSupply = 1_000_000_000 * 5 * 1e18; // 5 billion
        uint96 interestRate = 1000; // 10%  bp
        mToken token = new mToken("mToken","mTKN",_initialSupply,interestRate);
        vm.stopBroadcast();
    }
}
