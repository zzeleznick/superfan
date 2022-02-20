// This is a script for deploying your contracts. You can adapt it to deploy
// yours, or create new ones.
const deployFramework = require("@superfluid-finance/ethereum-contracts/scripts/deploy-framework");
const deployTestToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-test-token");
const deploySuperToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-super-token");
const SuperfluidSDK = require("@superfluid-finance/js-sdk");

async function main() {
  // This is just a convenience check
  if (network.name === "hardhat") {
    console.warn(
      "You are trying to deploy a contract to the Hardhat Network, which" +
        "gets automatically created and destroyed every time. Use the Hardhat" +
        " option '--network localhost'"
    );
  }

  const errorHandler = (err) => {
    if (err) throw err;
  };

  // ethers is available in the global scope
  const [deployer] = await ethers.getSigners();
  console.log(
    "Deploying the contracts with the account:",
    await deployer.getAddress()
  );

  const [owner, ...addrs] = (await web3.eth.getAccounts());

  console.log("Account balance:", (await deployer.getBalance()).toString());

  const SuperFan = await ethers.getContractFactory("SuperFan");
  
  await deployFramework(errorHandler, {
        web3,
        from: owner,
        newTestResolver: true
    });

  await deployTestToken(errorHandler, [":", "fDAI"], {
      web3,
      from: owner,
  });

  await deploySuperToken(errorHandler, [":", "fDAI"], {
      web3,
      from: owner,
  });

  sf = new SuperfluidSDK.Framework({
        web3,
        version: "test",
        tokens: ["fDAI"],
  });

  await sf.initialize();

  daix = sf.tokens.fDAIx;
  dai = await sf.contracts.TestToken.at(await sf.tokens.fDAI.address);

  app = await SuperFan.deploy(
        owner,
        "SuperFan",
        "SFAN",
        sf.host.address,
        sf.agreements.cfa.address,
        daix.address,
  );

  const appAddress = app.address;
  console.log("app address:", appAddress);

  // We also save the contract's artifacts and address in the frontend directory
  saveFrontendFiles({
    appAddress,
    daixAddress: daix.address,
  });
}

function saveFrontendFiles({appAddress, daixAddress}) {
  const fs = require("fs");
  const contractsDir = __dirname + "/../frontend/src/contracts";

  if (!fs.existsSync(contractsDir)) {
    fs.mkdirSync(contractsDir);
  }

  fs.writeFileSync(
    contractsDir + "/contract-address.json",
    JSON.stringify({
      SuperFan: appAddress,
      DAIx: daixAddress,
    }, undefined, 2)
  );

  const SuperFanArtifact = artifacts.readArtifactSync("SuperFan");

  fs.writeFileSync(
    contractsDir + "/SuperFan.json",
    JSON.stringify(SuperFanArtifact, null, 2)
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
