const deployFramework = require("@superfluid-finance/ethereum-contracts/scripts/deploy-framework");
const deployTestToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-test-token");
const deploySuperToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-super-token");
const SuperfluidSDK = require("@superfluid-finance/js-sdk");

const { expect } = require("chai");
const { web3tx, toWad, wad4human } = require("@decentral.ee/web3-helpers");

describe("SuperFan contract", function () {
  // Mocha has four functions that let you hook into the the test runner's
  // lifecycle. These are: `before`, `beforeEach`, `after`, `afterEach`.

  // They're very useful to setup the environment for tests, and to clean it
  // up after they run.

  // A common pattern is to declare some variables, and assign them in the
  // `before` and `beforeEach` callbacks.

  let SuperFan;

  let sf;
  let dai;
  let daix;
  let app;

  const names = ["Admin", "Alice", "Bob", "Carol"];
  let accounts;

  const u = {}; // object with all users
  const aliases = {};

  const errorHandler = (err) => {
    if (err) throw err;
   };

  before(async function () {
    // Get the ContractFactory and Signers here.
    SuperFan = await ethers.getContractFactory("SuperFan");

    // [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    const addrs = (await web3.eth.getAccounts())
    accounts = addrs.slice(0, names.length);

    //process.env.RESET_SUPERFLUID_FRAMEWORK = 1;
    await deployFramework(errorHandler, {
        web3,
        from: accounts[0],
        newTestResolver: true
    });

    await deployTestToken(errorHandler, [":", "fDAI"], {
        web3,
        from: accounts[0],
    });
    await deploySuperToken(errorHandler, [":", "fDAI"], {
        web3,
        from: accounts[0],
    });

    sf = new SuperfluidSDK.Framework({
        web3,
        version: "test",
        tokens: ["fDAI"],
    });

    await sf.initialize();

    daix = sf.tokens.fDAIx;
    dai = await sf.contracts.TestToken.at(await sf.tokens.fDAI.address);

    for (var i = 0; i < names.length; i++) {
        u[names[i].toLowerCase()] = sf.user({
            address: accounts[i],
            token: daix.address,
        });
        u[names[i].toLowerCase()].alias = names[i];
        aliases[u[names[i].toLowerCase()].address] = names[i];
    }
    for (const [, user] of Object.entries(u)) {
        if (user.alias === "App") return;
        await web3tx(dai.mint, `${user.alias} mints many dai`)(
            user.address,
            toWad(100000000000),
            {
                from: user.address,
            }
        );
        await web3tx(dai.approve, `${user.alias} approves daix`)(
            daix.address,
            toWad(100000000000),
            {
                from: user.address,
            }
        );
    }
    //u.zero = { address: ZERO_ADDRESS, alias: "0x0" };
    console.log(u.admin.address);
    console.log(sf.host.address);
    console.log(sf.agreements.cfa.address);
    console.log(daix.address);

    app = await SuperFan.deploy(
        "SuperFan",
        "SFAN",
        sf.host.address,
        sf.agreements.cfa.address,
        daix.address,
    );

  });
  // You can nest describe calls to create subsections.
  describe("Deployment", function () {

    it("Should conform to ERC721", async function () {
      const ownerBalance = await app.balanceOf(u.admin.address);
      expect(ownerBalance).to.equal(0);
    });

  });

});
