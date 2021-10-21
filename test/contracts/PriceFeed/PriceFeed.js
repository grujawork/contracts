'use strict';

const { artifacts, contract, web3 } = require('hardhat');

const { assert } = require('../../utils/common');

const { currentTime, toUnit, bytesToString } = require('../../utils')();

const { onlyGivenAddressCanInvoke, convertToDecimals } = require('../../utils/helpers');

const { toBytes32 } = require('../../../index');
const { setupAllContracts } = require('../../utils/setup');

const ZERO_ADDRESS = '0x' + '0'.repeat(40);

const MockAggregator = artifacts.require('MockAggregatorV2V3');

contract('Price Feed', async accounts => {
	const [deployerAccount, owner, oracle, accountOne, accountTwo] = accounts;
	const [SNX, JPY, XTZ, BNB, sUSD, EUR, LINK, fastGasPrice] = [
		'SNX',
		'JPY',
		'XTZ',
		'BNB',
		'sUSD',
		'EUR',
		'LINK',
		'fastGasPrice',
	].map(toBytes32);
	let instance;
	let aggregatorJPY;
	let aggregatorXTZ;
	let aggregatorLINK;
	let aggregatorFastGasPrice;
	let initialTime;
	let timeSent;

	before(async () => {
		initialTime = await currentTime();
		({ PriceFeed: instance } = await setupAllContracts({
			accounts,
			contracts: ['PriceFeed'],
		}));

		aggregatorJPY = await MockAggregator.new({ from: owner });
		aggregatorXTZ = await MockAggregator.new({ from: owner });
		aggregatorLINK = await MockAggregator.new({ from: owner });
		aggregatorFastGasPrice = await MockAggregator.new({ from: owner });

		aggregatorJPY.setDecimals('8');
		aggregatorXTZ.setDecimals('8');
		aggregatorLINK.setDecimals('8');
		aggregatorFastGasPrice.setDecimals('0');
	});

	beforeEach(async () => {
		timeSent = await currentTime();
	});

	describe('pricing aggregators', () => {
		describe('When an aggregator with more than 18 decimals is added', () => {
			it('an aggregator should return a value with 18 decimals or less', async () => {
				const newAggregator = await MockAggregator.new({ from: owner });
				await newAggregator.setDecimals('19');
				await assert.revert(
					instance.addAggregator(JPY, newAggregator.address, {
						from: owner,
					}),
					'Aggregator decimals should be lower or equal to 18'
				);
			});
		});

		describe('when a user queries the first entry in aggregatorKeys', () => {
			it('then it is empty', async () => {
				await assert.invalidOpcode(instance.aggregatorKeys(0));
			});
		});

		describe('when the owner attempts to add an invalid address for JPY ', () => {
			it('then zero address is invalid', async () => {
				await assert.revert(
					instance.addAggregator(JPY, ZERO_ADDRESS, {
						from: owner,
					})
					// 'function call to a non-contract account' (this reason is not valid in Ganache so fails in coverage)
				);
			});
			it('and a non-aggregator address is invalid', async () => {
				await assert.revert(
					instance.addAggregator(JPY, instance.address, {
						from: owner,
					})
					// 'function selector was not recognized'  (this reason is not valid in Ganache so fails in coverage)
				);
			});
		});

		describe('when the owner adds JPY added as an aggregator', () => {
			let txn;
			beforeEach(async () => {
				txn = await instance.addAggregator(JPY, aggregatorJPY.address, {
					from: owner,
				});
			});

			it('then the list of aggregatorKeys lists it', async () => {
				assert.equal('JPY', bytesToString(await instance.aggregatorKeys(0)));
				await assert.invalidOpcode(instance.aggregatorKeys(1));
			});

			it('and the AggregatorAdded event is emitted', () => {
				assert.eventEqual(txn, 'AggregatorAdded', {
					currencyKey: JPY,
					aggregator: aggregatorJPY.address,
				});
			});

			it('only an owner can remove an aggregator', async () => {
				await onlyGivenAddressCanInvoke({
					fnc: instance.removeAggregator,
					args: [JPY],
					accounts,
					address: owner,
				});
			});

			describe('when the owner adds the same aggregator to two other rates', () => {
				beforeEach(async () => {
					await instance.addAggregator(EUR, aggregatorJPY.address, {
						from: owner,
					});
					await instance.addAggregator(BNB, aggregatorJPY.address, {
						from: owner,
					});
				});
			});
			describe('when the owner tries to remove an invalid aggregator', () => {
				it('then it reverts', async () => {
					await assert.revert(
						instance.removeAggregator(XTZ, { from: owner }),
						'No aggregator exists for key'
					);
				});
			});

			describe('when the owner adds XTZ as an aggregator', () => {
				beforeEach(async () => {
					txn = await instance.addAggregator(XTZ, aggregatorXTZ.address, {
						from: owner,
					});
				});

				it('then the list of aggregatorKeys lists it also', async () => {
					assert.equal('JPY', bytesToString(await instance.aggregatorKeys(0)));
					assert.equal('XTZ', bytesToString(await instance.aggregatorKeys(1)));
					await assert.invalidOpcode(instance.aggregatorKeys(2));
				});

				it('and the AggregatorAdded event is emitted', () => {
					assert.eventEqual(txn, 'AggregatorAdded', {
						currencyKey: XTZ,
						aggregator: aggregatorXTZ.address,
					});
				});
			});

			describe('when the aggregator price is set to set a specific number (with support for 8 decimals)', () => {
				const newRate = 123.456;
				let timestamp;
				beforeEach(async () => {
					timestamp = await currentTime();
					// Multiply by 1e8 to match Chainlink's price aggregation
					await aggregatorJPY.setLatestAnswer(convertToDecimals(newRate, 8), timestamp);
				});

				describe('when the price is fetched for JPY', () => {
					it('the specific number is returned with 18 decimals', async () => {
						const result = await instance.rateForCurrency(JPY, {
							from: accountOne,
						});
						assert.bnEqual(result, toUnit(newRate.toString()));
					});
					it('and the timestamp is the latest', async () => {
						const result = await instance.rateAndUpdatedTime(JPY, {
							from: accountOne,
						});
						assert.bnEqual(result.time.toNumber(), timestamp);
					});
				});
			});

			describe('when the aggregator price is set to set a specific number, other than 8 decimals', () => {
				const gasPrice = 189.9;
				let timestamp;
				beforeEach(async () => {
					await instance.addAggregator(fastGasPrice, aggregatorFastGasPrice.address, {
						from: owner,
					});
					timestamp = await currentTime();
					// fastGasPrice has no decimals, so no conversion needed
					await aggregatorFastGasPrice.setLatestAnswer(
						web3.utils.toWei(gasPrice.toString(), 'gwei'),
						timestamp
					);
				});

				describe('when the price is fetched for fastGasPrice', () => {
					it('the specific number is returned with 18 decimals', async () => {
						const result = await instance.rateForCurrency(fastGasPrice, {
							from: accountOne,
						});
						assert.bnEqual(result, web3.utils.toWei(gasPrice.toString(), 'gwei'));
					});
					it('and the timestamp is the latest', async () => {
						const result = await instance.rateAndUpdatedTime(fastGasPrice, {
							from: accountOne,
						});
						assert.bnEqual(result.time.toNumber(), timestamp);
					});
				});
			});
		});
	});
});