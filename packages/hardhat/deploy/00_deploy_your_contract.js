// deploy/00_deploy_your_contract.js

const { ethers } = require("hardhat");

const localChainId = "31337";

// const sleep = (ms) =>
//   new Promise((r) =>
//     setTimeout(() => {
//       console.log(`waited for ${(ms / 1000).toFixed(3)} seconds`);
//       r();
//     }, ms)
//   );

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  await deploy("Balloons", {
    from: deployer,
    log: true,
  });

  const balloons = await ethers.getContract("Balloons", deployer);

  await deploy("DEX", {
    from: deployer,
    args: [balloons.address],
    log: true,
    waitConfirmations: 5,
  });

  const dex = await ethers.getContract("DEX", deployer);

  // Your address gets 10 balloons on deploy
  await balloons.transfer(
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    "" + 10 * 10 ** 18
  );

  console.log(
    "Approving DEX (" + dex.address + ") to take Balloons from main account..."
  );
  // If on testnet, make sure the deployer account has enough ETH
  await balloons.approve(dex.address, ethers.utils.parseEther("100"));
  // Init DEX on deploy:
  console.log("INIT exchange...");
  await dex.init(ethers.utils.parseEther("0.02"), {
    value: ethers.utils.parseEther("0.02"),
    gasLimit: 200000,
  });
};
module.exports.tags = ["Balloons", "DEX"];
