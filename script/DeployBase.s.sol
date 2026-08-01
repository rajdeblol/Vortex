// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {BaseVault} from "../src/BaseVault.sol";

contract DeployBase is Script {
    address constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        BaseVault vault = new BaseVault(BASE_SEPOLIA_USDC, address(0));
        console2.log("BaseVault deployed at:", address(vault));

        vm.stopBroadcast();
    }
}