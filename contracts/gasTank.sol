// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IBlast.sol";

contract GasTank is ReentrancyGuard, Ownable {
    uint256 public UNSTAKEABLE_FEE = 9950; // How much can they Unstake? 99.5% AKA 0.5% Staking FEE
    uint256 public MINIMUM_CONTRIBUTION_AMOUNT = 0.001 ether; // Minimum Amount to Stake
    bool public CONTRACT_RENOUNCED = false; // for ownerOnly Functions
    address public blast_yield_contract;

    string private constant NEVER_CONTRIBUTED_ERROR =
        "This address has never contributed ETH to the protocol";
    string private constant NO_ETH_CONTRIBUTIONS_ERROR = "No ETH Contributions";
    string private constant MINIMUM_CONTRIBUTION_ERROR =
        "Contributions must be over the minimum contribution amount";

    struct Staker {
        address addr; // The Address of the Staker
        uint256 lifetime_contribution; // The Total Lifetime Contribution of the Staker
        uint256 contribution; // The Current Contribution of the Staker
        uint256 yield; // The Current Yield / Reward amount of the Staker
        uint256 unstakeable; // How much can the staker withdraw.
        uint256 joined; // When did the Staker start staking
        bool exists;
    }

    mapping(address => Staker) public stakers;
    address[] public stakerList;

    constructor(
        address _owner,
        address _blast_yield_contract
    ) ReentrancyGuard() Ownable(_owner) {
        blast_yield_contract = _blast_yield_contract;
        IBlast(_blast_yield_contract).configureClaimableYield(); //contract balance will grow automatically
    }

    receive() external payable {}
    fallback() external payable {}

    function AddStakerYield(address addr, uint256 a) private {
        stakers[addr].yield = stakers[addr].yield + a;
    }

    function RemoveStakerYield(address addr, uint256 a) private {
        stakers[addr].yield = stakers[addr].yield - a;
    }

    function RenounceContract() external onlyOwner {
        CONTRACT_RENOUNCED = true;
    }

    function ChangeMinimumStakingAmount(uint256 a) external onlyOwner {
        MINIMUM_CONTRIBUTION_AMOUNT = a;
    }

    function ChangeUnstakeableFee(uint256 a) external onlyOwner {
        UNSTAKEABLE_FEE = a;
    }

    function UnstakeAll() external onlyOwner {
        if (CONTRACT_RENOUNCED == true) {
            revert("Unable to perform this action");
        }
        for (uint i = 0; i < stakerList.length; i++) {
            address user = stakerList[i];
            ForceRemoveStake(user);
        }
    }

    function Stake() external payable nonReentrant {
        require(
            msg.value >= MINIMUM_CONTRIBUTION_AMOUNT,
            MINIMUM_CONTRIBUTION_ERROR
        );
        uint256 eth = msg.value;
        uint256 unstakeable = (eth * UNSTAKEABLE_FEE) / 10000;

        if (StakerExists(msg.sender)) {
            stakers[msg.sender].lifetime_contribution =
                stakers[msg.sender].lifetime_contribution +
                eth;
            stakers[msg.sender].contribution =
                stakers[msg.sender].contribution +
                unstakeable;
            stakers[msg.sender].unstakeable =
                stakers[msg.sender].unstakeable +
                unstakeable;
        } else {
            // Create new user
            Staker memory user;
            user.addr = msg.sender;
            user.contribution = unstakeable;
            user.lifetime_contribution = eth;
            user.yield = 0;
            user.exists = true;
            user.unstakeable = unstakeable;
            user.joined = block.timestamp;
            // Add user to Stakers
            stakers[msg.sender] = user;
            stakerList.push(msg.sender);
        }

        // Staking has completed (or failed and won't reach this point)
        uint256 c = (10000 - UNSTAKEABLE_FEE);
        uint256 fee = (eth * c) / 10000;
        // Staking fee is stored as fee, use as you wish
        payable(owner()).transfer(fee);
    }

    function RemoveStake() external {
        address user = msg.sender;
        if (!StakerExists(user)) {
            revert(NEVER_CONTRIBUTED_ERROR);
        }
        uint256 uns = stakers[user].unstakeable;
        if (uns == 0) {
            revert("This user has nothing to withdraw from the protocol");
        }
        // Proceed to Unstake user funds from 3rd Party Yielding Farms etc
        uint256 total_shared = 0;
        for (uint i = 0; i < stakerList.length; i++) {
            total_shared += stakers[user].unstakeable;
        }
        uint256 total_reward = IBlast(blast_yield_contract).readClaimableYield(
            address(this)
        );
        uint256 shared_reward = (uns * total_reward) / total_shared;
        IBlast(blast_yield_contract).claimYield(
            address(this),
            user,
            shared_reward
        );

        // Remove Stake
        stakers[user].unstakeable = 0;
        stakers[user].contribution = 0;
        payable(user).transfer(uns);
    }

    function ForceRemoveStake(address user) private {
        if (!StakerExists(user)) {
            revert(NEVER_CONTRIBUTED_ERROR);
        }
        uint256 uns = stakers[user].unstakeable;
        if (uns == 0) {
            revert("This user has nothing to withdraw from the protocol");
        }

        // Remove Stake
        stakers[user].unstakeable = 0;
        stakers[user].contribution = 0;
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

    function GetStakerYield(address a) public view returns (uint256) {
        if (!StakerExists(a)) {
            revert(NEVER_CONTRIBUTED_ERROR);
        }
        return stakers[a].yield;
    }

    function GetStakingAmount(address a) public view returns (uint256) {
        if (!StakerExists(a)) {
            revert(NEVER_CONTRIBUTED_ERROR);
        }
        return stakers[a].contribution;
    }

    function GetStakerPercentageByAddress(
        address a
    ) public view returns (uint256) {
        if (!StakerExists(a)) {
            revert(NEVER_CONTRIBUTED_ERROR);
        }
        uint256 c_total = 0;
        for (uint i = 0; i < stakerList.length; i++) {
            c_total = c_total + stakers[stakerList[i]].contribution;
        }
        if (c_total == 0) {
            revert(NO_ETH_CONTRIBUTIONS_ERROR);
        }
        return (stakers[a].contribution * 10000) / c_total;
    }

    function GetStakerUnstakeableAmount(
        address addr
    ) public view returns (uint256) {
        if (StakerExists(addr)) {
            return stakers[addr].unstakeable;
        } else {
            return 0;
        }
    }

    function GetLifetimeContributionAmount(
        address a
    ) public view returns (uint256) {
        if (!StakerExists(a)) {
            revert("This address has never contributed ETH to the protocol");
        }
        return stakers[a].lifetime_contribution;
    }

    function CheckContractRenounced() external view returns (bool) {
        return CONTRACT_RENOUNCED;
    }
}
