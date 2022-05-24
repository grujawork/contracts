'use strict';

const { artifacts, contract, web3 } = require('hardhat');
const { toBN } = web3.utils;

const { assert, addSnapshotBeforeRestoreAfterEach } = require('../../utils/common');

const { toBytes32 } = require('../../../index');

var ethers2 = require('ethers');
var crypto = require('crypto');

const SECOND = 1000;
const HOUR = 3600;
const DAY = 86400;
const WEEK = 604800;
const YEAR = 31556926;

const {
	fastForward,
	toUnit,
	fromUnit,
	currentTime,
	bytesToString,
	multiplyDecimalRound,
	divideDecimalRound,
} = require('../../utils')();

const {
	onlyGivenAddressCanInvoke,
	convertToDecimals,
	encodeCall,
	assertRevert,
} = require('../../utils/helpers');

contract('SportsAMM', accounts => {
	const [manager, first, owner, second, third, fourth, safeBox, wrapper] = accounts;

	const ZERO_ADDRESS = '0x' + '0'.repeat(40);
	const MAX_NUMBER =
		'115792089237316195423570985008687907853269984665640564039457584007913129639935';

	const SportPositionContract = artifacts.require('SportPosition');
	const SportPositionalMarketContract = artifacts.require('SportPositionalMarket');
	const SportPositionalMarketDataContract = artifacts.require('SportPositionalMarketData');
	const SportPositionalMarketManagerContract = artifacts.require('SportPositionalMarketManager');
	const SportPositionalMarketFactoryContract = artifacts.require('SportPositionalMarketFactory');
	const StakingThalesContract = artifacts.require('StakingThales');
    const SportsAMMContract = artifacts.require('SportsAMM');
	const ThalesContract = artifacts.require('contracts/Token/OpThales_L1.sol:OpThales');
	const ThalesBondsContract = artifacts.require('ThalesBonds');
	const ExoticPositionalTagsContract = artifacts.require('ExoticPositionalTags');
	const SNXRewardsContract = artifacts.require('SNXRewards');
	const AddressResolverContract = artifacts.require('AddressResolverHelper');
	let ExoticPositionalMarket;
	let ExoticPositionalOpenBidMarket;
	let ExoticPositionalMarketManager;
	let ExoticPositionalTags;
	let ThalesOracleCouncil;
	let Thales;
	let ThalesBonds;
	let answer;
	let minimumPositioningDuration = 0;
	let minimumMarketMaturityDuration = 0;

	let marketQuestion,
		marketSource,
		endOfPositioning,
		fixedTicketPrice,
		positionAmount1,
		positionAmount2,
		positionAmount3,
		withdrawalAllowed,
		tag,
		paymentToken,
		phrases = [],
		deployedMarket,
		fixedBondAmount,
		outcomePosition,
		outcomePosition2;

	let consumer;
	let TherundownConsumer;
	let TherundownConsumerImplementation;
	let TherundownConsumerDeployed;
	let MockExoticMarket;
	let MockTherundownConsumerWrapper;
	let initializeConsumerData;
	let gamesQueue;
	let game_1_create;
	let game_1_resolve;
	let gameid1;
	let oddsid;
	let oddsResult;
	let oddsResultArray;
	let reqIdOdds;
	let gameid2;
	let gameid3;
	let game_2_create;
	let game_2_resolve;
	let gamesCreated;
	let gamesResolved;
	let reqIdCreate;
	let reqIdResolve;
	let reqIdFootballCreate;
	let reqIdFootballCreate2;
	let gameFootballid1;
	let gameFootballid2;
	let gameFootballid3;
	let game_1_football_create;
	let game_2_football_create;
	let game_3_football_create;
	let gamesFootballCreated;
	let game_1_football_resolve;
	let game_2_football_resolve;
	let reqIdResolveFoodball;
	let gamesResolvedFootball;
	

    let SportPositionalMarketManager,
        SportPositionalMarketFactory,
        SportPositionalMarketData,
        SportPositionalMarket,
        SportPositionalMarketMastercopy,
        SportPositionMastercopy,
		StakingThales,
		SNXRewards,
		AddressResolver,
        SportsAMM;

	const game1NBATime = 1646958600;
	const gameFootballTime = 1649876400;

	const sportId_4 = 4; // NBA
	const sportId_16 = 16; // CHL

	let gameMarket;

	beforeEach(async () => {

        SportPositionalMarketManager = await SportPositionalMarketManagerContract.new({from:manager});
        SportPositionalMarketFactory = await SportPositionalMarketFactoryContract.new({from:manager});
        SportPositionalMarketMastercopy = await SportPositionalMarketContract.new({from:manager});
        SportPositionMastercopy = await SportPositionContract.new({from:manager});
        SportPositionalMarketData = await SportPositionalMarketDataContract.new({from:manager});
        StakingThales = await StakingThalesContract.new({from:manager});
        SportsAMM = await SportsAMMContract.new({from:manager});
        SNXRewards = await SNXRewardsContract.new({from:manager});
		AddressResolver = await AddressResolverContract.new();
		await AddressResolver.setSNXRewardsAddress(SNXRewards.address);

		Thales = await ThalesContract.new({ from: owner });
		ExoticPositionalTags = await ExoticPositionalTagsContract.new();
		await ExoticPositionalTags.initialize(manager, { from: manager });
		let GamesQueue = artifacts.require('GamesQueue');
		gamesQueue = await GamesQueue.new({from:owner});
		await gamesQueue.initialize(owner, { from: owner });

		await SportPositionalMarketManager.initialize(manager, Thales.address, {from: manager});
		await SportPositionalMarketFactory.initialize(manager, {from: manager});
        
        await SportPositionalMarketFactory.setPositionalMarketManager(SportPositionalMarketManager.address, {from:manager});
        await SportPositionalMarketFactory.setPositionalMarketMastercopy(SportPositionalMarketMastercopy.address, {from:manager});
        await SportPositionalMarketFactory.setPositionMastercopy(SportPositionMastercopy.address, {from:manager});
        await SportPositionalMarketFactory.setLimitOrderProvider(SportsAMM.address, {from:manager});
        await SportPositionalMarketFactory.setThalesAMM(SportsAMM.address, {from:manager});
        await SportPositionalMarketManager.setPositionalMarketFactory(SportPositionalMarketFactory.address, {from:manager});
        
		await SportsAMM.initialize(
			owner,
			Thales.address,
			toUnit('5000'),
			toUnit('0.02'),
			toUnit('0.2'),
			DAY,
			{from:owner});

		await SportsAMM.setPositionalMarketManager(SportPositionalMarketManager.address, {from:owner});
		await SportsAMM.setStakingThales(StakingThales.address, {from:owner});
		await StakingThales.initialize(
			owner,
			Thales.address,
			Thales.address,
			Thales.address,
			WEEK,
			WEEK,
			SNXRewards.address,
			{from:owner}
		);
		await StakingThales.setThalesAMM(SportsAMM.address, {from:owner});
		await SportsAMM.setMinSupportedPrice(10, {from:owner});
		await SportsAMM.setMaxSupportedPrice(toUnit(1000), {from:owner});
		
		await Thales.transfer(first, toUnit('1000'), { from: owner });
		await Thales.transfer(second, toUnit('1000'), { from: owner });
		await Thales.transfer(third, toUnit('1000'), { from: owner });
		await Thales.transfer(SportsAMM.address, toUnit('100000'), { from: owner });

		await Thales.approve(SportsAMM.address, toUnit('1000'), { from: first });
		await Thales.approve(SportsAMM.address, toUnit('1000'), { from: second });
		await Thales.approve(SportsAMM.address, toUnit('1000'), { from: third });

		await ExoticPositionalTags.addTag('Sport', '1');
		await ExoticPositionalTags.addTag('Football', '101');
		await ExoticPositionalTags.addTag('Basketball', '102');
		
		// ids
		gameid1 = '0x6536306366613738303834366166363839373862343935373965356366333936';
		gameid2 = '0x3937346533663036386233333764313239656435633133646632376133326662';

		// create game props
		game_1_create =
			'0x0000000000000000000000000000000000000000000000000000000000000020653630636661373830383436616636383937386234393537396535636633393600000000000000000000000000000000000000000000000000000000625755f0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffaf240000000000000000000000000000000000000000000000000000000000004524ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffaf2400000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000000d41746c616e7461204861776b73000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011436861726c6f74746520486f726e657473000000000000000000000000000000';
			game_2_create =
			'0x0000000000000000000000000000000000000000000000000000000000000020393734653366303638623333376431323965643563313364663237613332666200000000000000000000000000000000000000000000000000000000625755f0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffaf240000000000000000000000000000000000000000000000000000000000004524ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffaf2400000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000000d41746c616e7461204861776b73000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011436861726c6f74746520486f726e657473000000000000000000000000000000';
			gamesCreated = [game_1_create, game_2_create];
			reqIdCreate = '0x65da2443ccd66b09d4e2693933e8fb9aab9addf46fb93300bd7c1d70c5e21666';

			// resolve game props
		reqIdResolve = '0x30250573c4b099aeaf06273ef9fbdfe32ab2d6b8e33420de988be5d6886c92a7';
		game_1_resolve =
        '0x6536306366613738303834366166363839373862343935373965356366333936000000000000000000000000000000000000000000000000000000000000006400000000000000000000000000000000000000000000000000000000000000810000000000000000000000000000000000000000000000000000000000000008';
		game_2_resolve =
        '0x3937346533663036386233333764313239656435633133646632376133326662000000000000000000000000000000000000000000000000000000000000006600000000000000000000000000000000000000000000000000000000000000710000000000000000000000000000000000000000000000000000000000000008';
		gamesResolved = [game_1_resolve, game_2_resolve];
        
		// football matches
		reqIdFootballCreate = '0x61d7dd698383c58c7217cf366764a1e92a1f059b1b6ea799dce4030a942302f4';
		reqIdFootballCreate2 = '0x47e3535f7d3c146606fa6bcc06d95eb74f0bf8eac7d0d9c352814ee4c726d194';
		gameFootballid1 = '0x3163626162623163303138373465363263313661316462333164363164353333';
		gameFootballid2 = '0x3662646437313731316337393837643336643465333538643937393237356234';
		gameFootballid3 = '0x6535303439326161636538313035666362316531366364373664383963643361';
		game_1_football_create =
			'0x000000000000000000000000000000000000000000000000000000000000002031636261626231633031383734653632633136613164623331643631643533330000000000000000000000000000000000000000000000000000000062571db00000000000000000000000000000000000000000000000000000000000009c40ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffcf2c0000000000000000000000000000000000000000000000000000000000006a4000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000001f41746c657469636f204d61647269642041746c657469636f204d616472696400000000000000000000000000000000000000000000000000000000000000001f4d616e636865737465722043697479204d616e63686573746572204369747900';
		game_2_football_create =
			'0x000000000000000000000000000000000000000000000000000000000000002036626464373137313163373938376433366434653335386439373932373562340000000000000000000000000000000000000000000000000000000062571db0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff76800000000000000000000000000000000000000000000000000000000000018c18000000000000000000000000000000000000000000000000000000000000cb2000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000134c69766572706f6f6c204c69766572706f6f6c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f42656e666963612042656e666963610000000000000000000000000000000000';
		game_3_football_create =
			'0x0000000000000000000000000000000000000000000000000000000000000020653530343932616163653831303566636231653136636437366438396364336100000000000000000000000000000000000000000000000000000000629271300000000000000000000000000000000000000000000000000000000000002a3000000000000000000000000000000000000000000000000000000000000064c800000000000000000000000000000000000000000000000000000000000067e800000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000134c69766572706f6f6c204c69766572706f6f6c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000175265616c204d6164726964205265616c204d6164726964000000000000000000';
		gamesFootballCreated = [game_1_football_create, game_2_football_create, game_3_football_create];
		game_1_football_resolve =
			'0x316362616262316330313837346536326331366131646233316436316435333300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000b';
		game_2_football_resolve =
        '0x366264643731373131633739383764333664346533353864393739323735623400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000b';
		reqIdResolveFoodball = '0xff8887a8535b7a8030962e6f6b1eba61c0f1cb82f706e77d834f15c781e47697';
		gamesResolvedFootball = [game_1_football_resolve, game_2_football_resolve];

		oddsid = '0x6135363061373861363135353239363137366237393232353866616336613532';
		oddsResult = '0x6135363061373861363135353239363137366237393232353866616336613532000000000000000000000000000000000000000000000000000000000000283cffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd3dc0000000000000000000000000000000000000000000000000000000000000000';
		oddsResultArray = [oddsResult];
		reqIdOdds = '0x5bf0ea636f9515e1e1060e5a21e11ef8a628fa99b1effb8aa18624b02c6f36de';
		// reqIdOdds2 = '';
        
		TherundownConsumer = artifacts.require('TherundownConsumer');
		TherundownConsumerDeployed = await TherundownConsumer.new();
        
		await TherundownConsumerDeployed.initialize(
            owner,
			[sportId_4, sportId_16],
			SportPositionalMarketManager.address,
			[sportId_4],
			gamesQueue.address,
			[8, 12], // resolved statuses 
			[1, 2], // cancel statuses
			{ from: owner }
            );
			
		await Thales.transfer(TherundownConsumerDeployed.address, toUnit('1000'), { from: owner });
		// await ExoticPositionalMarketManager.setTheRundownConsumerAddress(
			// 	TherundownConsumerDeployed.address
				// );
		await TherundownConsumerDeployed.setWrapperAddress(wrapper, { from: owner });
        await TherundownConsumerDeployed.addToWhitelist(third, { from: owner });
		await SportsAMM.setTherundownConsumer(TherundownConsumerDeployed.address, {from:owner});
        
        await SportPositionalMarketManager.setTherundownConsumer(TherundownConsumerDeployed.address, {from:manager});
		await gamesQueue.setConsumerAddress(TherundownConsumerDeployed.address, { from: owner });
		
		
			
	});

	describe('Init', () => {
		it('Check init Therundown consumer', async () => {
			assert.equal(true, await TherundownConsumerDeployed.isSupportedSport(sportId_4));
			assert.equal(true, await TherundownConsumerDeployed.isSupportedSport(sportId_16));
			assert.equal(false, await TherundownConsumerDeployed.isSupportedSport(0));
			assert.equal(false, await TherundownConsumerDeployed.isSupportedSport(1));

			assert.equal(true, await TherundownConsumerDeployed.isSportTwoPositionsSport(sportId_4));
			assert.equal(false, await TherundownConsumerDeployed.isSportTwoPositionsSport(sportId_16));
			assert.equal(false, await TherundownConsumerDeployed.isSportTwoPositionsSport(7));

			assert.equal(true, await TherundownConsumerDeployed.isSupportedMarketType('create'));
			assert.equal(true, await TherundownConsumerDeployed.isSupportedMarketType('resolve'));
			assert.equal(false, await TherundownConsumerDeployed.isSupportedMarketType('aaa'));

			assert.equal(true, await TherundownConsumerDeployed.isSameTeamOrTBD('Real Madrid', 'Real Madrid'));
			assert.equal(true, await TherundownConsumerDeployed.isSameTeamOrTBD('Real Madrid', 'TBD TBD'));
			assert.equal(true, await TherundownConsumerDeployed.isSameTeamOrTBD('TBD TBD', 'Liverpool FC'));
			assert.equal(false, await TherundownConsumerDeployed.isSameTeamOrTBD('Real Madrid', 'Liverpool FC'));


			assert.equal(true, await TherundownConsumerDeployed.suportResolveGameStatuses(8));
			assert.equal(false, await TherundownConsumerDeployed.suportResolveGameStatuses(1));

			assert.equal(false, await TherundownConsumerDeployed.cancelGameStatuses(8));
			assert.equal(true, await TherundownConsumerDeployed.cancelGameStatuses(1));
		});
	});

	describe('Create games markets', () => {
		it('Fulfill Games Created - NBA, create market, check results', async () => {
			await fastForward(game1NBATime - (await currentTime()) - SECOND);

			// req. games
			const tx = await TherundownConsumerDeployed.fulfillGamesCreated(
				reqIdCreate,
				gamesCreated,
				sportId_4,
				{ from: wrapper }
			);

			assert.equal(gameid1, await gamesQueue.gamesCreateQueue(1));
			assert.equal(gameid2, await gamesQueue.gamesCreateQueue(2));

			assert.equal(2, await gamesQueue.getLengthUnproccessedGames());
			assert.equal(0, await gamesQueue.unproccessedGamesIndex(gameid1));
			assert.equal(1, await gamesQueue.unproccessedGamesIndex(gameid2));
			assert.equal(sportId_4, await gamesQueue.sportPerGameId(gameid1));
			assert.equal(sportId_4, await gamesQueue.sportPerGameId(gameid2));
			assert.bnEqual(1649890800, await gamesQueue.gameStartPerGameId(gameid1));
			assert.bnEqual(1649890800, await gamesQueue.gameStartPerGameId(gameid2));

			assert.equal(true, await TherundownConsumerDeployed.isSportTwoPositionsSport(sportId_4));
			assert.equal(true, await TherundownConsumerDeployed.isSupportedSport(sportId_4));

			assert.bnEqual(-20700, await TherundownConsumerDeployed.getOddsHomeTeam(gameid1));
			assert.bnEqual(17700, await TherundownConsumerDeployed.getOddsAwayTeam(gameid1));

			assert.equal(
				game_1_create,
				await TherundownConsumerDeployed.requestIdGamesCreated(reqIdCreate, 0)
			);
			assert.equal(
				game_2_create,
				await TherundownConsumerDeployed.requestIdGamesCreated(reqIdCreate, 1)
			);

			let game = await TherundownConsumerDeployed.gameCreated(gameid1);
			let gameTime = game.startTime;
			assert.equal('Atlanta Hawks', game.homeTeam);
			assert.equal('Charlotte Hornets', game.awayTeam);

			// check if event is emited
			assert.eventEqual(tx.logs[0], 'GameCreated', {
				_requestId: reqIdCreate,
				_sportId: sportId_4,
				_id: gameid1,
				_game: game,
			});

			// create markets
			const tx_create = await TherundownConsumerDeployed.createMarketForGame(gameid1);

			let marketAdd = await TherundownConsumerDeployed.marketPerGameId(gameid1);

			// check if event is emited
			assert.eventEqual(tx_create.logs[1], 'CreateSportsMarket', {
				_marketAddress: marketAdd,
				_id: gameid1,
				_game: game,
			});

			let answer = await SportPositionalMarketManager.getActiveMarketAddress('0');
            deployedMarket = await SportPositionalMarketContract.at(answer);

            assert.equal(false, await deployedMarket.canResolve());
            assert.equal(9004, await deployedMarket.tags(0));

            assert.equal(2, await deployedMarket.optionsCount());

            await fastForward(await currentTime());

			assert.equal(true, await deployedMarket.canResolve());
            
            const tx_2 = await TherundownConsumerDeployed.fulfillGamesResolved(
				reqIdResolve,
				gamesResolved,
				sportId_4,
				{ from: wrapper }
			);

			assert.equal(
				game_1_resolve,
				await TherundownConsumerDeployed.requestIdGamesResolved(reqIdResolve, 0)
			);
			assert.equal(
				game_2_resolve,
				await TherundownConsumerDeployed.requestIdGamesResolved(reqIdResolve, 1)
			);

			let gameR = await TherundownConsumerDeployed.gameResolved(gameid1);
			assert.equal(100, gameR.homeScore);
			assert.equal(129, gameR.awayScore);
			assert.equal(8, gameR.statusId);

			assert.eventEqual(tx_2.logs[0], 'GameResolved', {
				_requestId: reqIdResolve,
				_sportId: sportId_4,
				_id: gameid1,
				_game: gameR,
			});

			// resolve markets
			const tx_resolve = await TherundownConsumerDeployed.resolveMarketForGame(gameid1);

			// check if event is emited
			assert.eventEqual(tx_resolve.logs[0], 'ResolveSportsMarket', {
				_marketAddress: marketAdd,
				_id: gameid1,
				_outcome: 2,
			});

			assert.equal(1, await gamesQueue.getLengthUnproccessedGames());
			assert.equal(0, await gamesQueue.unproccessedGamesIndex(gameid1));
			assert.equal(0, await gamesQueue.unproccessedGamesIndex(gameid2));

		});

		
	});

	describe('Test SportsAMM', () => {
		let deployedMarket;
		let answer;
		beforeEach(async () => {
			await fastForward(game1NBATime - (await currentTime()) - SECOND);
			// req. games
			const tx = await TherundownConsumerDeployed.fulfillGamesCreated(
				reqIdCreate,
				gamesCreated,
				sportId_4,
				{ from: wrapper }
			);

			
			let game = await TherundownConsumerDeployed.gameCreated(gameid1);
			let gameTime = game.startTime;
			await TherundownConsumerDeployed.createMarketForGame(gameid1);
			await TherundownConsumerDeployed.marketPerGameId(gameid1);
			answer = await SportPositionalMarketManager.getActiveMarketAddress('0');
            deployedMarket = await SportPositionalMarketContract.at(answer.toString());
		});
		
		it('Checking SportsAMM variables', async () => {
			assert.bnEqual(await SportsAMM.min_spread(), toUnit('0.02'));
			assert.bnEqual(await SportsAMM.max_spread(), toUnit('0.2'));
			assert.bnEqual(await SportsAMM.capPerMarket(), toUnit('5000'));
			assert.bnEqual(await SportsAMM.minimalTimeLeftToMaturity(), DAY);
		});
		
		it('Is market in AMM trading', async () => {
			answer = await SportsAMM.isMarketInAMMTrading(deployedMarket.address);
			assert.equal(answer, true);
		});

		it('Get cap per asset', async () => {
			answer = await SportsAMM.getCapPerAsset(gameid1);
			console.log("Game id 1 cap: ",answer.toString());
		});

		it('Get odds', async () => {
			answer = await SportsAMM.obtainOdds(deployedMarket.address, 0);
			let sumOfOdds = answer;
			console.log("Odds for pos 0: ",fromUnit(answer));
			answer = await SportsAMM.obtainOdds(deployedMarket.address, 1);
			sumOfOdds = sumOfOdds.add(answer);
			console.log("Odds for pos 1: ",fromUnit(answer));
			answer = await SportsAMM.obtainOdds(deployedMarket.address, 2);
			sumOfOdds = sumOfOdds.add(answer);
			console.log("Odds for pos 2: ",fromUnit(answer));
			console.log("Total odds: ",fromUnit(sumOfOdds));
		});
		
		it('Get american odds', async () => {
			answer = await TherundownConsumerDeployed.getOddsHomeTeam(gameid1);
			let sumOfOdds = answer;
			console.log("American Odds for pos 0: ",fromUnit(answer));
			answer = await TherundownConsumerDeployed.getOddsAwayTeam(gameid1);
			sumOfOdds = sumOfOdds.add(answer);
			console.log("American Odds for pos 1: ",fromUnit(answer));
			answer = await TherundownConsumerDeployed.getOddsDraw(gameid1);
			sumOfOdds = sumOfOdds.add(answer);
			console.log("American Odds for pos 2: ",fromUnit(answer));
		});
		
		it('Get price', async () => {
			answer = await SportsAMM.price(deployedMarket.address, 0);
			let sumOfPrices = answer;
			console.log("Price for pos 0: ",fromUnit(answer));
			sumOfPrices = sumOfPrices.add(answer);
			answer = await SportsAMM.price(deployedMarket.address, 1);
			console.log("Price for pos 1: ",fromUnit(answer));
			sumOfPrices = sumOfPrices.add(answer);
			answer = await SportsAMM.price(deployedMarket.address, 2);
			console.log("Price for pos 2: ",fromUnit(answer));
			console.log("Total price: ",fromUnit(sumOfPrices));
		});
		it('Get Available to buy from SportsAMM, position 1', async () => {
			answer = await SportsAMM.availableToBuyFromAMM(deployedMarket.address, 1);
			console.log("Available to buy: ",fromUnit(answer));
		});

		it('Get BuyQuote from SportsAMM, position 1, value: 100', async () => {
			answer = await SportsAMM.buyFromAmmQuote(deployedMarket.address, 1, toUnit(100));
			console.log("buyAMMQuote: ",fromUnit(answer));
		});
		
		it('Buy from SportsAMM, position 1, value: 100', async () => {
			let availableToBuy = await SportsAMM.availableToBuyFromAMM(deployedMarket.address, 1);
			let additionalSlippage = toUnit(0.01);
			let buyFromAmmQuote = await SportsAMM.buyFromAmmQuote(
				deployedMarket.address,
				1,
				toUnit(100)
				);
			answer = await Thales.balanceOf(first);
			let before_balance= answer;
			console.log("acc balance: ",fromUnit(answer));
			console.log("buyQuote: ",fromUnit(buyFromAmmQuote));
			answer = await SportsAMM.buyFromAMM(
				deployedMarket.address, 
				1, 
				toUnit(100),
				buyFromAmmQuote,
				additionalSlippage,
				{from: first}
				);
			answer = await Thales.balanceOf(first);
			console.log("acc after buy balance: ",fromUnit(answer));
			console.log("cost: ",fromUnit((before_balance.sub(answer))));
			let options = await deployedMarket.balancesOf(first);
			console.log("Balances",options[0].toString(), fromUnit(options[1]), options[2].toString());
			
		});
		let position = 0;
		let value = 100;
		it('Buy from SportsAMM, position '+position+', value: '+ value, async () => {
			let availableToBuy = await SportsAMM.availableToBuyFromAMM(deployedMarket.address, position);
			let additionalSlippage = toUnit(0.01);
			let buyFromAmmQuote = await SportsAMM.buyFromAmmQuote(
				deployedMarket.address,
				position,
				toUnit(value)
				);
			answer = await Thales.balanceOf(first);
			let before_balance= answer;
			console.log("acc balance: ",fromUnit(answer));
			console.log("buyQuote: ",fromUnit(buyFromAmmQuote));
			answer = await SportsAMM.buyFromAMM(
				deployedMarket.address, 
				position, 
				toUnit(value),
				buyFromAmmQuote,
				additionalSlippage,
				{from: first}
				);
			answer = await Thales.balanceOf(first);
			console.log("acc after buy balance: ",fromUnit(answer));
			console.log("cost: ",fromUnit((before_balance.sub(answer))));
			let options = await deployedMarket.balancesOf(first);
			console.log("Balances",fromUnit(options[position]));
			
		});
		
		it('Sell to SportsAMM, position '+position+', value: '+ value, async () => {
			beforeEach(async () => {
				let availableToBuy = await SportsAMM.availableToBuyFromAMM(deployedMarket.address, position);
				let additionalSlippage = toUnit(0.01);
				let buyFromAmmQuote = await SportsAMM.buyFromAmmQuote(
					deployedMarket.address,
					position,
					toUnit(value)
					);
				answer = await Thales.balanceOf(first);
				let before_balance= answer;
				console.log("acc balance: ",fromUnit(answer));
				console.log("buyQuote: ",fromUnit(buyFromAmmQuote));
				answer = await SportsAMM.buyFromAMM(
					deployedMarket.address, 
					position, 
					toUnit(value),
					buyFromAmmQuote,
					additionalSlippage,
					{from: first}
					);
			});
			// let availableToBuy = await SportsAMM.availableToBuyFromAMM(deployedMarket.address, position);
			let additionalSlippage = toUnit(0.01);
			let options = await deployedMarket.balancesOf(first);
			console.log("user balance of options: ", fromUnit(options[position]));
			// let sellToAmmQuote = await SportsAMM.sellToAmmQuote(
			// 	deployedMarket.address,
			// 	position,
			// 	options[position]
			// 	);
			// answer = await Thales.balanceOf(first);
			// let before_balance= answer;
			// console.log("acc balance: ",fromUnit(answer));
			// console.log("sellQuote: ",fromUnit(sellToAmmQuote));
			// answer = await SportsAMM.sellToAMM(
			// 	deployedMarket.address, 
			// 	position, 
			// 	options[position],
			// 	sellToAmmQuote,
			// 	additionalSlippage,
			// 	{from: first}
			// 	);
			// answer = await Thales.balanceOf(first);
			// console.log("acc after sell balance: ",fromUnit(answer));
			// console.log("cost: ",fromUnit((answer.sub(before_balance))));
			
		});

		


	});

	
});