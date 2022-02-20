const fs = require("fs");


const getContractAddress = async () => {
  const addressesFile = __dirname + "/../frontend/src/contracts/contract-address.json";

  if (!fs.existsSync(addressesFile)) {
    console.error("You need to deploy your contract first");
    return;
  }

  const addressJson = fs.readFileSync(addressesFile);
  const address = JSON.parse(addressJson);

  if ((await ethers.provider.getCode(address.SuperFan)) === "0x") {
    console.error("You need to deploy your contract first");
    return;
  }

  return address.SuperFan;
}

// This file is only here to make interacting with the Dapp easier,
// feel free to ignore it if you don't need it.
task("greet", "Says hello to an address")
  .addPositionalParam("receiver", "The address that will receive them")
  .setAction(async ({ receiver }, { ethers }) => {
    console.log(`Hello ${receiver}`);
  });

task("createTier", "Creates a tier based on a flowRate")
  .addPositionalParam("flowRate", "the flow rate")
  .setAction(async ({ flowRate }, { ethers }) => {

    console.log(`Creating flowRate of ${flowRate}`);

    const address = await getContractAddress()

    const app = await ethers.getContractAt("SuperFan", address);
    const [sender] = await ethers.getSigners();

    const tierId = await app.nextTierId();
    await app.connect(sender).createTier(Number(flowRate));

    console.log(`Created new tier ${tierId} of flowRate ${flowRate}`);
  });

task("faucet", "Sends ETH and tokens to an address")
  .addPositionalParam("receiver", "The address that will receive them")
  .setAction(async ({ receiver }, { ethers }) => {
    if (network.name === "hardhat") {
      console.warn(
        "You are running the faucet task with Hardhat network, which" +
          "gets automatically created and destroyed every time. Use the Hardhat" +
          " option '--network localhost'"
      );
    }

    // const app = await ethers.getContractAt("SuperFan", address.SuperFan);
    const [sender] = await ethers.getSigners();

    const ethTx = await sender.sendTransaction({
      to: receiver,
      value: ethers.constants.WeiPerEther,
    });
    await ethTx.wait();

    // const tx = await token.transfer(receiver, 100);
    // await tx.wait();

    console.log(`Transferred 1 ETH and 100 tokens to ${receiver}`);
  });
