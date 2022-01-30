// SPDX-License-Identifier: Unlicense
// Includes code modified from Gnosis https://github.com/gnosis/delegate-registry.git
pragma solidity 0.8.10;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {IArbitrable} from "./IArbitrable.sol";
import {IArbitrator} from "./IArbitrator.sol";

interface IWETH {
    function transfer(address, uint256) external;

    function deposit() external payable;
}

contract Reps is ERC721, ReentrancyGuard, IArbitrable {
    //===== Structs =====//

    struct Dispute {
        uint256 id;
        address creator;
    }

    //===== State =====//
    // The first key is the delegator and the second key an id.
    // The value is the id of the Rep NFT.
    mapping(address => mapping(bytes32 => uint256)) public delegation;

    uint256 public repCount;
    mapping(uint256 => string) private _promiseURIs;
    mapping(uint256 => bytes32) private _promiseHashes;
    mapping(uint256 => uint256) private _checkpointTimes;
    mapping(uint256 => uint256) private _claimable;
    mapping(uint256 => uint256) private _streamPools;
    mapping(uint256 => uint256) private _streamRates;
    mapping(uint256 => address) private _arbitrators;
    mapping(uint256 => Dispute) private _repDisputes;
    mapping(uint256 => uint256) private _disputeReps;

    address public immutable weth;

    //===== Events =====//

    event TransferETH(address to, uint256 value, bool success);

    event Checkpoint(uint256 rep, uint256 claimable, uint256 streaming);

    // Using these events it is possible to process the events to build up reverse lookups.
    // The indeces allow it to be very partial about how to build this lookup (e.g. only for a specific rep).
    event SetRep(
        address indexed delegator,
        bytes32 indexed id,
        uint256 indexed rep
    );
    event ClearRep(
        address indexed delegator,
        bytes32 indexed id,
        uint256 indexed rep
    );

    //===== Constructor =====//

    constructor(
        string memory name,
        string memory symbol,
        address weth_
    ) ERC721(name, symbol) {
        weth = weth_;
    }

    //===== External Functions =====//

    /**
      @notice Creates a new Rep NFT.

      @param owner The initial owner of the Rep NFT
      @param promiseURI Universal resource identifier for the Rep's promise text
      @param promiseHash_ A keccak256 hash of the content stored in/at the promise URI
      @param arbitrator Arbitrator that will handle challenges for this rep
     */
    function newRep(
        address owner,
        string memory promiseURI,
        bytes32 promiseHash_,
        address arbitrator
    ) external returns (uint256) {
        repCount += 1;
        _promiseURIs[repCount] = promiseURI;
        _promiseHashes[repCount] = promiseHash_;
        _arbitrators[repCount] = arbitrator;
        _mint(owner, repCount);
        return repCount;
    }

    /**
      @notice Sets a rep for the msg.sender and a specific id.
      The combination of msg.sender and the id can be seen as a unique key.

      @param id Id for which the delegate should be set
      @param rep Id of the Rep NFT
     */
    function setRep(bytes32 id, uint256 rep) external payable repExists(rep) {
        require(ownerOf[rep] != msg.sender, "Can't delegate to self");
        uint256 currentRep = delegation[msg.sender][id];
        require(rep != currentRep, "Already delegated to this rep");

        // Update delegation mapping
        delegation[msg.sender][id] = rep;
        if (msg.value > 0) boostEthFor(rep);

        if (currentRep != 0) {
            emit ClearRep(msg.sender, id, currentRep);
        }

        emit SetRep(msg.sender, id, rep);
    }

    /** 
      @notice Clears a rep for the msg.sender and a specific id.
      The combination of msg.sender and the id can be seen as a unique key.
      
      @param id Id for which the rep should be set
     */
    function clearRep(bytes32 id) external {
        uint256 currentRep = delegation[msg.sender][id];
        require(currentRep != 0, "No rep set");

        // update delegation mapping
        delegation[msg.sender][id] = 0;

        emit ClearRep(msg.sender, id, currentRep);
    }

    /**
      @notice Claim ETH or WETH for the current owner of a Rep NFT

      @dev Claiming for a rep with owner address(0) will send to address(0),
      but there's no way to get that eth back anyway, so no harm done.
     */
    function claimFor(uint256 rep) external repExists(rep) {
        _newCheckpoint(rep);
        address claimee = ownerOf[rep];
        uint256 value = _claimable[rep];
        _claimable[rep] = 0;
        _transferETHOrWETH(claimee, value);
    }

    /**
      @notice Accuse the owner of a Rep NFT of breaking their promise by creating a dispute in 
      that rep's arbitrator contract.
     */
    function dispute(uint256 rep) external payable returns (uint256 id) {
        require(_repDisputes[rep].creator == address(0), "Already disputed");
        address arbitrator = _arbitrators[rep];
        id = IArbitrator(arbitrator).createDispute{value: msg.value}(2, "");
        _repDisputes[rep] = Dispute(id, msg.sender);
        _disputeReps[id] = rep;
    }

    /**
      @notice Resolve a dispute. 
      If ruling is 1, burns the Rep NFT and sends remaining payment to the challenger.

      @dev Callable only by a Rep NFT's arbitrator in accordance with the Arbitrator/Arbitrable interfaces.

      @dev No need to reset state around stream pools, disputes, and so on if ruling is 1: burning the NFT is enough.

      @param ruling 0 -- refused to arbitrate, 1 -- fired, 2 -- not fired
     */
    function rule(uint256 disputeId, uint256 ruling) external {
        uint256 rep = _disputeReps[disputeId];
        require(rep != 0, "Non-existant rep");
        address arbitrator = _arbitrators[rep];
        require(arbitrator == msg.sender, "Arbitrator only");
        if (ruling == 1) {
            // you're fired
            _burn(rep);
            // send remaining rep funds to dispute creator
            uint256 amount = _claimable[rep] + _streamPools[rep];
            address creator = _repDisputes[rep].creator;
            _transferETHOrWETH(creator, amount);
        } else {
            // rep is no longer disputed
            delete _repDisputes[rep];
        }
        emit Ruling(IArbitrator(arbitrator), disputeId, ruling);
    }

    function promiseHash(uint256 rep)
        external
        view
        repExists(rep)
        returns (bytes32)
    {
        return _promiseHashes[rep];
    }

    function repPaymentData(uint256 rep)
        external
        view
        repExists(rep)
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            _checkpointTimes[rep],
            _claimable[rep],
            _streamPools[rep],
            _streamRates[rep]
        );
    }

    function repDisputeData(uint256 rep)
        external
        view
        repExists(rep)
        returns (
            address,
            uint256,
            address
        )
    {
        return (
            _arbitrators[rep],
            _repDisputes[rep].id,
            _repDisputes[rep].creator
        );
    }

    //===== Public Functions =====//

    function tokenURI(uint256 rep)
        public
        view
        override
        repExists(rep)
        returns (string memory)
    {
        return _promiseURIs[rep];
    }

    /**
      @notice Add additional ETH to the payment / bounty pool for a Rep.

      @dev If the rep's owner is address(0), eth paid here is lost!
      This may be a bad design choice, but it may not be, and it is simple.
     */
    function boostEthFor(uint256 rep) public payable {
        _newCheckpoint(rep);
        _streamRates[rep] = _streamPools[rep];
    }

    /**
      @notice Predict claimable ETH for a Rep NFT owner at a given time

      @dev Stream rate is such that 100% would be claimable after 365 solidity days,
      if nothing is added to the pool. Adding to the pool increases the rate.
     */
    function claimableAt(uint256 rep, uint256 timestamp)
        public
        view
        returns (uint256)
    {
        if (timestamp < _checkpointTimes[rep]) return 0;
        uint256 timePassed = timestamp - _checkpointTimes[rep];
        uint256 claimable = (_streamRates[rep] * timePassed) / 365 days;
        if (claimable > _streamPools[rep]) {
            return _streamPools[rep];
        }
        return claimable;
    }

    //===== Private Functions =====//

    function _newCheckpoint(uint256 rep) private {
        uint256 timePassed = block.timestamp - _checkpointTimes[rep];
        uint256 newClaimable = (_streamRates[rep] * timePassed) / 365 days;
        if (newClaimable > _streamPools[rep] + msg.value)
            newClaimable = _streamPools[rep] + msg.value;
        _checkpointTimes[rep] = block.timestamp;
        _claimable[rep] = _claimable[rep] + newClaimable;
        _streamPools[rep] = _streamPools[rep] + msg.value - newClaimable;
        emit Checkpoint(rep, _claimable[rep], _streamPools[rep]);
    }

    function _transferETHOrWETH(address to, uint256 value)
        private
        nonReentrant
        returns (bool)
    {
        // try to transfer ETH with some gas
        (bool success, ) = to.call{value: value, gas: 30000}("");
        // if it fails, transfer wrapped ETH
        if (!success) {
            IWETH(weth).deposit{value: value}();
            IWETH(weth).transfer(to, value);
        }
        emit TransferETH(to, value, success);
        return success;
    }

    //===== Modifiers =====//

    modifier repExists(uint256 rep) {
        require(ownerOf[rep] != address(0), "Non-existant rep");
        _;
    }
}
