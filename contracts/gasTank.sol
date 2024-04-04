// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IBlast.sol";

//  address BlastPointsAddressTestnet = 0x2fc95838c71e76ec69ff817983BFf17c710F34E0;
//  address BlastPointsAddressMainnet = 0x2536FE9ab3F511540F2f9e2eC2A805005C3Dd800;

contract GasTank is ReentrancyGuard, Ownable {
    IBlast public constant BLAST =
        IBlast(0x4300000000000000000000000000000000000002);
    IBlastPoints public constant BLAST_POINTS =
        IBlastPoints(0x2fc95838c71e76ec69ff817983BFf17c710F34E0);
    address public treasuror;

    uint256 public MINIMUM_CONTRIBUTION_AMOUNT = 0.001 ether; // Minimum Amount to Stake

    string private constant NEVER_CONTRIBUTED_ERROR =
        "This address has never contributed ETH to the protocol";
    string private constant MINIMUM_CONTRIBUTION_ERROR =
        "Contributions must be over the minimum contribution amount";

    struct Staker {
        address addr; // The Address of the Staker
        uint256 debt; // Native ETH amount that is used
        uint256 reserve; // Native ETH amount that is available
        uint256 joined; // The time that the user joined the protocol
        uint256 nonce; // Block recall unstake
        bool exists;
    }

    mapping(address => Staker) public stakers;
    address[] public stakerList;

    constructor(address _pointsOperator) ReentrancyGuard() Ownable() {
        BLAST.configureAutomaticYield(); //contract balance will grow automatically
        BLAST_POINTS.configurePointsOperator(_pointsOperator);
        treasuror = _pointsOperator;
    }

    receive() external payable {}
    fallback() external payable {}

    function Stake() external payable nonReentrant {
        require(
            msg.value >= MINIMUM_CONTRIBUTION_AMOUNT,
            MINIMUM_CONTRIBUTION_ERROR
        );
        uint256 eth = msg.value;

        if (StakerExists(msg.sender)) {
            stakers[msg.sender].reserve = stakers[msg.sender].reserve + eth;
        } else {
            // Create new user
            Staker memory user;
            user.addr = msg.sender;
            user.reserve = eth;
            user.debt = 0;
            user.exists = true;
            user.joined = block.timestamp;
            user.nonce = 0;
            // Add user to Stakers
            stakers[msg.sender] = user;
            stakerList.push(msg.sender);
        }
        payable(owner()).transfer(eth);
    }

    function RemoveStake() external {
        address user = msg.sender;
        if (!StakerExists(user)) {
            revert(NEVER_CONTRIBUTED_ERROR);
        }
        uint256 uns = stakers[user].reserve;
        if (uns == 0) {
            revert("This user has nothing to withdraw from the protocol");
        }

        // Remove Stake
        stakers[user].reserve = 0;
        stakers[user].nonce = stakers[user].nonce + 1;
        payable(user).transfer(uns);
    }

    function RemoveStake() external {
        address user = msg.sender;
        if (!StakerExists(user)) {
            revert(NEVER_CONTRIBUTED_ERROR);
        }
        uint256 uns = stakers[user].reserve;
        if (uns == 0) {
            revert("This user has nothing to withdraw from the protocol");
        }

        // Remove Stake
        stakers[user].reserve = 0;
        stakers[user].nonce = stakers[user].nonce + 1;
        payable(user).transfer(uns);
    }

    /* 

      CONTRIBUTER GETTERS

    */

    function StakerExists(address a) public view returns (bool) {
        return stakers[a].exists;
    }

    function StakerCount() public view returns (uint256) {
        return stakerList.length;
    }

    function GetStakeJoinDate(address a) public view returns (uint256) {
        if (!StakerExists(a)) {
            revert(NEVER_CONTRIBUTED_ERROR);
        }
        return stakers[a].joined;
    }

    function GetStakingAmount(address a) public view returns (uint256) {
        if (!StakerExists(a)) {
            revert(NEVER_CONTRIBUTED_ERROR);
        }
        return stakers[a].reserve;
    }

    function GetAllYield() public view returns (uint256) {
        uint256 total_reward = BLAST.readClaimableYield(address(this));
        return total_reward;
    }
}
