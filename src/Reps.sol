// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {IRep, Rep, IERC20, IERC721} from "./Rep.sol";
import {IArbitrable} from "./IArbitrable.sol";
import {IArbitrator} from "./IArbitrator.sol";

interface IWETH {
    function deposit() external payable;
}

contract Reps is ERC721, ReentrancyGuard, IArbitrable {
    //===== Structs =====//

    struct Dispute {
      uint256 id;
      address creator;
    }


    //===== State =====//

    uint256 public delegationCount;
    mapping(uint256 => address[]) private _delegationTokens;
    mapping(uint256 => uint256[]) private _delegationAmounts;
    mapping(uint256 => uint256[][]) private _delegationTokenIds;
    mapping(uint256 => address) private _delegationReps;

    mapping(address => uint256) private _repCheckpointTimes;
    mapping(address => uint256) private _repClaimable;
    mapping(address => uint256) private _repStreamPools;
    mapping(address => uint256) private _repStreamRates;
    mapping(address => address) private _repArbitrators;
    mapping(address => Dispute) private _repDisputes;
    mapping(uint256 => address) private _disputeReps;

    address public immutable weth;

    //===== Events =====//

    event NewRep(
        address rep, 
        address operator, 
        address[10] tokens, 
        string promise_
    );

    event TransferETH(address to, uint256 value, bool success);

    event Checkpoint(address rep, uint256 claimable, uint256 streaming);


    //===== Constructor =====//

    constructor(
        string memory name, 
        string memory symbol, 
        address weth_
    ) ERC721(name, symbol) {
        weth = weth_;
    }


    //===== External Functions =====//

    // @param promise_ The political promise of the rep. Could be a hash + URI in the future but should emphasize brevity.
    function newRep(
        address operator, 
        address[10] calldata tokens, 
        string calldata promise_,
        address arbitrator
    ) external returns (address) {
        // TODO do a minimal check on arbitrator w/out using ERC165
        Rep rep = new Rep(operator, tokens, promise_);
        _repArbitrators[address(rep)] = arbitrator;
        emit NewRep(address(rep), operator, tokens, promise_);
        return address(rep);
    }

    function newDelegation(
        address[] calldata tokens, 
        uint256[] calldata amounts, 
        uint256[][] calldata tokenIds, 
        address rep
        // TODO input redelegations
    ) external payable returns (uint256) {
        require(IRep(rep).operator() != address(0), "Reps: invalid rep");
        require(tokens.length <= 10, "Reps: cannot delegate more than 10 tokens");
        require(
            tokens.length == amounts.length &&
            amounts.length == tokenIds.length,
            "Reps: array length mismatch"
        );
        // TODO reallocate redelegations
        for(uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] > 0) {
                // treat as ERC20
                IERC20(tokens[i]).transferFrom(msg.sender, rep, amounts[i]);
            } else {
                // treat as ERC721
                for(uint256 j = 0; j < tokenIds[i].length; j++) {
                    IERC721(tokens[i]).transferFrom(msg.sender, rep, tokenIds[i][j]);
                }
            }
        }
        uint256 tokenId = _mint(msg.sender, tokens, amounts, tokenIds, rep);
        boostEthFor(rep);
        return tokenId;
    }

    function burnDelegations(uint256[] calldata delegationIds) external {
        for(uint256 i = 0; i < delegationIds.length; i++) {
            require(msg.sender == ownerOf[delegationIds[i]], "Reps: only delegator can burn delegation");
            _burnDelegation(delegationIds[i]);
        }
    }

    // Claiming for a rep with operator at address(0) will send eth to address(0),
    // but there's no way to get that eth back anyway, so no big harm done.
    function claimFor(address rep) external {
        _newCheckpoint(rep);
        address claimee = IRep(rep).operator();
        uint256 value = _repClaimable[rep];
        _repClaimable[rep] = 0;
        _transferETHOrWETH(claimee, value);
    }

    function dispute(address rep) external payable {
        uint256 id = _repDisputes[rep].id;
        require(id != 0, "Reps: already disputed");
        address arbitrator = _repArbitrators[rep];
        id = IArbitrator(arbitrator).createDispute(2, "");
        _repDisputes[rep] = Dispute(id, msg.sender);
        _disputeReps[id] = rep;
    }

    // @param ruling 0 -- refused to arbitrate, 1 -- fired, 2 -- not fired
    function rule(uint256 disputeId, uint256 ruling) external {
        address rep = _disputeReps[disputeId];
        require(rep != address(0), "Reps: non-existant dispute");
        address arbitrator = _repArbitrators[rep];
        require(arbitrator == msg.sender, "Reps: arbitrator only");
        if (ruling == 1) {
            // you're fired
            IRep(rep).setOperator(address(0));
            // send remaining rep funds to dispute creator
            uint256 amount = _repClaimable[rep] + _repStreamPools[rep];
            address creator = _repDisputes[rep].creator;
            _repStreamRates[rep] = 0;
            _repClaimable[rep] = 0;
            _repStreamPools[rep] = 0;
            _repCheckpointTimes[rep] = block.timestamp;
            _transferETHOrWETH(creator, amount);
        }
        // rep is no longer disputed
        delete _repDisputes[rep];
        emit Ruling(IArbitrator(arbitrator), disputeId, ruling);
    }

    function delegationData(uint256 id) external view returns (
        address[] memory, 
        uint256[] memory, 
        uint256[][] memory, 
        address
    ) {
        return (
            _delegationTokens[id],
            _delegationAmounts[id],
            _delegationTokenIds[id],
            _delegationReps[id]
        );
    }

    function repData(address rep) external view returns (
        uint256,
        uint256,
        uint256,
        uint256,
        address,
        uint256,
        address
    ) {
        return (
          _repCheckpointTimes[rep],
          _repClaimable[rep],
          _repStreamPools[rep],
          _repStreamRates[rep],
          _repArbitrators[rep],
          _repDisputes[rep].id,
          _repDisputes[rep].creator
        );
    }

    //===== Public Functions =====//

    // If the rep's operator is address(0), eth paid here is lost!
    // This may be a bad design choice, but it may not be, and it is simple.
    function boostEthFor(address rep) public payable {
        _newCheckpoint(rep);
        _repStreamRates[rep] = _repStreamPools[rep] + msg.value;
    }

    function claimableFor(address rep) public view returns (uint256) {
        uint256 timePassed = block.timestamp - _repCheckpointTimes[rep];
        // stream rate is such that 100% would be claimable after 365 solidity days
        // if nothing is added to the pool. Adding to the pool increases the rate
        return _repStreamRates[rep] * timePassed / 365 days;
    }

    // TODO something useful with tokenURI
    function tokenURI(uint256 delegationId) public view override returns (string memory) {
        return "";
    }


    //===== Private Functions =====//

    function _newCheckpoint(address rep) private {
        uint256 newClaimable = claimableFor(rep);
        _repCheckpointTimes[rep] = block.timestamp;
        _repClaimable[rep] = _repClaimable[rep] + newClaimable;
        _repStreamPools[rep] = _repStreamPools[rep] + msg.value - newClaimable;
        emit Checkpoint(rep, _repClaimable[rep], _repStreamPools[rep]);
    }

    function _mint(
        address to,
        address[] calldata tokens, 
        uint256[] calldata amounts, 
        uint256[][] memory tokenIds, 
        address rep
    ) private returns (uint256) {
        uint256 id = delegationCount;
        _delegationTokens[id] = tokens;
        _delegationAmounts[id] = amounts;
        _delegationTokenIds[id] = tokenIds;
        _delegationReps[id] = rep;
        _mint(to, id);
        delegationCount = delegationCount + 1;
        return id;
    }

    function _burnDelegation(uint256 id) private {
        require(ownerOf[id] != address(0), "Reps: delegation doesn't exist");
        for(uint256 i = 0; i < _delegationTokens[id].length; i++) {
            if (_delegationAmounts[id][i] > 0) {
                // treat as ERC20
                IRep(_delegationReps[id]).transferFungible(
                    ownerOf[id], 
                    _delegationTokens[id][i], 
                    _delegationAmounts[id][i]
                );
            } else {
                // treat as ERC721
                IRep(_delegationReps[id]).transferNonfungible(
                    ownerOf[id], 
                    _delegationTokens[id][i], 
                    _delegationTokenIds[id][i]
                );
            }
        }
        _burn(id);
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
            IERC20(weth).transferFrom(address(this), to, value);
        }
        emit TransferETH(to, value, success);
        return success;
    }
}