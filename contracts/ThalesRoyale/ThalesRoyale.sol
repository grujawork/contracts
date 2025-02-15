// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// external
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

// interfaces
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IThalesRoyalePass.sol";
import "../interfaces/IThalesRoyalePassport.sol";
import "../interfaces/IPassportPosition.sol";

// internal
import "../utils/proxy/solidity-0.8.0/ProxyReentrancyGuard.sol";
import "../utils/proxy/solidity-0.8.0/ProxyOwned.sol";

contract ThalesRoyale is Initializable, ProxyOwned, PausableUpgradeable, ProxyReentrancyGuard {
    /* ========== LIBRARIES ========== */

    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== CONSTANTS =========== */

    uint public constant DOWN = 1;
    uint public constant UP = 2;

    /* ========== STATE VARIABLES ========== */

    IERC20Upgradeable public rewardToken;
    bytes32 public oracleKey;
    IPriceFeed public priceFeed;

    address public safeBox;
    uint public safeBoxPercentage;

    uint public rounds;
    uint public signUpPeriod;
    uint public roundChoosingLength;
    uint public roundLength;

    bool public nextSeasonStartsAutomatically;
    uint public pauseBetweenSeasonsTime;

    uint public roundTargetPrice;
    uint public buyInAmount;

    /* ========== SEASON VARIABLES ========== */

    uint public season;

    mapping(uint => uint) public rewardPerSeason;
    mapping(uint => uint) public signedUpPlayersCount;
    mapping(uint => uint) public roundInASeason;
    mapping(uint => bool) public seasonStarted;
    mapping(uint => bool) public seasonFinished;
    mapping(uint => uint) public seasonCreationTime;
    mapping(uint => bool) public royaleInSeasonStarted;
    mapping(uint => uint) public royaleSeasonEndTime;
    mapping(uint => uint) public roundInSeasonEndTime;
    mapping(uint => uint) public roundInASeasonStartTime;
    mapping(uint => address[]) public playersPerSeason;
    mapping(uint => mapping(address => uint256)) public playerSignedUpPerSeason;
    mapping(uint => mapping(uint => uint)) public roundResultPerSeason;
    mapping(uint => mapping(uint => uint)) public targetPricePerRoundPerSeason;
    mapping(uint => mapping(uint => uint)) public finalPricePerRoundPerSeason;
    mapping(uint => mapping(uint256 => mapping(uint256 => uint256))) public positionsPerRoundPerSeason;
    mapping(uint => mapping(uint => uint)) public totalPlayersPerRoundPerSeason;
    mapping(uint => mapping(uint => uint)) public eliminatedPerRoundPerSeason;

    mapping(uint => mapping(address => mapping(uint256 => uint256))) public positionInARoundPerSeason;
    mapping(uint => mapping(address => bool)) public rewardCollectedPerSeason;
    mapping(uint => uint) public rewardPerWinnerPerSeason;
    mapping(uint => uint) public unclaimedRewardPerSeason;

    IThalesRoyalePass public royalePass;
    mapping(uint => bytes32) public oracleKeyPerSeason;

    IThalesRoyalePassport public thalesRoyalePassport;

    mapping(uint => uint) public mintedTokensCount;
    mapping(uint => uint[]) public tokensPerSeason;
    mapping(uint => uint) public tokenSeason;
    mapping(uint => mapping(uint => uint256)) public tokensMintedPerSeason;
    mapping(uint => mapping(uint => uint)) public totalTokensPerRoundPerSeason;
    mapping(uint => mapping(uint256 => uint256)) public tokenPositionInARoundPerSeason;
    mapping(uint => IPassportPosition.Position[]) public tokenPositions;
    mapping(uint => bool) public tokenRewardCollectedPerSeason;

    /* ========== CONSTRUCTOR ========== */

    function initialize(
        address _owner,
        bytes32 _oracleKey,
        IPriceFeed _priceFeed,
        address _rewardToken,
        uint _rounds,
        uint _signUpPeriod,
        uint _roundChoosingLength,
        uint _roundLength,
        uint _buyInAmount,
        uint _pauseBetweenSeasonsTime,
        bool _nextSeasonStartsAutomatically
    ) external initializer {
        setOwner(_owner);
        initNonReentrant();
        oracleKey = _oracleKey;
        priceFeed = _priceFeed;
        rewardToken = IERC20Upgradeable(_rewardToken);
        rounds = _rounds;
        signUpPeriod = _signUpPeriod;
        roundChoosingLength = _roundChoosingLength;
        roundLength = _roundLength;
        buyInAmount = _buyInAmount;
        pauseBetweenSeasonsTime = _pauseBetweenSeasonsTime;
        nextSeasonStartsAutomatically = _nextSeasonStartsAutomatically;
    }

    /* ========== GAME ========== */

    function signUp() external playerCanSignUp {
        uint[] memory positions = new uint[](rounds);
        for(uint i = 0; i < positions.length; i++) {
            positions[i] = 0;
        }
        _signUpPlayer(msg.sender, positions, 0);
    }

    function signUpWithPosition(uint[] memory _positions) external playerCanSignUp {
        require(_positions.length == rounds, "Number of positions exceeds number of rounds");
        for(uint i = 0; i < _positions.length; i++) {
            require(_positions[i] == DOWN || _positions[i] == UP, "Position can only be 1 or 2");
        }
        _signUpPlayer(msg.sender, _positions, 0);
    }

    function signUpWithPass(uint passId) external playerCanSignUpWithPass(passId) {
        uint[] memory positions = new uint[](rounds);
        for(uint i = 0; i < positions.length; i++) {
            positions[i] = 0;
        }
        _signUpPlayer(msg.sender, positions, passId);
    }

    function signUpWithPassWithPosition(uint passId, uint[] memory _positions) external playerCanSignUpWithPass(passId) {
        require(_positions.length == rounds, "Number of positions exceeds number of rounds");
        for(uint i = 0; i < _positions.length; i++) {
            require(_positions[i] == DOWN || _positions[i] == UP, "Position can only be 1 or 2");
        }
        _signUpPlayer(msg.sender, _positions, passId);
    }

    function startRoyaleInASeason() external {
        require(block.timestamp > (seasonCreationTime[season] + signUpPeriod), "Can't start until signup period expires");
        require(mintedTokensCount[season] > 0, "Can not start, no tokens in a season");
        require(!royaleInSeasonStarted[season], "Already started");
        require(seasonStarted[season], "Season not started yet");

        roundTargetPrice = priceFeed.rateForCurrency(oracleKeyPerSeason[season]);
        roundInASeason[season] = 1;
        targetPricePerRoundPerSeason[season][roundInASeason[season]] = roundTargetPrice;
        royaleInSeasonStarted[season] = true;
        roundInASeasonStartTime[season] = block.timestamp;
        roundInSeasonEndTime[season] = roundInASeasonStartTime[season] + roundLength;
        totalTokensPerRoundPerSeason[season][roundInASeason[season]] = mintedTokensCount[season];

        unclaimedRewardPerSeason[season] = rewardPerSeason[season];

        emit RoyaleStarted(season, mintedTokensCount[season], rewardPerSeason[season]);
    }

    function takeAPosition(uint tokenId, uint position) external {
        require(position == DOWN || position == UP, "Position can only be 1 or 2");
        require(msg.sender == thalesRoyalePassport.ownerOf(tokenId), "Not an owner");
        require(season == tokenSeason[tokenId], "Wrong season");
        require(royaleInSeasonStarted[season], "Competition not started yet");
        require(!seasonFinished[season], "Competition finished");

        require(tokenPositionInARoundPerSeason[tokenId][roundInASeason[season]] != position, "Same position");

        if (roundInASeason[season] != 1) {
            require(isTokenAlive(tokenId),"Token no longer valid");
        }

        require(block.timestamp < roundInASeasonStartTime[season] + roundChoosingLength, "Round positioning finished");

        // this block is when sender change positions in a round - first reduce
        if (tokenPositionInARoundPerSeason[tokenId][roundInASeason[season]] == DOWN) {
            positionsPerRoundPerSeason[season][roundInASeason[season]][DOWN]--;
        } else if (tokenPositionInARoundPerSeason[tokenId][roundInASeason[season]] == UP) {
            positionsPerRoundPerSeason[season][roundInASeason[season]][UP]--;
        }

        _putPosition(msg.sender, season, roundInASeason[season], position, tokenId);
    }

    function closeRound() external {
        require(royaleInSeasonStarted[season], "Competition not started yet");
        require(!seasonFinished[season], "Competition finished");
        require(block.timestamp > (roundInASeasonStartTime[season] + roundLength), "Can't close round yet");

        uint currentSeasonRound = roundInASeason[season];
        uint nextRound = currentSeasonRound + 1;

        // getting price
        uint currentPriceFromOracle = priceFeed.rateForCurrency(oracleKeyPerSeason[season]);

        require(currentPriceFromOracle > 0, "Oracle Price must be larger than 0");

        uint stikePrice = roundTargetPrice;

        finalPricePerRoundPerSeason[season][currentSeasonRound] = currentPriceFromOracle;
        roundResultPerSeason[season][currentSeasonRound] = currentPriceFromOracle >= stikePrice ? UP : DOWN;
        uint losingResult = currentPriceFromOracle >= stikePrice ? DOWN : UP;
        roundTargetPrice = currentPriceFromOracle;

        uint winningPositionsPerRound =
            roundResultPerSeason[season][currentSeasonRound] == UP
                ? positionsPerRoundPerSeason[season][currentSeasonRound][UP]
                : positionsPerRoundPerSeason[season][currentSeasonRound][DOWN];

        if (nextRound <= rounds) {
            // setting total players for next round (round + 1) to be result of position in a previous round
            totalTokensPerRoundPerSeason[season][nextRound] = winningPositionsPerRound;
        }

        // setting eliminated players to be total players - number of winning players
        eliminatedPerRoundPerSeason[season][currentSeasonRound] =
            totalTokensPerRoundPerSeason[season][currentSeasonRound] -
            winningPositionsPerRound;

        _cleanPositions(losingResult, nextRound);

        // if no one is left no need to set values
        if (winningPositionsPerRound > 0) {
            roundInASeason[season] = nextRound;
            targetPricePerRoundPerSeason[season][nextRound] = roundTargetPrice;
        }

        if (nextRound > rounds || winningPositionsPerRound <= 1) {
            seasonFinished[season] = true;

            uint numberOfWinners = 0;

            // in no one is winner pick from lest round
            if (winningPositionsPerRound == 0) {
                numberOfWinners = totalTokensPerRoundPerSeason[season][currentSeasonRound];
                _populateReward(numberOfWinners);
            } else {
                // there is min 1 winner
                numberOfWinners = winningPositionsPerRound;
                _populateReward(numberOfWinners);
            }

            royaleSeasonEndTime[season] = block.timestamp;
            // first close previous round then royale
            emit RoundClosed(
                season,
                currentSeasonRound,
                roundResultPerSeason[season][currentSeasonRound],
                stikePrice,
                finalPricePerRoundPerSeason[season][currentSeasonRound],
                eliminatedPerRoundPerSeason[season][currentSeasonRound],
                numberOfWinners
            );
            emit RoyaleFinished(season, numberOfWinners, rewardPerWinnerPerSeason[season]);
        } else {
            roundInASeasonStartTime[season] = block.timestamp;
            roundInSeasonEndTime[season] = roundInASeasonStartTime[season] + roundLength;
            emit RoundClosed(
                season,
                currentSeasonRound,
                roundResultPerSeason[season][currentSeasonRound],
                stikePrice,
                finalPricePerRoundPerSeason[season][currentSeasonRound],
                eliminatedPerRoundPerSeason[season][currentSeasonRound],
                winningPositionsPerRound
            );
        }
    }

    function startNewSeason() external seasonCanStart {
        season = season + 1;
        seasonCreationTime[season] = block.timestamp;
        seasonStarted[season] = true;
        oracleKeyPerSeason[season] = oracleKey;

        emit NewSeasonStarted(season);
    }

    function claimRewardForSeason(uint _season, uint tokenId) external onlyWinners(_season, tokenId) {
        _claimRewardForSeason(msg.sender, _season, tokenId);
    }

    /* ========== VIEW ========== */

    function canCloseRound() public view returns (bool) {
        return
            royaleInSeasonStarted[season] &&
            !seasonFinished[season] &&
            block.timestamp > (roundInASeasonStartTime[season] + roundLength);
    }

    function canStartRoyale() public view returns (bool) {
        return
            seasonStarted[season] &&
            !royaleInSeasonStarted[season] &&
            block.timestamp > (seasonCreationTime[season] + signUpPeriod);
    }

    function canSeasonBeAutomaticallyStartedAfterSomePeriod() public view returns (bool) {
        return nextSeasonStartsAutomatically && (block.timestamp > seasonCreationTime[season] + pauseBetweenSeasonsTime);
    }

    function canStartNewSeason() public view returns (bool) {
        return canSeasonBeAutomaticallyStartedAfterSomePeriod() && (seasonFinished[season] || season == 0);
    }

    function hasParticipatedInCurrentOrLastRoyale(address _player) external view returns (bool) {
        if (season > 1) {
            return playerSignedUpPerSeason[season][_player] > 0 || playerSignedUpPerSeason[season - 1][_player] > 0;
        } else {
            return playerSignedUpPerSeason[season][_player] > 0;
        }
    }

    function isTokenAliveInASpecificSeason(uint tokenId, uint _season) public view returns (bool) {
        if(_season != tokenSeason[tokenId]) {
            return false;
        }
        if (roundInASeason[_season] > 1) {
            return (tokenPositionInARoundPerSeason[tokenId][roundInASeason[_season] - 1] ==
                roundResultPerSeason[_season][roundInASeason[_season] - 1]);
        } else {
            return tokensMintedPerSeason[_season][tokenId] != 0;
        }
    }

    function isTokenAlive(uint tokenId) public view returns (bool) {
        if(season != tokenSeason[tokenId]) {
            return false;
        }
        if (roundInASeason[season] > 1) {
            return (tokenPositionInARoundPerSeason[tokenId][roundInASeason[season] - 1] ==
                roundResultPerSeason[season][roundInASeason[season] - 1]);
        } else {
            return tokensMintedPerSeason[season][tokenId] != 0;
        }
    }

    function getTokensForSeason(uint _season) public view returns (uint[] memory) {
        return tokensPerSeason[_season];
    }

    function getTokenPositions(uint tokenId) public view returns (IPassportPosition.Position[] memory) {
        return tokenPositions[tokenId];
    }

    // deprecated from passport impl
    function getPlayersForSeason(uint _season) public view returns (address[] memory) {
        return playersPerSeason[_season];
    }

    function getBuyInAmount() public view returns (uint) {
        return buyInAmount;
    }

    /* ========== INTERNALS ========== */

    function _signUpPlayer(address _player, uint[] memory _positions, uint _passId) internal {
        uint tokenId = thalesRoyalePassport.safeMint(_player);
        tokenSeason[tokenId] = season;

        tokensMintedPerSeason[season][tokenId] = block.timestamp;
        tokensPerSeason[season].push(tokenId);
        mintedTokensCount[season]++;

        playerSignedUpPerSeason[season][_player] = block.timestamp;

        for(uint i = 0; i < _positions.length; i++){
            if(_positions[i] != 0) {
                _putPosition(_player, season, i+1, _positions[i], tokenId);
            }
        }
        if(_passId != 0) {
            _buyInWithPass(_player, _passId);
        } else {
            _buyIn(_player, buyInAmount);
        }

        emit SignedUpPassport(_player, tokenId, season, _positions);
    }

    function _putPosition(
        address _player,
        uint _season,
        uint _round,
        uint _position,
        uint _tokenId
    ) internal {
        // set value
        positionInARoundPerSeason[_season][_player][_round] = _position;
        // set token value
        tokenPositionInARoundPerSeason[_tokenId][_round] = _position;
        

        if(tokenPositions[_tokenId].length >= _round) {
            tokenPositions[_tokenId][_round - 1] = IPassportPosition.Position(_round, _position);   
        } else {
            tokenPositions[_tokenId].push(IPassportPosition.Position(_round, _position));
        }
        
        // add number of positions
        if (_position == UP) {
            positionsPerRoundPerSeason[_season][_round][_position]++;
        } else {
            positionsPerRoundPerSeason[_season][_round][_position]++;
        }

        emit TookAPositionPassport(_player, _tokenId, _season, _round, _position);
    }

    function _populateReward(uint numberOfWinners) internal {
        require(seasonFinished[season], "Royale must be finished");
        require(numberOfWinners > 0, "There is no alive players left in Royale");

        rewardPerWinnerPerSeason[season] = rewardPerSeason[season] / numberOfWinners;
    }

    function _buyIn(address _sender, uint _amount) internal {
        (uint amountBuyIn, uint amountSafeBox) = _calculateSafeBoxOnAmount(_amount);

        if (amountSafeBox > 0) {
            rewardToken.safeTransferFrom(_sender, safeBox, amountSafeBox);
        }

        rewardToken.safeTransferFrom(_sender, address(this), amountBuyIn);
        rewardPerSeason[season] += amountBuyIn;
    }

    function _buyInWithPass(address _player, uint _passId) internal {
        // burning pass
        royalePass.burnWithTransfer(_player, _passId);

        // increase reward
        rewardPerSeason[season] += buyInAmount;
    }

    function _calculateSafeBoxOnAmount(uint _amount) internal view returns (uint, uint) {
        uint amountSafeBox = 0;

        if (safeBoxPercentage > 0) {
            amountSafeBox = (_amount * safeBoxPercentage) / 100;
        }

        uint amountBuyIn = _amount - amountSafeBox;

        return (amountBuyIn, amountSafeBox);
    }

    function _claimRewardForSeason(address _winner, uint _season, uint _tokenId) internal {
        require(rewardPerSeason[_season] > 0, "Reward must be set");
        require(!tokenRewardCollectedPerSeason[_tokenId], "Reward already collected");
        require(rewardToken.balanceOf(address(this)) >= rewardPerWinnerPerSeason[_season], "Not enough balance for rewards");

        // set collected -> true
        tokenRewardCollectedPerSeason[_tokenId] = true;

        unclaimedRewardPerSeason[_season] = unclaimedRewardPerSeason[_season] - rewardPerWinnerPerSeason[_season];

        // transfering rewardPerToken
        rewardToken.safeTransfer(_winner, rewardPerWinnerPerSeason[_season]);

        // emit event
        emit RewardClaimedPassport(_season, _winner, _tokenId, rewardPerWinnerPerSeason[_season]);
    }

    function _putFunds(
        address _from,
        uint _amount,
        uint _season
    ) internal {
        rewardPerSeason[_season] = rewardPerSeason[_season] + _amount;
        unclaimedRewardPerSeason[_season] = unclaimedRewardPerSeason[_season] + _amount;
        rewardToken.safeTransferFrom(_from, address(this), _amount);
        emit PutFunds(_from, _season, _amount);
    }

    function _cleanPositions(uint _losingPosition, uint _nextRound) internal {
            
        uint[] memory tokens = tokensPerSeason[season];

        for(uint i = 0; i < tokens.length; i++){
            if(tokenPositionInARoundPerSeason[tokens[i]][_nextRound - 1] == _losingPosition
                || tokenPositionInARoundPerSeason[tokens[i]][_nextRound - 1] == 0){
                // decrease position count
                if (tokenPositionInARoundPerSeason[tokens[i]][_nextRound] == DOWN) {
                        positionsPerRoundPerSeason[season][_nextRound][DOWN]--;
                } else if (tokenPositionInARoundPerSeason[tokens[i]][_nextRound] == UP) {
                        positionsPerRoundPerSeason[season][_nextRound][UP]--;
                    }
                // setting 0 position
                tokenPositionInARoundPerSeason[tokens[i]][_nextRound] = 0;
            }
        }
    }

    /* ========== CONTRACT MANAGEMENT ========== */

    function putFunds(uint _amount, uint _season) external {
        require(_amount > 0, "Amount must be more then zero");
        require(_season >= season, "Cant put funds in a past");
        require(!seasonFinished[_season], "Season is finished");
        require(rewardToken.allowance(msg.sender, address(this)) >= _amount, "No allowance.");
        require(rewardToken.balanceOf(msg.sender) >= _amount, "No enough sUSD for buy in");

        _putFunds(msg.sender, _amount, _season);
    }

    function setNextSeasonStartsAutomatically(bool _nextSeasonStartsAutomatically) external onlyOwner {
        nextSeasonStartsAutomatically = _nextSeasonStartsAutomatically;
        emit NewNextSeasonStartsAutomatically(_nextSeasonStartsAutomatically);
    }

    function setPauseBetweenSeasonsTime(uint _pauseBetweenSeasonsTime) external onlyOwner {
        pauseBetweenSeasonsTime = _pauseBetweenSeasonsTime;
        emit NewPauseBetweenSeasonsTime(_pauseBetweenSeasonsTime);
    }

    function setSignUpPeriod(uint _signUpPeriod) external onlyOwner {
        signUpPeriod = _signUpPeriod;
        emit NewSignUpPeriod(_signUpPeriod);
    }

    function setRoundChoosingLength(uint _roundChoosingLength) external onlyOwner {
        roundChoosingLength = _roundChoosingLength;
        emit NewRoundChoosingLength(_roundChoosingLength);
    }

    function setRoundLength(uint _roundLength) external onlyOwner {
        roundLength = _roundLength;
        emit NewRoundLength(_roundLength);
    }

    function setPriceFeed(IPriceFeed _priceFeed) external onlyOwner {
        priceFeed = _priceFeed;
        emit NewPriceFeed(_priceFeed);
    }

    function setThalesRoyalePassport(IThalesRoyalePassport _thalesRoyalePassport) external onlyOwner {
        require(address(_thalesRoyalePassport) != address(0), "Invalid address");
        thalesRoyalePassport = _thalesRoyalePassport;
        emit NewThalesRoyalePassport(_thalesRoyalePassport);
    }

    function setBuyInAmount(uint _buyInAmount) external onlyOwner {
        buyInAmount = _buyInAmount;
        emit NewBuyInAmount(_buyInAmount);
    }

    function setSafeBoxPercentage(uint _safeBoxPercentage) external onlyOwner {
        require(_safeBoxPercentage <= 100, "Must be in between 0 and 100 %");
        safeBoxPercentage = _safeBoxPercentage;
        emit NewSafeBoxPercentage(_safeBoxPercentage);
    }

    function setSafeBox(address _safeBox) external onlyOwner {
        require(_safeBox != address(0), "Invalid address");
        safeBox = _safeBox;
        emit NewSafeBox(_safeBox);
    }

    function setRoyalePassAddress(address _royalePass) external onlyOwner {
        require(address(_royalePass) != address(0), "Invalid address");
        royalePass = IThalesRoyalePass(_royalePass);
        emit NewThalesRoyalePass(_royalePass);
    }

    function setOracleKey(bytes32 _oracleKey) external onlyOwner {
        oracleKey = _oracleKey;
        emit NewOracleKey(_oracleKey);
    }

    function setRewardToken(address _rewardToken) external onlyOwner {
        require(address(_rewardToken) != address(0), "Invalid address");
        rewardToken = IERC20Upgradeable(_rewardToken);
        emit NewRewardToken(_rewardToken);
    }

    function setNumberOfRounds(uint _rounds) external onlyOwner {
        rounds = _rounds;
        emit NewNumberOfRounds(_rounds);
    }

    /* ========== MODIFIERS ========== */

    modifier playerCanSignUp() {
        require(season > 0, "Initialize first season");
        require(block.timestamp < (seasonCreationTime[season] + signUpPeriod), "Sign up period has expired");
        require(rewardToken.balanceOf(msg.sender) >= buyInAmount, "No enough sUSD for buy in");
        require(rewardToken.allowance(msg.sender, address(this)) >= buyInAmount, "No allowance.");
        require(address(thalesRoyalePassport) != address(0), "ThalesRoyale Passport not set");
        _;
    }

    modifier playerCanSignUpWithPass(uint passId) {
        require(season > 0, "Initialize first season");
        require(block.timestamp < (seasonCreationTime[season] + signUpPeriod), "Sign up period has expired");
        require(royalePass.ownerOf(passId) == msg.sender, "Owner of the token not valid");
        require(rewardToken.balanceOf(address(royalePass)) >= buyInAmount, "No enough sUSD on royale pass contract");
        require(address(thalesRoyalePassport) != address(0), "ThalesRoyale Passport not set");
        _;
    }

    modifier seasonCanStart() {
        require(
            msg.sender == owner || canSeasonBeAutomaticallyStartedAfterSomePeriod(),
            "Only owner can start season before pause between two seasons"
        );
        require(seasonFinished[season] || season == 0, "Previous season must be finished");
        _;
    }

    modifier onlyWinners(uint _season, uint tokenId) {
        require(seasonFinished[_season], "Royale must be finished!");
        require(thalesRoyalePassport.ownerOf(tokenId) == msg.sender, "Not an owner");
        require(isTokenAliveInASpecificSeason(tokenId, _season), "Token is not alive");
        _;
    }

    /* ========== EVENTS ========== */

    event SignedUpPassport(address user, uint tokenId, uint season, uint[] positions);
    event SignedUp(address user, uint season, uint position); //deprecated from passport impl.
    event RoundClosed(
        uint season,
        uint round,
        uint result,
        uint strikePrice,
        uint finalPrice,
        uint numberOfEliminatedPlayers,
        uint numberOfWinningPlayers
    );
    event TookAPosition(address user, uint season, uint round, uint position); //deprecated from passport impl.
    event TookAPositionPassport(address user, uint tokenId, uint season, uint round, uint position);
    event RoyaleStarted(uint season, uint totalTokens, uint totalReward);
    event RoyaleFinished(uint season, uint numberOfWinners, uint rewardPerWinner);
    event RewardClaimedPassport(uint season, address winner, uint tokenId, uint reward);
    event RewardClaimed(uint season, address winner, uint reward); //deprecated from passport impl.
    event NewSeasonStarted(uint season);
    event NewBuyInAmount(uint buyInAmount);
    event NewPriceFeed(IPriceFeed priceFeed);
    event NewThalesRoyalePassport(IThalesRoyalePassport _thalesRoyalePassport);
    event NewRoundLength(uint roundLength);
    event NewRoundChoosingLength(uint roundChoosingLength);
    event NewPauseBetweenSeasonsTime(uint pauseBetweenSeasonsTime);
    event NewSignUpPeriod(uint signUpPeriod);
    event NewNextSeasonStartsAutomatically(bool nextSeasonStartsAutomatically);
    event PutFunds(address from, uint season, uint amount);
    event NewSafeBoxPercentage(uint _safeBoxPercentage);
    event NewSafeBox(address _safeBox);
    event NewThalesRoyalePass(address _royalePass);
    event NewOracleKey(bytes32 _oracleKey);
    event NewRewardToken(address _rewardToken);
    event NewNumberOfRounds(uint _rounds);
}
