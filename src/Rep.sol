// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

interface IDelegatable {
    function delegate(address delegatee) external;
}

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount)
        external
        returns (bool);
}

interface IERC721 {
    function transferFrom(address sender, address recipient, uint256 tokenId)
        external
        returns (bool);
}

interface IRep {
    function operator() external returns (address);
    function setOperator(address) external;
    function transferFungible(address, address, uint256) external;
    function transferNonfungible(address, address, uint256[] calldata) external;
}

contract Rep is IRep {
    //===== State =====//
   
    address private immutable _owner;
    // For tokens that are not delegatable, the balance of a given token in this contract may also be
    // considered delegated to the operator.
    address public operator;
    string public promise_;
    address[10] public tokens;


    //===== Constructor =====//

    constructor(address operator_, address[10] memory tokens_, string memory promise__, address owner) {
        // Owner included in constructor args so that it goes into create2 address gen, and require
        // statement included to ensure only a given Reps contract can deploy 
        require(msg.sender == owner, "owner deploy only");
        _owner = owner;
        operator = operator_;
        promise_ = promise__;
        tokens = tokens_;
        _delegate(operator);
    }


    //===== External Functions =====//

    // Setting this to address(0) permanently kills the Rep contract's delegation! 
    // Note: cannot prevent this contract from holding tokens.
    function setOperator(address operator_) external {
        require(
            msg.sender == operator || 
            msg.sender == _owner,
            "only operator or owner"
        );
        operator = operator_;
        _delegate(operator);
    }

    function transferFungible(address to, address token, uint256 amount) external onlyOwner {
        IERC20(token).transferFrom(address(this), to, amount);
    }

    function transferNonfungible(address to, address token, uint256[] calldata tokenIds) external onlyOwner {
        for(uint256 i = 0; i < tokenIds.length; i++) {
            IERC721(token).transferFrom(address(this), to, tokenIds[i]);
        }
    }


    //===== Private Functions =====//

    function _delegate(address operator_) private {
        for(uint8 i = 0; i < tokens.length; i++) {
            if (tokens[i] != address(0)) {
                try IDelegatable(tokens[i]).delegate(operator_) {} catch {}
            }
        }
    }


    //===== Modifiers =====//

    modifier onlyOwner() {
        require(msg.sender == _owner, "only owner");
        _;
    }
}