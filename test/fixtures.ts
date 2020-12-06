import chai, { expect } from 'chai'
import { Contract, Wallet, providers } from 'ethers'
import { solidity, deployContract } from 'ethereum-waffle'

import Ppay from '../build/Ppay.json'
import Timelock from '../build/Timelock.json'
import GovernorPlasma from '../build/GovernorPlasma.json'

import { DELAY } from './utils'

chai.use(solidity)

interface GovernanceFixture {
  ppay: Contract
  timelock: Contract
  governorPlasma: Contract
}

export async function governanceFixture(
  [wallet]: Wallet[],
  provider: providers.Web3Provider
): Promise<GovernanceFixture> {
  // deploy PPAY, sending the total supply to the deployer
  const { timestamp: now } = await provider.getBlock('latest')
  const timelockAddress = Contract.getContractAddress({ from: wallet.address, nonce: 1 })
  const ppay = await deployContract(wallet, Ppay, [wallet.address])

  // deploy timelock, controlled by what will be the governor
  const governorPlasmaAddress = Contract.getContractAddress({ from: wallet.address, nonce: 2 })
  const timelock = await deployContract(wallet, Timelock, [governorPlasmaAddress, DELAY])
  expect(timelock.address).to.be.eq(timelockAddress)

  // deploy governorPlasma
  const governorPlasma = await deployContract(wallet, GovernorPlasma, [timelock.address, ppay.address])
  expect(governorPlasma.address).to.be.eq(governorPlasmaAddress)

  return { ppay, timelock, governorPlasma }
}
