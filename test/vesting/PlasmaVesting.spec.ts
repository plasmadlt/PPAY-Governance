import chai, { expect } from 'chai'
import { Contract, BigNumber } from 'ethers'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'

import PlasmaVesting from '../../build/PlasmaVesting.json'

import { governanceFixture } from '../fixtures'
import { mineBlock, expandTo18Decimals } from '../utils'

chai.use(solidity)

describe('scenario:PlasmaVesting', () => {
  const provider = new MockProvider({
    ganacheOptions: {
      hardfork: 'istanbul',
      mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
      gasLimit: 9999999,
    },
  })
  const [wallet] = provider.getWallets()
  const loadFixture = createFixtureLoader([wallet], provider)

  let ppay: Contract
  let timelock: Contract
  beforeEach(async () => {
    const fixture = await loadFixture(governanceFixture)
    ppay = fixture.ppay
    timelock = fixture.timelock
  })

  let plasmaVesting: Contract
  let vestingAmount: BigNumber
  let vestingBegin: number
  let vestingCliff: number
  let vestingEnd: number
  beforeEach('deploy plasma vesting contract', async () => {
    const { timestamp: now } = await provider.getBlock('latest')
    vestingAmount = expandTo18Decimals(100)
    vestingBegin = now + 60
    vestingCliff = vestingBegin + 60
    vestingEnd = vestingBegin + 60 * 60 * 24 * 365
    plasmaVesting = await deployContract(wallet, PlasmaVesting, [
      ppay.address,
      timelock.address,
      vestingAmount,
      vestingBegin,
      vestingCliff,
      vestingEnd,
    ])

    // fund the plasma
    await ppay.transfer(plasmaVesting.address, vestingAmount)
  })

  it('setRecipient:fail', async () => {
    await expect(plasmaVesting.setRecipient(wallet.address)).to.be.revertedWith(
      'PlasmaVesting::setRecipient: unauthorized'
    )
  })

  it('claim:fail', async () => {
    await expect(plasmaVesting.claim()).to.be.revertedWith('PlasmaVesting::claim: not time yet')
    await mineBlock(provider, vestingBegin + 1)
    await expect(plasmaVesting.claim()).to.be.revertedWith('PlasmaVesting::claim: not time yet')
  })

  it('claim:~half', async () => {
    await mineBlock(provider, vestingBegin + Math.floor((vestingEnd - vestingBegin) / 2))
    await plasmaVesting.claim()
    const balance = await ppay.balanceOf(timelock.address)
    expect(vestingAmount.div(2).sub(balance).abs().lte(vestingAmount.div(2).div(10000))).to.be.true
  })

  it('claim:all', async () => {
    await mineBlock(provider, vestingEnd)
    await plasmaVesting.claim()
    const balance = await ppay.balanceOf(timelock.address)
    expect(balance).to.be.eq(vestingAmount)
  })
})
