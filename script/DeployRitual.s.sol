// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {LiveYieldOracle} from "../src/LiveYieldOracle.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {RitualVault} from "../src/RitualVault.sol";

contract DeployRitual is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockUSDC musdc = new MockUSDC();
        console2.log("MockUSDC deployed at:", address(musdc));

        LiveYieldOracle oracle = new LiveYieldOracle();
        console2.log("LiveYieldOracle deployed at:", address(oracle));

        RitualVault vault = new RitualVault(address(musdc), address(oracle));
        console2.log("RitualVault deployed at:", address(vault));

        vm.stopBroadcast();
    }
}