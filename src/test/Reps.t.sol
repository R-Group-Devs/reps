pragma solidity 0.8.10;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import {ERC20User} from "solmate/test/utils/users/ERC20User.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {CentralizedArbitrator} from "./CentralizedArbitrator.sol";
import {Reps} from "../Reps.sol";
import {Rep, IRep} from "../Rep.sol";
import "./console.sol";

contract RepsTest is DSTestPlus {
    Reps reps;
    WETH weth;
    CentralizedArbitrator arb;
    MockERC20 erc20_1;
    MockERC20 erc20_2;
    MockERC20 erc20_3;
    MockERC20 erc20_4;
    MockERC20 erc20_5;
    MockERC721 erc721_1;
    MockERC721 erc721_2;
    MockERC721 erc721_3;
    MockERC721 erc721_4;
    MockERC721 erc721_5;

    function setUp() public {
        weth = new WETH();
        reps = new Reps("Test", "TST", address(weth));
        arb = new CentralizedArbitrator(1000000, 10000, 2000000);
        erc20_1 = new MockERC20("ERC20_1", "201", 18);
        erc20_2 = new MockERC20("ERC20_2", "202", 18);
        erc20_3 = new MockERC20("ERC20_3", "203", 18);
        erc20_4 = new MockERC20("ERC20_4", "204", 18);
        erc20_5 = new MockERC20("ERC20_5", "205", 18);
        erc721_1 = new MockERC721("ERC721_1", "7211");
        erc721_2 = new MockERC721("ERC721_2", "7212");
        erc721_3 = new MockERC721("ERC721_3", "7213");
        erc721_4 = new MockERC721("ERC721_4", "7214");
        erc721_5 = new MockERC721("ERC721_5", "7215");
    }

    function testMetaData() public {
        assertEq(reps.name(), "Test");
        assertEq(reps.symbol(), "TST");
        assertEq(reps.weth(), address(weth));
    }

    function testNewRep() public {
        address rep = reps.newRep(
            address(0xBEEF),
            [
                address(erc20_1),
                address(0),
                address(0),
                address(0),
                address(0),
                address(erc721_1),
                address(0),
                address(0),
                address(0),
                address(0)
            ],
            "I promise to be good",
            address(arb)
        );
        assertEq(Rep(rep).operator(), address(0xBEEF));
    }
}
