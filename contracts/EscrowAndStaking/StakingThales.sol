// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";

import "../utils/proxy/ProxyReentrancyGuard.sol";
import "../utils/proxy/ProxyOwned.sol";
import "../utils/proxy/ProxyPausable.sol";
import "@openzeppelin/upgrades-core/contracts/Initializable.sol";

import "../interfaces/IEscrowThales.sol";
import "../interfaces/IStakingThales.sol";
import "../interfaces/ISNXRewards.sol";
import "../interfaces/IThalesRoyale.sol";
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IThalesStakingRewardsPool.sol";
import "../interfaces/IAddressResolver.sol";

contract StakingThales is IStakingThales, Initializable, ProxyOwned, ProxyReentrancyGuard, ProxyPausable {
    /* ========== LIBRARIES ========== */

    using SafeMath for uint;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IEscrowThales public iEscrowThales;
    IERC20 public stakingToken;
    IERC20 public feeToken;
    ISNXRewards public SNXRewards;
    IThalesRoyale public thalesRoyale;
    IPriceFeed public priceFeed;

    uint public periodsOfStaking;
    uint public lastPeriodTimeStamp;
    uint public durationPeriod;
    uint public unstakeDurationPeriod;
    uint public startTimeStamp;
    uint public currentPeriodRewards;
    uint public currentPeriodFees;
    bool public distributeFeesEnabled;
    uint public fixedPeriodReward;
    uint public periodExtraReward;
    uint public totalSNXRewardsInPeriod;
    uint public totalSNXFeesInPeriod;
    bool public claimEnabled;

    mapping(address => uint) public stakerLifetimeRewardsClaimed;
    mapping(address => uint) public stakerFeesClaimed;

    uint private _totalStakedAmount;
    uint private _totalEscrowedAmount;
    uint private _totalPendingStakeAmount;
    uint private _totalUnclaimedRewards;
    uint private _totalRewardsClaimed;
    uint private _totalRewardFeesClaimed;

    mapping(address => uint) public lastUnstakeTime;
    mapping(address => bool) public unstaking;
    mapping(address => uint) public unstakingAmount;
    mapping(address => uint) private _stakedBalances;
    mapping(address => uint) private _lastRewardsClaimedPeriod;
    address public thalesAMM;

    uint constant HUNDRED = 1e18;
    uint constant AMM_EXTRA_REWARD_PERIODS = 4;

    struct AMMVolumeEntry {
        uint amount;
        uint period;
    }
    mapping(address => uint) private lastAMMUpdatePeriod;
    mapping(address => AMMVolumeEntry[AMM_EXTRA_REWARD_PERIODS]) private stakerAMMVolume;

    bool public extraRewardsActive;
    IThalesStakingRewardsPool public ThalesStakingRewardsPool;

    uint public maxSNXRewardsPercentage;
    uint public maxAMMVolumeRewardsPercentage;
    uint public AMMVolumeRewardsMultiplier;
    uint public maxThalesRoyaleRewardsPercentage;

    uint constant ONE = 1e18;
    uint constant ONE_PERCENT = 1e16;

    uint public SNXVolumeRewardsMultiplier;

    mapping(address => uint) private _lastStakingPeriod;

    uint public totalStakedLastPeriodEnd;
    uint public totalEscrowedLastPeriodEnd;
    address public exoticBonds;

    IAddressResolver public addressResolver;

    address public thalesRangedAMM;
    address public sportsAMM;

    /* ========== CONSTRUCTOR ========== */

    function initialize(
        address _owner,
        address _iEscrowThales, //THALES
        address _stakingToken, //THALES
        address _feeToken, //sUSD
        uint _durationPeriod,
        uint _unstakeDurationPeriod,
        address _ISNXRewards
    ) public initializer {
        setOwner(_owner);
        initNonReentrant();
        iEscrowThales = IEscrowThales(_iEscrowThales);
        stakingToken = IERC20(_stakingToken);
        feeToken = IERC20(_feeToken);
        stakingToken.approve(_iEscrowThales, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        durationPeriod = _durationPeriod;
        unstakeDurationPeriod = _unstakeDurationPeriod;
        fixedPeriodReward = 70000 * 1e18;
        periodExtraReward = 21000 * 1e18;
        SNXRewards = ISNXRewards(_ISNXRewards);
    }

    /* ========== VIEWS ========== */

    function totalStakedAmount() external view returns (uint) {
        return _totalStakedAmount;
    }

    function stakedBalanceOf(address account) external view returns (uint) {
        return _stakedBalances[account];
    }

    function getLastPeriodOfClaimedRewards(address account) external view returns (uint) {
        return _lastRewardsClaimedPeriod[account];
    }

    function getRewardsAvailable(address account) external view returns (uint) {
        return _calculateAvailableRewardsToClaim(account);
    }

    function getRewardFeesAvailable(address account) external view returns (uint) {
        return _calculateAvailableFeesToClaim(account);
    }

    function getAlreadyClaimedRewards(address account) external view returns (uint) {
        return stakerLifetimeRewardsClaimed[account];
    }

    function getAlreadyClaimedFees(address account) external view returns (uint) {
        return stakerFeesClaimed[account];
    }

    function getContractRewardFunds() external view returns (uint) {
        return stakingToken.balanceOf(address(ThalesStakingRewardsPool));
    }

    function getContractFeeFunds() external view returns (uint) {
        return feeToken.balanceOf(address(this));
    }

    function setDistributeFeesEnabled(bool _distributeFeesEnabled) external onlyOwner {
        distributeFeesEnabled = _distributeFeesEnabled;
        emit DistributeFeesEnabled(_distributeFeesEnabled);
    }

    function setFixedPeriodReward(uint _fixedReward) external onlyOwner {
        fixedPeriodReward = _fixedReward;
        emit FixedPeriodRewardChanged(_fixedReward);
    }

    function setPeriodExtraReward(uint _extraReward) external onlyOwner {
        periodExtraReward = _extraReward;
        emit PeriodExtraRewardChanged(_extraReward);
    }

    function setClaimEnabled(bool _claimEnabled) external onlyOwner {
        claimEnabled = _claimEnabled;
        emit ClaimEnabled(_claimEnabled);
    }

    function setDurationPeriod(uint _durationPeriod) external onlyOwner {
        durationPeriod = _durationPeriod;
        emit DurationPeriodChanged(_durationPeriod);
    }

    function setUnstakeDurationPeriod(uint _unstakeDurationPeriod) external onlyOwner {
        unstakeDurationPeriod = _unstakeDurationPeriod;
        emit UnstakeDurationPeriodChanged(_unstakeDurationPeriod);
    }

    function setSNXRewards(address _snxRewards) public onlyOwner {
        require(_snxRewards != address(0), "Invalid address");
        SNXRewards = ISNXRewards(_snxRewards);
        emit SNXRewardsAddressChanged(_snxRewards);
    }

    function setExtraRewards(bool _extraRewardsActive) public onlyOwner {
        extraRewardsActive = _extraRewardsActive;
        emit ExtraRewardsChanged(_extraRewardsActive);
    }

    function setMaxSNXRewardsPercentage(uint _maxSNXRewardsPercentage) public onlyOwner {
        maxSNXRewardsPercentage = _maxSNXRewardsPercentage;
        emit MaxSNXRewardsPercentageChanged(_maxSNXRewardsPercentage);
    }

    function setMaxAMMVolumeRewardsPercentage(uint _maxAMMVolumeRewardsPercentage) public onlyOwner {
        maxAMMVolumeRewardsPercentage = _maxAMMVolumeRewardsPercentage;
        emit MaxAMMVolumeRewardsPercentageChanged(_maxAMMVolumeRewardsPercentage);
    }

    function setAMMVolumeRewardsMultiplier(uint _AMMVolumeRewardsMultiplier) public onlyOwner {
        AMMVolumeRewardsMultiplier = _AMMVolumeRewardsMultiplier;
        emit AMMVolumeRewardsMultiplierChanged(_AMMVolumeRewardsMultiplier);
    }

    function setSNXVolumeRewardsMultiplier(uint _SNXVolumeRewardsMultiplier) public onlyOwner {
        SNXVolumeRewardsMultiplier = _SNXVolumeRewardsMultiplier;
        emit SNXVolumeRewardsMultiplierChanged(_SNXVolumeRewardsMultiplier);
    }

    function setMaxThalesRoyaleRewardsPercentage(uint _maxThalesRoyaleRewardsPercentage) public onlyOwner {
        maxThalesRoyaleRewardsPercentage = _maxThalesRoyaleRewardsPercentage;
        emit MaxThalesRoyaleRewardsPercentageChanged(_maxThalesRoyaleRewardsPercentage);
    }

    function setThalesRoyale(address _royale) public onlyOwner {
        require(_royale != address(0), "Invalid address");
        thalesRoyale = IThalesRoyale(_royale);
        emit ThalesRoyaleAddressChanged(_royale);
    }

    function setThalesAMM(address _thalesAMM) public onlyOwner {
        require(_thalesAMM != address(0), "Invalid address");
        thalesAMM = _thalesAMM;
        emit ThalesAMMAddressChanged(_thalesAMM);
    }

    function setThalesRangedAMM(address _thalesRangedAMM) public onlyOwner {
        require(_thalesRangedAMM != address(0), "Invalid address");
        thalesRangedAMM = _thalesRangedAMM;
        emit ThalesRangedAMMAddressChanged(_thalesRangedAMM);
    }

    function setThalesSportsAMM(address _sportsAMM) public onlyOwner {
        require(_sportsAMM != address(0), "Invalid address");
        sportsAMM = _sportsAMM;
        emit ThalesSportsAMMAddressChanged(_sportsAMM);
    }

    function setExoticBonds(address _exoticBonds) public onlyOwner {
        require(_exoticBonds != address(0), "Invalid address");
        exoticBonds = _exoticBonds;
        emit ExoticBondsAddressChanged(_exoticBonds);
    }

    function setPriceFeed(address _priceFeed) public onlyOwner {
        require(_priceFeed != address(0), "Invalid address");
        priceFeed = IPriceFeed(_priceFeed);
        emit PriceFeedAddressChanged(_priceFeed);
    }

    function setThalesStakingRewardsPool(address _thalesStakingRewardsPool) public onlyOwner {
        require(_thalesStakingRewardsPool != address(0), "Invalid address");
        ThalesStakingRewardsPool = IThalesStakingRewardsPool(_thalesStakingRewardsPool);
        emit ThalesStakingRewardsPoolChanged(_thalesStakingRewardsPool);
    }

    // Set EscrowThales contract address
    function setEscrow(address _escrowThalesContract) public onlyOwner {
        if (address(iEscrowThales) != address(0)) {
            stakingToken.approve(address(iEscrowThales), 0);
        }
        iEscrowThales = IEscrowThales(_escrowThalesContract);
        stakingToken.approve(_escrowThalesContract, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        emit EscrowChanged(_escrowThalesContract);
    }

    function setAddressResolver(address _addressResolver) external onlyOwner {
        require(_addressResolver != address(0), "Invalid address");
        addressResolver = IAddressResolver(_addressResolver);
        emit AddressResolverChanged(_addressResolver);
    }

    function getSNXRewardsAddress() public view returns (address) {
        if (address(addressResolver) == address(0)) {
            return address(0);
        } else {
            return addressResolver.getAddress("Issuer");
        }
    }

    function getSNXStaked(address account) external view returns (uint) {
        return _getSNXStakedForAccount(account);
    }

    function getBaseReward(address account) public view returns (uint) {
        if (
            (_lastStakingPeriod[account] == periodsOfStaking) ||
            (_stakedBalances[account] == 0) ||
            (_lastRewardsClaimedPeriod[account] == periodsOfStaking) ||
            (totalStakedLastPeriodEnd == 0)
        ) {
            return 0;
        }
        return
            _stakedBalances[account]
                .add(iEscrowThales.getStakedEscrowedBalanceForRewards(account))
                .mul(currentPeriodRewards)
                .div(totalStakedLastPeriodEnd.add(totalEscrowedLastPeriodEnd));
    }

    function getAMMVolume(address account) external view returns (uint) {
        return _getTotalAMMVolume(account);
    }

    function getSNXBonusPercentage(address account) public view returns (uint) {
        uint baseReward = getBaseReward(account);
        if (baseReward == 0) {
            return 0;
        }
        uint stakedSNX = _getSNXStakedForAccount(account);
        // SNX staked more than base reward
        return
            stakedSNX >= baseReward.mul(SNXVolumeRewardsMultiplier)
                ? maxSNXRewardsPercentage.mul(ONE_PERCENT)
                : stakedSNX.mul(maxSNXRewardsPercentage).mul(ONE_PERCENT).div(baseReward.mul(SNXVolumeRewardsMultiplier));
    }

    function getSNXBonus(address account) public view returns (uint) {
        uint baseReward = getBaseReward(account);
        uint SNXBonusPercentage = getSNXBonusPercentage(account);

        return baseReward.mul(SNXBonusPercentage).div(ONE);
    }

    function getAMMBonusPercentage(address account) public view returns (uint) {
        uint baseReward = getBaseReward(account);
        if (baseReward == 0) {
            return 0;
        }
        return
            _getTotalAMMVolume(account) >= baseReward.mul(AMMVolumeRewardsMultiplier)
                ? maxAMMVolumeRewardsPercentage.mul(ONE_PERCENT)
                : _getTotalAMMVolume(account).mul(ONE_PERCENT).mul(maxAMMVolumeRewardsPercentage).div(
                    baseReward.mul(AMMVolumeRewardsMultiplier)
                );
    }

    function getAMMBonus(address account) public view returns (uint) {
        uint baseReward = getBaseReward(account);
        uint AMMPercentage = getAMMBonusPercentage(account);
        return baseReward.mul(AMMPercentage).div(ONE);
    }

    function getThalesRoyaleBonusPercentage(address account) public view returns (uint) {
        uint baseReward = getBaseReward(account);
        if (baseReward == 0) {
            return 0;
        }
        return
            (address(thalesRoyale) != address(0) && thalesRoyale.hasParticipatedInCurrentOrLastRoyale(account))
                ? maxThalesRoyaleRewardsPercentage.mul(ONE_PERCENT)
                : 0;
    }

    function getThalesRoyaleBonus(address account) public view returns (uint) {
        uint baseReward = getBaseReward(account);
        uint RoyalePercentage = getThalesRoyaleBonusPercentage(account);
        return baseReward.mul(RoyalePercentage).div(ONE);
    }

    function getTotalBonusPercentage(address account) public view returns (uint) {
        uint snxPercentage = getSNXBonusPercentage(account);
        uint ammPercentage = getAMMBonusPercentage(account);
        uint royalePercentage = getThalesRoyaleBonusPercentage(account);
        return snxPercentage.add(ammPercentage).add(royalePercentage);
    }

    function getTotalBonus(address account) public view returns (uint) {
        uint baseReward = getBaseReward(account);
        uint totalBonusPercentage = getTotalBonusPercentage(account);
        // failsafe
        require(totalBonusPercentage < ONE, "Bonus Exceeds base rewards");
        return baseReward.mul(totalBonusPercentage).div(ONE);
    }

    function canClosePeriod() external view returns (bool) {
        return (startTimeStamp > 0 && (block.timestamp >= lastPeriodTimeStamp.add(durationPeriod)));
    }

    function getSNXTargetRatio() public view returns (uint) {
        uint hund = 100 * 100 * 1e18;
        return hund.div(ISNXRewards(getSNXRewardsAddress()).issuanceRatio());
    }

    function getCRatio(address account) public view returns (uint) {
        uint debt = ISNXRewards(getSNXRewardsAddress()).debtBalanceOf(account, "sUSD");
        if (debt == 0) {
            return 0;
        }
        uint hund = 100 * 100 * 1e18;
        (uint cRatio, ) = ISNXRewards(getSNXRewardsAddress()).collateralisationRatioAndAnyRatesInvalid(account);
        return hund.div(cRatio);
    }

    function getSNXRateForCurrency() public view returns (uint) {
        return priceFeed.rateForCurrency("SNX");
    }

    function getSNXDebt(address account) public view returns (uint) {
        return ISNXRewards(getSNXRewardsAddress()).debtBalanceOf(account, "sUSD");
    }

    /* ========== PUBLIC ========== */

    function startStakingPeriod() external onlyOwner {
        require(startTimeStamp == 0, "Staking has already started");
        startTimeStamp = block.timestamp;
        periodsOfStaking = 0;
        lastPeriodTimeStamp = startTimeStamp;
        _totalUnclaimedRewards = 0;
        _totalRewardsClaimed = 0;
        _totalRewardFeesClaimed = 0;
        _totalStakedAmount = 0;
        _totalEscrowedAmount = 0;
        _totalPendingStakeAmount = 0;
        emit StakingPeriodStarted();
    }

    function closePeriod() external nonReentrant notPaused {
        require(startTimeStamp > 0, "Staking period has not started");
        require(
            block.timestamp >= lastPeriodTimeStamp.add(durationPeriod),
            "A full period has not passed since the last closed period"
        );

        iEscrowThales.updateCurrentPeriod();
        lastPeriodTimeStamp = block.timestamp;
        periodsOfStaking = iEscrowThales.currentVestingPeriod();

        _totalEscrowedAmount = iEscrowThales.totalEscrowedRewards().sub(
            iEscrowThales.totalEscrowBalanceNotIncludedInStaking()
        );

        //Actions taken on every closed period
        currentPeriodRewards = fixedPeriodReward;
        _totalUnclaimedRewards = _totalUnclaimedRewards.add(currentPeriodRewards.add(periodExtraReward));

        currentPeriodFees = feeToken.balanceOf(address(this));

        totalStakedLastPeriodEnd = _totalStakedAmount;
        totalEscrowedLastPeriodEnd = _totalEscrowedAmount;

        emit ClosedPeriod(periodsOfStaking, lastPeriodTimeStamp);
    }

    function stake(uint amount) external nonReentrant notPaused {
        require(startTimeStamp > 0, "Staking period has not started");
        require(amount > 0, "Cannot stake 0");
        require(
            stakingToken.allowance(msg.sender, address(this)) >= amount,
            "No allowance. Please grant StakingThales allowance"
        );
        require(unstaking[msg.sender] == false, "Cannot stake, the staker is paused from staking due to unstaking");
        // Check if there are not claimable rewards from last period.
        // Claim them, and add new stake

        if (_calculateAvailableRewardsToClaim(msg.sender) > 0) {
            _claimReward(msg.sender);
        }
        _lastStakingPeriod[msg.sender] = periodsOfStaking;

        // if just started staking subtract his escrowed balance from totalEscrowBalanceNotIncludedInStaking
        if (_stakedBalances[msg.sender] == 0) {
            if (iEscrowThales.totalAccountEscrowedAmount(msg.sender) > 0) {
                iEscrowThales.subtractTotalEscrowBalanceNotIncludedInStaking(
                    iEscrowThales.totalAccountEscrowedAmount(msg.sender)
                );
            }
        }

        _totalStakedAmount = _totalStakedAmount.add(amount);
        _stakedBalances[msg.sender] = _stakedBalances[msg.sender].add(amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function stakeOnBehalf(uint amount, address staker) external nonReentrant onlyOwner {
        require(startTimeStamp > 0, "Staking period has not started");
        require(amount > 0, "Cannot stake 0");
        require(
            stakingToken.allowance(msg.sender, address(this)) >= amount,
            "No allowance. Please grant StakingThales allowance"
        );
        require(unstaking[staker] == false, "Cannot stake, the staker is paused from staking due to unstaking");
        // Check if there are not claimable rewards from last period.
        // Claim them, and add new stake
        if (_calculateAvailableRewardsToClaim(staker) > 0) {
            _claimReward(staker);
        }

        // if just started staking subtract his escrowed balance from totalEscrowBalanceNotIncludedInStaking
        if (_stakedBalances[staker] == 0) {
            if (iEscrowThales.totalAccountEscrowedAmount(staker) > 0) {
                iEscrowThales.subtractTotalEscrowBalanceNotIncludedInStaking(
                    iEscrowThales.totalAccountEscrowedAmount(staker)
                );
            }
        }

        _totalStakedAmount = _totalStakedAmount.add(amount);
        _stakedBalances[staker] = _stakedBalances[staker].add(amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit StakedOnBehalf(msg.sender, staker, amount);
    }

    function startUnstake(uint amount) external notPaused {
        require(amount > 0, "Cannot unstake 0");
        require(_stakedBalances[msg.sender] >= amount, "Account doesnt have that much staked");
        require(unstaking[msg.sender] == false, "Account has already triggered unstake cooldown");

        if (_calculateAvailableRewardsToClaim(msg.sender) > 0) {
            _claimReward(msg.sender);
        }
        lastUnstakeTime[msg.sender] = block.timestamp;
        unstaking[msg.sender] = true;
        _totalStakedAmount = _totalStakedAmount.sub(amount);
        unstakingAmount[msg.sender] = amount;
        _stakedBalances[msg.sender] = _stakedBalances[msg.sender].sub(amount);

        // on full unstake add his escrowed balance to totalEscrowBalanceNotIncludedInStaking
        if (_stakedBalances[msg.sender] == 0) {
            if (iEscrowThales.totalAccountEscrowedAmount(msg.sender) > 0) {
                iEscrowThales.addTotalEscrowBalanceNotIncludedInStaking(
                    iEscrowThales.totalAccountEscrowedAmount(msg.sender)
                );
            }
        }

        emit UnstakeCooldown(msg.sender, lastUnstakeTime[msg.sender].add(unstakeDurationPeriod), amount);
    }

    function cancelUnstake() external notPaused {
        require(unstaking[msg.sender] == true, "Account is not unstaking");

        // on revert full unstake remove his escrowed balance from totalEscrowBalanceNotIncludedInStaking
        if (_stakedBalances[msg.sender] == 0) {
            if (iEscrowThales.totalAccountEscrowedAmount(msg.sender) > 0) {
                iEscrowThales.subtractTotalEscrowBalanceNotIncludedInStaking(
                    iEscrowThales.totalAccountEscrowedAmount(msg.sender)
                );
            }
        }

        if (_calculateAvailableRewardsToClaim(msg.sender) > 0) {
            _claimReward(msg.sender);
        }

        unstaking[msg.sender] = false;
        _totalStakedAmount = _totalStakedAmount.add(unstakingAmount[msg.sender]);
        _stakedBalances[msg.sender] = _stakedBalances[msg.sender].add(unstakingAmount[msg.sender]);
        unstakingAmount[msg.sender] = 0;

        emit CancelUnstake(msg.sender);
    }

    function unstake() external notPaused {
        require(unstaking[msg.sender] == true, "Account has not triggered unstake cooldown");
        require(
            lastUnstakeTime[msg.sender] < block.timestamp.sub(unstakeDurationPeriod),
            "Cannot unstake yet, cooldown not expired."
        );
        unstaking[msg.sender] = false;
        uint unstakeAmount = unstakingAmount[msg.sender];
        stakingToken.safeTransfer(msg.sender, unstakeAmount);
        unstakingAmount[msg.sender] = 0;
        emit Unstaked(msg.sender, unstakeAmount);
    }

    function claimReward() public nonReentrant notPaused {
        _claimReward(msg.sender);
    }

    function updateVolume(address account, uint amount) external {
        require(
            msg.sender == thalesAMM || msg.sender == exoticBonds || msg.sender == thalesRangedAMM || msg.sender == sportsAMM,
            "Invalid address"
        );
        require(msg.sender != address(0), "Invalid address");
        if (lastAMMUpdatePeriod[account] < periodsOfStaking) {
            stakerAMMVolume[account][periodsOfStaking.mod(AMM_EXTRA_REWARD_PERIODS)].amount = 0;
            stakerAMMVolume[account][periodsOfStaking.mod(AMM_EXTRA_REWARD_PERIODS)].period = periodsOfStaking;
            lastAMMUpdatePeriod[account] = periodsOfStaking;
        }
        stakerAMMVolume[account][periodsOfStaking.mod(AMM_EXTRA_REWARD_PERIODS)].amount = stakerAMMVolume[account][
            periodsOfStaking.mod(AMM_EXTRA_REWARD_PERIODS)
        ]
            .amount
            .add(amount);
        emit AMMVolumeUpdated(account, amount);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _claimReward(address account) internal notPaused {
        require(claimEnabled, "Claiming is not enabled.");
        require(startTimeStamp > 0, "Staking period has not started");

        //Calculate rewards
        if (distributeFeesEnabled) {
            uint availableFeesToClaim = _calculateAvailableFeesToClaim(account);
            if (availableFeesToClaim > 0) {
                feeToken.safeTransfer(account, availableFeesToClaim);
                stakerFeesClaimed[account] = stakerFeesClaimed[account].add(availableFeesToClaim);
                _totalRewardFeesClaimed = _totalRewardFeesClaimed.add(availableFeesToClaim);
                emit FeeRewardsClaimed(account, availableFeesToClaim);
            }
        }
        uint availableRewardsToClaim = _calculateAvailableRewardsToClaim(account);
        if (availableRewardsToClaim > 0) {
            // Transfer THALES to Escrow contract
            ThalesStakingRewardsPool.addToEscrow(account, availableRewardsToClaim);
            // Record the total claimed rewards
            stakerLifetimeRewardsClaimed[account] = stakerLifetimeRewardsClaimed[account].add(availableRewardsToClaim);
            _totalRewardsClaimed = _totalRewardsClaimed.add(availableRewardsToClaim);
            _totalUnclaimedRewards = _totalUnclaimedRewards.sub(availableRewardsToClaim);

            emit RewardsClaimed(account, availableRewardsToClaim);
        }
        // Update last claiming period
        _lastRewardsClaimedPeriod[account] = periodsOfStaking;
    }

    function _calculateAvailableRewardsToClaim(address account) internal view returns (uint) {
        uint baseReward = getBaseReward(account);
        if (baseReward == 0) {
            return 0;
        }
        if (!extraRewardsActive) {
            return baseReward;
        } else {
            return baseReward.add(getTotalBonus(account));
        }
    }

    function _calculateAvailableFeesToClaim(address account) internal view returns (uint) {
        uint baseReward = getBaseReward(account);
        if (baseReward == 0) {
            return 0;
        }

        return
            _stakedBalances[account]
                .add(iEscrowThales.getStakedEscrowedBalanceForRewards(account))
                .mul(currentPeriodFees)
                .div(totalStakedLastPeriodEnd.add(totalEscrowedLastPeriodEnd));
    }

    function _getSNXStakedForAccount(address account) internal view returns (uint) {
        uint cRatio = getCRatio(account);
        uint targetRatio = getSNXTargetRatio();
        uint snxPrice = priceFeed.rateForCurrency("SNX");
        uint debt = ISNXRewards(getSNXRewardsAddress()).debtBalanceOf(account, "sUSD");
        if (cRatio < targetRatio) {
            return (cRatio.mul(cRatio).mul(debt).mul(1e14)).div(targetRatio.mul(snxPrice));
        } else {
            return (targetRatio.mul(debt).mul(1e14)).div(snxPrice);
        }
    }

    function _getTotalAMMVolume(address account) internal view returns (uint) {
        uint totalAMMforAccount;
        if (periodsOfStaking >= lastAMMUpdatePeriod[account].add(AMM_EXTRA_REWARD_PERIODS)) {
            return 0;
        }
        for (uint i = 0; i < AMM_EXTRA_REWARD_PERIODS; i++) {
            if (periodsOfStaking < stakerAMMVolume[account][i].period.add(AMM_EXTRA_REWARD_PERIODS))
                totalAMMforAccount = totalAMMforAccount.add(stakerAMMVolume[account][i].amount);
        }
        return totalAMMforAccount;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint reward);
    event Staked(address user, uint amount);
    event StakedOnBehalf(address user, address staker, uint amount);
    event ClosedPeriod(uint PeriodOfStaking, uint lastPeriodTimeStamp);
    event RewardsClaimed(address account, uint unclaimedReward);
    event FeeRewardsClaimed(address account, uint unclaimedFees);
    event UnstakeCooldown(address account, uint cooldownTime, uint amount);
    event CancelUnstake(address account);
    event Unstaked(address account, uint unstakeAmount);
    event ClaimEnabled(bool enabled);
    event DistributeFeesEnabled(bool enabled);
    event FixedPeriodRewardChanged(uint value);
    event PeriodExtraRewardChanged(uint value);
    event DurationPeriodChanged(uint value);
    event UnstakeDurationPeriodChanged(uint value);
    event EscrowChanged(address newEscrow);
    event StakingPeriodStarted();
    event SNXRewardsAddressChanged(address snxRewards);
    event ThalesRoyaleAddressChanged(address royale);
    event ThalesAMMAddressChanged(address amm);
    event ThalesRangedAMMAddressChanged(address amm);
    event ThalesSportsAMMAddressChanged(address amm);
    event AMMVolumeUpdated(address account, uint amount);
    event ExtraRewardsChanged(bool extrarewardsactive);
    event PriceFeedAddressChanged(address pricefeed);
    event MaxSNXRewardsPercentageChanged(uint maxSnxRewardsPercentage);
    event AMMVolumeRewardsMultiplierChanged(uint ammVolumeRewardsMultiplier);
    event MaxAMMVolumeRewardsPercentageChanged(uint maxAmmVolumeRewardsPercentage);
    event MaxThalesRoyaleRewardsPercentageChanged(uint maxThalesRewardsPercentage);
    event ThalesStakingRewardsPoolChanged(address thalesStakingRewardsPool);
    event SNXVolumeRewardsMultiplierChanged(uint ammVolumeRewardsMultiplier);
    event AddressResolverChanged(address addressResolver);
    event ExoticBondsAddressChanged(address exoticBonds);
}
