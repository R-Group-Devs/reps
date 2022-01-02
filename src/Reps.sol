// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import {ERC721} from "openzeppelin-contracts.git/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "openzeppelin-contracts.git/token/ERC721/extensions/ERC721Enumerable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts.git/security/ReentrancyGuard.sol";
import {IRep, Rep, IERC20, IERC721} from "./Rep.sol";

interface IWETH {
    function deposit() external payable;
}

contract Reps is ERC721Enumerable, ReentrancyGuard {
    //===== State =====//

    uint256 public delegationCount;
    mapping(uint256 => address[]) public delegationTokens;
    mapping(uint256 => uint256[]) public delegationAmounts;
    mapping(uint256 => uint256[][]) public delegationTokenIds;
    mapping(uint256 => address) public delegationReps;

    mapping(address => uint256) private _repCheckpointTimes;
    mapping(address => uint256) public repClaimable;
    mapping(address => uint256) public repStreamPools;
    mapping(address => uint256) public repStreamRates;

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

    // @param promise The political promise of the rep. Could be a hash + URI in the future but should emphasize brevity.
    function newRep(address operator, address[10] calldata tokens, string calldata promise_) external {
        require(tokens.length <= 10, "Reps: rep cannot have more than 10 tokens");
        Rep rep = new Rep(operator, tokens, promise_, msg.sender);
        emit NewRep(address(rep), operator, tokens, promise_);
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
            require(msg.sender == ownerOf(delegationIds[i]), "Reps: only delegator can burn delegation");
            _burnDelegation(delegationIds[i]);
        }
    }

    // Claiming for a rep with operator at address(0) will send eth to address(0),
    // but there's no way to get that eth back anyway, so no big harm done.
    function claimFor(address rep) external {
        _newCheckpoint(rep);
        address claimee = IRep(rep).operator();
        uint256 value = repClaimable[rep];
        repClaimable[rep] = 0;
        _transferETHOrWETH(claimee, value);
    }

    // TODO arbitration


    //===== Public Functions =====//

    // If the rep's operator is address(0), eth paid here is lost!
    // This may be a bad design choice, but it may not be, and it is simple.
    function boostEthFor(address rep) public payable {
        _newCheckpoint(rep);
        repStreamRates[rep] = repStreamPools[rep] + msg.value;
    }

    function claimableFor(address rep) public view returns (uint256) {
        uint256 timePassed = block.timestamp - _repCheckpointTimes[rep];
        // stream rate is such that 100% would be claimable after 365 solidity days
        // if nothing is added to the pool. Adding to the pool increases the rate
        return repStreamRates[rep] * timePassed / 365 days;
    }


    //===== Private Functions =====//

    function _fire(address rep) private {
        IRep(rep).setOperator(address(0));
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

    function _newCheckpoint(address rep) private {
        uint256 newClaimable = claimableFor(rep);
        _repCheckpointTimes[rep] = block.timestamp;
        repClaimable[rep] = repClaimable[rep] + newClaimable;
        repStreamPools[rep] = repStreamPools[rep] + msg.value - newClaimable;
        emit Checkpoint(rep, repClaimable[rep], repStreamPools[rep]);
    }

    function _mint(
        address to,
        address[] calldata tokens, 
        uint256[] calldata amounts, 
        uint256[][] memory tokenIds, 
        address rep
    ) private returns (uint256) {
        uint256 id = delegationCount;
        delegationTokens[id] = tokens;
        delegationAmounts[id] = amounts;
        delegationTokenIds[id] = tokenIds;
        delegationReps[id] = rep;
        _mint(to, id);
        delegationCount = delegationCount + 1;
        return id;
    }

    function _burnDelegation(uint256 id) private {
        require(ownerOf(id) != address(0), "Reps: Rep doesn't exist");
        for(uint256 i = 0; i < delegationTokens[id].length; i++) {
            if (delegationAmounts[id][i] > 0) {
                // treat as ERC20
                IRep(delegationReps[id]).transferFungible(
                    ownerOf(id), 
                    delegationTokens[id][i], 
                    delegationAmounts[id][i]
                );
            } else {
                // treat as ERC721
                IRep(delegationReps[id]).transferNonfungible(
                    ownerOf(id), 
                    delegationTokens[id][i], 
                    delegationTokenIds[id][i]
                );
            }
        }
        _burn(id);
    }
}