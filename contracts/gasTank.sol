// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

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

    uint256 public MINIMUM_CONTRIBUTION_AMOUNT = 0.000001 ether; // Minimum Amount to Stake

    string private constant NEVER_CONTRIBUTED_ERROR =
        "This address has never contributed ETH to the protocol";
    string private constant MINIMUM_CONTRIBUTION_ERROR =
        "Contributions must be over the minimum contribution amount";

    struct Staker {
        address addr; // The Address of the Staker
        uint256 shares;
        uint256 debts;
        uint256 joined; // The time that the user joined the protocol
        bool exists;
    }

    uint256 public totalDebts;
    uint256 public totalShares;
    uint256 private base;
    bool private initialRatioFlag;

    mapping(address => Staker) public stakers;
    address[] public stakerList;

    constructor(address _pointsOperator) ReentrancyGuard() Ownable() {
        // BLAST.configureAutomaticYield();
        // BLAST_POINTS.configurePointsOperator(_pointsOperator);
        treasuror = _pointsOperator;
        base = 10 ** 18;
    }

    receive() external payable {}
    fallback() external payable {}

    modifier isInitialRatioNotSet() {
        require(!initialRatioFlag, "Initial Ratio has already been set");
        _;
    }

    modifier isInitialRatioSet() {
        require(initialRatioFlag, "Initial Ratio has not yet been set");
        _;
    }

    function configureClaimableYield() external onlyOwner {
        BLAST.configureClaimableYield();
    }

    function configureAutomaticYield() external onlyOwner {
        BLAST.configureAutomaticYield();
    }

    function configureClaimableGas() external onlyOwner {
        BLAST.configureClaimableGas();
    }

    function configureGovernor(address _governor) external onlyOwner {
        BLAST.configureGovernor(_governor);
    }

    // claim yield
    function claimYield(
        address recipientOfYield,
        uint256 amount
    ) external onlyOwner {
        BLAST.claimYield(address(this), recipientOfYield, amount);
    }

    function claimAllYield(address recipientOfYield) external onlyOwner {
        BLAST.claimAllYield(address(this), recipientOfYield);
    }

    // claim gas
    function claimAllGas(address recipientOfGas) external onlyOwner {
        BLAST.claimAllGas(address(this), recipientOfGas);
    }

    function claimMaxGas(address recipientOfGas) external onlyOwner {
        BLAST.claimMaxGas(address(this), recipientOfGas);
    }

    // read functions
    function readClaimableYield() external view returns (uint256) {
        return BLAST.readClaimableYield(address(this));
    }

    function readYieldConfiguration() external view returns (uint8) {
        return BLAST.readYieldConfiguration(address(this));
    }

    function readGasParams()
        external
        view
        returns (
            uint256 etherSeconds,
            uint256 etherBalance,
            uint256 lastUpdated,
            GasMode
        )
    {
        return BLAST.readGasParams(address(this));
    }

    // Staking
    function readContractAvailable() public view returns (uint256) {
        uint256 contractBalance = address(this).balance;
        return contractBalance;
    }

    function setInitialRatio(uint256 stakeAmount) public payable {
        require(totalShares == 0, "Stakes and shares are non-zero");
        require(
            stakeAmount >= MINIMUM_CONTRIBUTION_AMOUNT,
            MINIMUM_CONTRIBUTION_ERROR
        );

        // Create new user & Add user to Stakers
        stakers[msg.sender] = Staker({
            addr: msg.sender,
            exists: true,
            joined: block.timestamp,
            debts: 0,
            shares: base
        });
        stakerList.push(msg.sender);

        totalShares = base;
        initialRatioFlag = true;

        payable(address(this)).transfer(stakeAmount);
    }

    function caclContractShare(
        uint256 stakeAmount
    ) public view returns (uint256) {
        uint256 shares = (stakeAmount * totalShares) / address(this).balance;
        return shares;
    }

    function caclContractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function depositBonus() external payable {
        payable(address(this)).transfer(msg.value);
    }

    function stake() external payable nonReentrant {
        require(
            msg.value >= MINIMUM_CONTRIBUTION_AMOUNT,
            MINIMUM_CONTRIBUTION_ERROR
        );
        if (totalShares == 0) {
            return setInitialRatio(msg.value);
        }

        uint256 stkAmount = msg.value;
        uint256 shares = (stkAmount * totalShares) /
            (address(this).balance - msg.value);

        if (stakerExists(msg.sender)) {
            stakers[msg.sender].shares += shares;
        } else {
            // Create new user
            stakers[msg.sender] = Staker({
                addr: msg.sender,
                exists: true,
                joined: block.timestamp,
                debts: 0,
                shares: shares
            });
            stakerList.push(msg.sender);
        }
        totalShares += shares;

        payable(address(this)).transfer(stkAmount);
    }

    function calcUserRatio(
        address owner,
        uint256 amount
    ) public view returns (uint256) {
        uint256 shares = stakers[owner].shares;
        uint256 currentRatio = (shares * base) / totalShares;
        return (amount * currentRatio) / base;
    }

    function readAvailableByOwner(address owner) public view returns (uint256) {
        uint256 stakeholderShares = stakers[owner].shares;
        uint256 contractBalance = address(this).balance;
        return (stakeholderShares * contractBalance) / totalShares;
    }

    function unstake(uint256 outAmount) public nonReentrant {
        address user = msg.sender;
        require(stakerExists(user), NEVER_CONTRIBUTED_ERROR);

        uint256 avaiable = readAvailableByOwner(user);
        uint256 contractAvailable = readContractAvailable();
        uint256 sharesToWithdraw = (outAmount * totalShares) /
            contractAvailable;

        require(avaiable >= outAmount, "Not enough ETH to withdraw");

        stakers[msg.sender].debts += outAmount;
        stakers[msg.sender].shares -= sharesToWithdraw;

        totalShares -= sharesToWithdraw;

        address payable recipient = payable(msg.sender);
        recipient.transfer(outAmount);
    }

    function sponsorTx(
        address owner,
        uint256 sponsorAmount
    ) external onlyOwner {
        require(stakerExists(owner), NEVER_CONTRIBUTED_ERROR);

        uint256 avaiable = readAvailableByOwner(owner);
        uint256 contractAvailable = readContractAvailable();
        uint256 sharesToWithdraw = (sponsorAmount * totalShares) /
            contractAvailable;

        require(avaiable >= sponsorAmount, "Not enough ETH to withdraw");

        stakers[owner].debts += sponsorAmount;
        stakers[owner].shares -= sharesToWithdraw;

        totalShares -= sharesToWithdraw;
        totalDebts = totalDebts + sponsorAmount;

        address payable recipient = payable(msg.sender);
        recipient.transfer(sponsorAmount);
    }
    /* 

      CONTRIBUTER GETTERS

    */

    function stakerExists(address a) public view returns (bool) {
        return stakers[a].exists;
    }

    function stakerCount() public view returns (uint256) {
        return stakerList.length;
    }

    function getStakeJoinDate(address a) public view returns (uint256) {
        if (!stakerExists(a)) {
            revert(NEVER_CONTRIBUTED_ERROR);
        }
        return stakers[a].joined;
    }
}
