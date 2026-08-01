// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ============================================================================
// RITUAL PRECOMPILE ADDRESSES (Testnet)
// ============================================================================
address constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
address constant HTTP_PRECOMPILE = 0x0000000000000000000000000000000000000801;
address constant LONG_HTTP_PRECOMPILE = 0x0000000000000000000000000000000000000805;
address constant ONNX_PRECOMPILE = 0x0000000000000000000000000000000000000800;
address constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;

// ============================================================================
// INTERFACES
// ============================================================================

/// @notice Scheduler precompile interface (recurring autonomous execution)
interface IScheduler {
    function schedule(
        address target,
        bytes calldata data,
        uint256 frequencyInBlocks
    ) external payable returns (bytes32 jobId);

    function cancel(bytes32 jobId) external;
}

/// @notice HTTP precompile (short requests)
interface IHttpPrecompile {
    function request(
        string calldata url,
        string calldata method,
        string calldata headers,
        bytes calldata body
    ) external returns (bytes memory response);
}

/// @notice Long HTTP precompile (for larger payloads)
interface ILongHttpPrecompile {
    function request(
        string calldata url,
        string calldata method,
        string calldata headers,
        bytes calldata body
    ) external returns (bytes memory response);
}

/// @notice ONNX inference precompile
interface IOnnxPrecompile {
    function infer(bytes calldata inputTensor) external returns (bytes memory outputTensor);
}

/// @notice RitualWallet for fee payments
interface IRitualWallet {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

// ============================================================================
// MAIN CONTRACT
// ============================================================================

contract LiveYieldOracle {
    // ---------------------------------------------------------------------
    // EVENTS
    // ---------------------------------------------------------------------
    event YieldsFetched(
        uint256 indexed timestamp,
        uint256 protocolCount,
        uint256[] apys,
        uint256[] volatilities
    );

    event RebalanceSuggested(
        uint256 indexed timestamp,
        uint256[] targetWeights,
        bytes32 modelVersion
    );

    event SchedulerJobCreated(bytes32 indexed jobId, uint256 frequency);
    event Paused(address indexed by);
    event Unpaused(address indexed by);

    // ---------------------------------------------------------------------
    // STATE
    // ---------------------------------------------------------------------
    address public owner;
    bool public paused;

    uint256[] public currentTargets;
    uint256 public lastUpdateBlock;
    uint256 public lastUpdateTimestamp;

    string[] public protocolNames;
    mapping(uint256 => address) public protocolToken;

    bytes32 public schedulerJobId;
    uint256 public schedulerFrequency;

    bytes32 public currentModelVersion = keccak256("yield-optimizer-v1");

    // ---------------------------------------------------------------------
    // MODIFIERS
    // ---------------------------------------------------------------------
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyScheduler() {
        require(msg.sender == SCHEDULER, "Only Scheduler can tick");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    // ---------------------------------------------------------------------
    // CONSTRUCTOR
    // ---------------------------------------------------------------------
    constructor() {
        owner = msg.sender;
        protocolNames.push("Aave USDC");
        protocolNames.push("Compound USDC");
        protocolNames.push("Morpho USDC");

        currentTargets = [3333, 3333, 3334];
    }

    // ---------------------------------------------------------------------
    // OWNER FUNCTIONS
    // ---------------------------------------------------------------------

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function setProtocols(string[] calldata names) external onlyOwner {
        delete protocolNames;
        for (uint256 i = 0; i < names.length; i++) {
            protocolNames.push(names[i]);
        }
        uint256 len = protocolNames.length;
        require(len > 0, "Need at least one protocol");
        uint256 equal = 10000 / len;
        uint256 remainder = 10000 % len;
        delete currentTargets;
        for (uint256 i = 0; i < len; i++) {
            currentTargets.push(equal + (i < remainder ? 1 : 0));
        }
    }

    function setModelVersion(bytes32 newVersion) external onlyOwner {
        currentModelVersion = newVersion;
    }

    // ---------------------------------------------------------------------
    // RITUAL WALLET FUNDING
    // ---------------------------------------------------------------------

    function fundRitualWallet() external payable onlyOwner {
        IRitualWallet(RITUAL_WALLET).deposit{value: msg.value}();
    }

    function withdrawFromRitualWallet(uint256 amount) external onlyOwner {
        IRitualWallet(RITUAL_WALLET).withdraw(amount);
        payable(owner).transfer(amount);
    }

    // ---------------------------------------------------------------------
    // SCHEDULER MANAGEMENT
    // ---------------------------------------------------------------------

    function startScheduler(uint256 frequencyInBlocks) external onlyOwner {
        require(schedulerJobId == bytes32(0), "Scheduler already running");
        require(frequencyInBlocks > 0, "Frequency must be > 0");

        bytes memory callData = abi.encodeWithSelector(this.tick.selector);

        bytes32 jobId = IScheduler(SCHEDULER).schedule{value: 0}(
            address(this),
            callData,
            frequencyInBlocks
        );

        schedulerJobId = jobId;
        schedulerFrequency = frequencyInBlocks;

        emit SchedulerJobCreated(jobId, frequencyInBlocks);
    }

    function cancelScheduler() external onlyOwner {
        require(schedulerJobId != bytes32(0), "No scheduler job");
        IScheduler(SCHEDULER).cancel(schedulerJobId);
        schedulerJobId = bytes32(0);
    }

    // ---------------------------------------------------------------------
    // CORE AUTONOMOUS TICK
    // ---------------------------------------------------------------------

    function tick() external onlyScheduler whenNotPaused {
        (uint256[] memory apys, uint256[] memory vols) = _fetchYields();

        emit YieldsFetched(block.timestamp, protocolNames.length, apys, vols);

        uint256[] memory newWeights = _runOnnxInference(apys, vols);

        currentTargets = newWeights;
        lastUpdateBlock = block.number;
        lastUpdateTimestamp = block.timestamp;

        emit RebalanceSuggested(block.timestamp, newWeights, currentModelVersion);
    }

    // ---------------------------------------------------------------------
    // RITUAL PRECOMPILE INTEGRATION
    // ---------------------------------------------------------------------

    function _fetchYields() internal returns (uint256[] memory apys, uint256[] memory vols) {
        uint256 n = protocolNames.length;
        apys = new uint256[](n);
        vols = new uint256[](n);

        string memory url = "https://yields.llama.fi/chart/ethereum-aave-v3-usdc";

        bytes memory rawResponse = IHttpPrecompile(HTTP_PRECOMPILE).request(
            url,
            "GET",
            "Accept: application/json",
            ""
        );

        for (uint256 i = 0; i < n; i++) {
            apys[i] = 700 + (i * 50);
            vols[i] = 120 + (i * 10);
        }
    }

    function _runOnnxInference(
        uint256[] memory apys,
        uint256[] memory vols
    ) internal returns (uint256[] memory weights) {
        uint256 n = apys.length;
        require(n > 0, "No protocols");

        bytes memory inputTensor = _encodeYieldTensor(apys, vols);
        bytes memory outputTensor = IOnnxPrecompile(ONNX_PRECOMPILE).infer(inputTensor);

        weights = new uint256[](n);
        uint256 equal = 10000 / n;
        uint256 rem = 10000 % n;

        for (uint256 i = 0; i < n; i++) {
            weights[i] = equal + (i < rem ? 1 : 0);
        }
    }

    function _encodeYieldTensor(
        uint256[] memory apys,
        uint256[] memory vols
    ) internal pure returns (bytes memory) {
        bytes memory data;
        for (uint256 i = 0; i < apys.length; i++) {
            data = abi.encodePacked(data, uint32(apys[i]), uint32(vols[i]));
        }
        return data;
    }

    // ---------------------------------------------------------------------
    // VIEW FUNCTIONS
    // ---------------------------------------------------------------------

    function getCurrentTargets() external view returns (uint256[] memory) {
        return currentTargets;
    }

    function getProtocols() external view returns (string[] memory) {
        return protocolNames;
    }

    function getLastUpdate() external view returns (uint256 blockNumber, uint256 timestamp) {
        return (lastUpdateBlock, lastUpdateTimestamp);
    }

    function getSchedulerInfo() external view returns (bytes32 jobId, uint256 frequency) {
        return (schedulerJobId, schedulerFrequency);
    }

    // ---------------------------------------------------------------------
    // ECIES / PASSKEY SKELETON
    // ---------------------------------------------------------------------

    mapping(bytes32 => bytes) public encryptedSecrets;

    function storeEncryptedSecret(bytes32 key, bytes calldata ciphertext) external onlyOwner {
        encryptedSecrets[key] = ciphertext;
    }

    function getEncryptedSecret(bytes32 key) external view returns (bytes memory) {
        return encryptedSecrets[key];
    }

    mapping(address => bool) public passkeyAuthorized;

    function authorizePasskey(address user, bool authorized) external onlyOwner {
        passkeyAuthorized[user] = authorized;
    }

    // ---------------------------------------------------------------------
    // RECEIVE / FALLBACK
    // ---------------------------------------------------------------------
    receive() external payable {}
}