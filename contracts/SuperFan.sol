// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import "hardhat/console.sol";

library Errors {
    string internal constant PositiveFlow = "flow rate must be positive";
    string internal constant TokenIdMismatch = "invalid tokenId";
    string internal constant FlowRateMismatch = "flowRate does not match tier";
    string internal constant TierOwnerMismatch = "tier does not belong to creator";
    string internal constant OwnerMismatch = "subscription does not belong to caller";
}

// Allows creators to create NFTs with associated patron streams
contract SuperFan is ERC721, Ownable, SuperAppBase {
    using EnumerableSet for EnumerableSet.UintSet;

    address public _owner;

    ISuperfluid private _host; // host
    IConstantFlowAgreementV1 private _cfa; // the stored constant flow agreement class address

    ISuperToken public _acceptedToken; // accepted token

    mapping(uint256 => int96) public flowRates; // per tier

    mapping(uint256 => address) private subscriptionToPayor;
    mapping(uint256 => uint256) private subscriptionToTier;
    mapping(bytes32 => uint256) public flowIdToSubscription;
    

    EnumerableSet.UintSet private creatorTiers;

    uint256 public nextTierId; // this is so we can increment the number (each stream has new id we store in flowRates)
    uint256 public nextSubscriptionId;

    constructor(
        address owner,
        string memory _name,
        string memory _symbol,
        ISuperfluid host,
        IConstantFlowAgreementV1 cfa,
        ISuperToken acceptedToken
    ) ERC721(_name, _symbol) {
        _host = host;
        _cfa = cfa;
        _acceptedToken = acceptedToken;
        _owner = owner;

        nextTierId = 1;
        nextSubscriptionId = 1;

        assert(address(_host) != address(0));
        assert(address(_cfa) != address(0));
        assert(address(_acceptedToken) != address(0));

        uint256 configWord =
            SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP;

        _host.registerApp(configWord);
    }

    event PatronTierCreated(uint256 tokenId, address receiver, int96 flowRate);
    event PatronTierSubscription(uint256 tokenId, address subscriber, address receiver, int96 flowRate);

    function createTier(int96 flowRate) external {
        require(flowRate > 0, Errors.PositiveFlow);

        flowRates[nextTierId] = flowRate;
        creatorTiers.add(nextTierId);

        emit PatronTierCreated(nextTierId, _owner, flowRate);
        nextTierId += 1;
    }

    function getTiers() public view returns (bytes32[] memory) {
        return creatorTiers._inner._values;
    }

    function _handleSubscribe(address payor, address subscriber, int96 flowRate, uint256 tierId) internal {
        subscriptionToPayor[nextSubscriptionId] = payor;
        subscriptionToTier[nextSubscriptionId] = tierId;

        _mint(subscriber, nextSubscriptionId);
        emit PatronTierSubscription(nextSubscriptionId, subscriber, _owner, flowRate);
    
        nextSubscriptionId += 1;
    }

    function _placeUnsubscription(bytes calldata _ctx, bytes32 agreementId, int96 flowRate)
        private
        returns (bytes memory newCtx)
    {
        newCtx = _ctx;
        uint256 tokenId = flowIdToSubscription[agreementId];

        console.log("_placeUnsubscription: %s", tokenId);

        if(_exists(tokenId)) {
            _burn(tokenId);
        }

        (,int96 existingFlowRate,,) = _cfa.getFlow(_acceptedToken, address(this), _owner);
        console.log("flowRate, existingFlowRate");
        console.logInt(flowRate);
        console.logInt(existingFlowRate);

        // need to adjust flow from app to owner
        if(existingFlowRate == int96(0)) {
            newCtx = _deleteFlowWithCtx(_ctx, _owner);
        } else {
            newCtx = _decreaseFlowWithCtx(_ctx, _owner, existingFlowRate, flowRate);
        }

        delete subscriptionToPayor[tokenId];
        delete subscriptionToTier[tokenId];
    }

    function _placeSubscription(bytes calldata _ctx, bytes32 agreementId, bytes calldata agreementData)
        private
        returns (bytes memory newCtx)
    {
        (uint256 tierId, uint256 tokenId) = abi.decode(_host.decodeCtx(_ctx).userData, (uint256, uint256));

        console.log("tierId: %s, tokenId: %s", tierId, tokenId);
        // console.log("agreementId: %s", agreementId);

        require(tokenId == nextSubscriptionId, Errors.TokenIdMismatch);

        (address subscriber,) = abi.decode(agreementData, (address, address));
        (,int96 flowRate,,) = _cfa.getFlowByID(_acceptedToken, agreementId); // from user
        (,int96 existingFlowRate,,) = _cfa.getFlow(_acceptedToken, address(this), _owner);

        console.log("flowRate, existingFlowRate"); // , flowRate, existingFlowRate);
        console.logInt(flowRate);
        console.logInt(existingFlowRate);

        int96 expectedFlowRate = flowRates[tierId];
        require(flowRate == expectedFlowRate, Errors.FlowRateMismatch);

        flowIdToSubscription[agreementId] = nextSubscriptionId;

        // pass from app to creator
        if(existingFlowRate == int96(0)) {
            newCtx = _createFlowWithCtx(_ctx, _owner, tierId, nextSubscriptionId, flowRate);
        } else {
            newCtx = _updateFlowWithCtx(_ctx, _owner, tierId, nextSubscriptionId, existingFlowRate, flowRate);
        }
        _handleSubscribe(subscriber, subscriber, flowRate, tierId);
    }

    /**************************************************************************
     * Callbacks
    *************************************************************************/
    function afterAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata _agreementData,
        bytes calldata /* _cbdata */,
        bytes calldata _ctx
    )
        external override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory)
    {
        console.log("afterAgreementCreated");
        return _placeSubscription(_ctx, _agreementId, _agreementData);
    }

     function beforeAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 /*agreementId*/,
        bytes calldata /*_agreementData*/,
        bytes calldata /*ctx*/
    )
        external view override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory)
    {
        revert("update unsupported: must delete and create flow");
        // return abi.encode(false);
    }

    function beforeAgreementTerminated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata /*_agreementData*/,
        bytes calldata /*ctx*/
    )
        external view override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory)
    {
        console.log("beforeAgreementTerminated");
        (,int96 flowRate,,) = _cfa.getFlowByID(_acceptedToken, _agreementId); // from user
        console.log("flowRate");
        console.logInt(flowRate);
        return abi.encode(flowRate);
    }

    function afterAgreementTerminated(
        ISuperToken /* superToken */,
        address /* agreementClass */,
        bytes32 _agreementId,
        bytes calldata /*_agreementData*/,
        bytes calldata _cbdata,
        bytes calldata _ctx
    )
        external override
        onlyHost
        returns (bytes memory newCtx)
    {

        console.log("afterAgreementTerminated");
        (int96 flowRate) = abi.decode(_cbdata, (int96));

        // (address subscriber, address creator) = abi.decode(agreementData, (address, address));
        // don't rely on supplied user data (potentially malicious)
        // (uint256 tierId, uint256 tokenId) = abi.decode(_host.decodeCtx(ctx).userData, (uint256, uint256));
        
        return _placeUnsubscription(_ctx, _agreementId, flowRate);
    }

    /**************************************************************************
     * Utilities
     *************************************************************************/
    function _isAccepted(ISuperToken _superToken) private view returns (bool) {
        return address(_superToken) == address(_acceptedToken);
    }

    function _isCFAv1(address agreementClass) private view returns (bool) {
        return ISuperAgreement(agreementClass).agreementType()
            == keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    }

    /**************************************************************************
     * Modifiers
     *************************************************************************/

    modifier exists(uint256 tokenId) {
        require(_exists(tokenId), "token doesn't exist or has been burnt");
        _;
    }

    modifier onlyHost() {
        require(msg.sender == address(_host), "PatronSuperApp: support only one host");
        _;
    }

    modifier onlyExpected(ISuperToken _superToken, address _agreementClass) {
        require(_isAccepted(_superToken) , "SuperFan: not accepted tokens");
        require(_isCFAv1(_agreementClass), "SuperFan: only CFAv1 supported");
        _;
    }

    /**************************************************************************
     * Library
     *************************************************************************/

    function _createFlowWithCtx(
        bytes memory ctx,
        address to,
        uint256 tierId,
        uint256 tokenId,
        int96 flowRate
    ) internal returns (bytes memory newCtx) {

        int96 expectedFlowRate = flowRates[tierId];
        require(flowRate == expectedFlowRate, Errors.FlowRateMismatch);

        (newCtx, ) = _host.callAgreementWithContext(
                _cfa,
                abi.encodeWithSelector(
                    _cfa.createFlow.selector,
                    _acceptedToken,
                    to,
                    flowRate,
                    new bytes(0) // placeholder
                ),
                "0x", // user data
                ctx
        );
    }

    // flow from app to owner (with new subscriber)
    function _updateFlowWithCtx(
        bytes memory ctx,
        address to,
        uint256 tierId,
        uint256 tokenId,
        int96 oldFlowRate,
        int96 flowRate
    ) internal returns (bytes memory newCtx) {

        (newCtx, ) = _host.callAgreementWithContext(
                _cfa,
                abi.encodeWithSelector(
                    _cfa.updateFlow.selector,
                    _acceptedToken,
                    to,
                    oldFlowRate + flowRate,
                    new bytes(0) // placeholder
                ),
                "0x", // user data
                ctx
        );
    }

    // flow from app to owner (with unsubscriber)
    function _decreaseFlowWithCtx(
        bytes memory ctx,
        address to,
        int96 oldFlowRate,
        int96 flowRate
    ) internal returns (bytes memory newCtx) {

        (newCtx, ) = _host.callAgreementWithContext(
                _cfa,
                abi.encodeWithSelector(
                    _cfa.updateFlow.selector,
                    _acceptedToken,
                    to,
                    oldFlowRate - flowRate,
                    new bytes(0) // placeholder
                ),
                "0x",  // user data
                ctx
        );
    }

    function _deleteFlowWithCtx(
        bytes memory ctx,
        address to
    ) internal returns (bytes memory newCtx) {
        (newCtx, ) = _host.callAgreementWithContext(
                _cfa,
                abi.encodeWithSelector(
                    _cfa.deleteFlow.selector,
                    _acceptedToken,
                    to,
                    new bytes(0) // placeholder
                ),
                "0x",  // user data
                ctx
        );
    }
}


// balanceOf(tokenId)
// getFlow -> see

// factory contract

