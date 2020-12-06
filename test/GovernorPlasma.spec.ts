import chai, { expect } from 'chai'
import { Contract, constants } from 'ethers'
import { solidity, MockProvider, createFixtureLoader } from 'ethereum-waffle'

import { governanceFixture } from './fixtures'
import { DELAY } from './utils'

chai.use(solidity)

describe('GovernorPlasma', () => {
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
  let governorPlasma: Contract
  beforeEach(async () => {
    const fixture = await loadFixture(governanceFixture)
    ppay = fixture.ppay
    timelock = fixture.timelock
    governorPlasma = fixture.governorPlasma
  })

  it('ppay', async () => {
    const balance = await ppay.balanceOf(wallet.address)
    const totalSupply = await ppay.totalSupply()
    expect(balance).to.be.eq(totalSupply)
  })

  it('timelock', async () => {
    const admin = await timelock.admin()
    expect(admin).to.be.eq(governorPlasma.address)
    const pendingAdmin = await timelock.pendingAdmin()
    expect(pendingAdmin).to.be.eq(constants.AddressZero)
    const delay = await timelock.delay()
    expect(delay).to.be.eq(DELAY)
  })

  it('governor', async () => {
    const votingPeriod = await governorPlasma.votingPeriod()
    expect(votingPeriod).to.be.eq(40320)
    const timelockAddress = await governorPlasma.timelock()
    expect(timelockAddress).to.be.eq(timelock.address)
    const ppayFromGovernor = await governorPlasma.ppay()
    expect(ppayFromGovernor).to.be.eq(ppay.address)
  })
})
