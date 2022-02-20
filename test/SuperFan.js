const deployFramework = require("@superfluid-finance/ethereum-contracts/scripts/deploy-framework");
const deployTestToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-test-token");
const deploySuperToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-super-token");
const SuperfluidSDK = require("@superfluid-finance/js-sdk");

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

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

  async function checkBalance(user) {
      console.log("Balance of ", user.alias);
      console.log("DAIx: ", (await daix.balanceOf(user.address)).toString());
  }

  async function checkBalances(accounts) {
      for (let i = 0; i < accounts.length; ++i) {
          await checkBalance(accounts[i]);
      }
  }

  async function hasFlows(user) {
      const { inFlows, outFlows } = (await user.details()).cfa.flows;
      return inFlows.length + outFlows.length > 0;
  }

  async function logUsers() {
      let string = "user\t\ttokens\t\tnetflow\n";
      let p = 0;
      for (const [, user] of Object.entries(u)) {
          if (await hasFlows(user)) {
              p++;
              string += `${user.alias}\t\t${wad4human(
                  await daix.balanceOf(user.address)
              )}\t\t${wad4human((await user.details()).cfa.netFlow)}
          `;
          }
      }
      if (p == 0) return console.warn("no users with flows");
      console.log("User logs:");
      console.log(string);
  }

  async function appStatus() {
      const isApp = await sf.host.isApp(u.app.address);
      const isJailed = await sf.host.isAppJailed(app.address);
      !isApp && console.error("App is not an App");
      isJailed && console.error("app is Jailed");
      await checkBalance(u.app);
  }

  async function upgrade(accounts) {
      for (let i = 0; i < accounts.length; ++i) {
          await web3tx(
              daix.upgrade,
              `${accounts[i].alias} upgrades many DAIx`
          )(toWad(100000), { from: accounts[i].address });
          await checkBalance(accounts[i]);
      }
  }

  before(async function () {
    // Get the ContractFactory and Signers here.
    SuperFan = await ethers.getContractFactory("SuperFan");

    // [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    const addrs = (await web3.eth.getAccounts())
    accounts = addrs.slice(0, names.length);

    let signers = await ethers.getSigners();
    signers = signers.slice(0, names.length);


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
        u[names[i].toLowerCase()].signer = signers[i];
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
        u.admin.address,
        "SuperFan",
        "SFAN",
        sf.host.address,
        sf.agreements.cfa.address,
        daix.address,
    );

    u.app = sf.user({ address: app.address, token: daix.address });
    u.app.alias = "App";

  });
  // You can nest describe calls to create subsections.
  describe("Deployment", function () {

    it("Should conform to ERC721", async function () {
      const ownerBalance = await app.balanceOf(u.admin.address);
      expect(ownerBalance).to.equal(0);
    });

  });

  describe("CreateTiers", function () {

    it("Should enable tiers to be created", async function () {
      const { admin } = u;

      let count = await app.nextTierId();
      expect(count).to.equal(1);

      await app.connect(admin.signer).createTier(3858024691358);

      count = await app.nextTierId();
      expect(count).to.equal(2);

      await app.connect(admin.signer).createTier(38580246913580);

      count = await app.nextTierId();
      expect(count).to.equal(3);

    });

  });

  describe("Subscribe", function () {

    it("Should enable a subscription", async function () {
      const { alice } = u;
      await upgrade([alice]);
      await appStatus();

      let nextSubs = await app.nextSubscriptionId();
      expect(nextSubs).to.equal(1);

      const expectedFlowRate = await app.flowRates(1)
      console.log(`expectedFlowRate: ${expectedFlowRate}`);
      console.log(`alice.address: ${alice.address}`);
      console.log(`alice.signer: ${alice.signer.address}`);
      await alice.flow({
        flowRate: `${expectedFlowRate}`,
        recipient: u.app,
        userData: web3.eth.abi.encodeParameters(['uint256', 'uint256'],[1, 1]) // actual recipient
      });

      nextSubs = await app.nextSubscriptionId();
      expect(nextSubs).to.equal(2);

      const aliceBalance = await app.balanceOf(alice.address);
      expect(aliceBalance).to.equal(1);

      await appStatus();
      await logUsers();
    });

    it("Should enable multiple subscription", async function () {
      const { bob, carol } = u;
      await upgrade([bob, carol]);
      await appStatus();

      const nextSubs = await app.nextSubscriptionId();
      const silverFlowRate = await app.flowRates(1);
      const goldFlowRate = await app.flowRates(2);

      await bob.flow({
        flowRate: `${silverFlowRate}`,
        recipient: u.app,
        userData: web3.eth.abi.encodeParameters(['uint256', 'uint256'],[1, 2]) // actual recipient
      });

      expect(await app.nextSubscriptionId()).to.equal(Number(nextSubs)+1);

      await carol.flow({
        flowRate: `${goldFlowRate}`,
        recipient: u.app,
        userData: web3.eth.abi.encodeParameters(['uint256', 'uint256'],[2, 3]) // actual recipient
      });

      expect(await app.nextSubscriptionId()).to.equal(Number(nextSubs)+2);
      
      await appStatus();
      await logUsers();
    });

    it("Should enable an unsubscription", async function () {
      const { alice } = u;

      const aliceBalance = await app.balanceOf(alice.address);

      await alice.flow({
        flowRate: '0', // delete flow (hopefully)
        recipient: u.app,
      });

      await appStatus();
      await logUsers();

      expect(await app.balanceOf(alice.address)).to.equal(Number(aliceBalance)-1);

    });

  });

});
