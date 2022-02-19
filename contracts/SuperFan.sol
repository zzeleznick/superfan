// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

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

    ISuperfluid private _host; // host
    IConstantFlowAgreementV1 private _cfa; // the stored constant flow agreement class address

    ISuperToken public _acceptedToken; // accepted token

    mapping(uint256 => int96) public flowRates;
    mapping(uint256 => address) public tierIdToCreator;

    mapping(uint256 => address) public subscriptionToCreator;
    mapping(uint256 => address) private subscriptionToPayor;
    mapping(uint256 => uint256) private subscriptionToTier;
    mapping(bytes32 => uint256) public flowIdToSubscription;
    

    mapping(address => EnumerableSet.UintSet) private creatorTiers;

    uint256 public nextTierId; // this is so we can increment the number (each stream has new id we store in flowRates)
    uint256 public nextSubscriptionId;

    constructor(
        string memory _name,
        string memory _symbol,
        ISuperfluid host,
        IConstantFlowAgreementV1 cfa,
        ISuperToken acceptedToken
    ) ERC721(_name, _symbol) {
        _host = host;
        _cfa = cfa;
        _acceptedToken = acceptedToken;

        nextTierId = 1;
        nextSubscriptionId = 1;

        assert(address(_host) != address(0));
        assert(address(_cfa) != address(0));
        assert(address(_acceptedToken) != address(0));

        uint256 configWord =
            SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;

        _host.registerApp(configWord);
    }

    event PatronTierCreated(uint256 tokenId, address receiver, int96 flowRate);
    event PatronTierSubscription(uint256 tokenId, address subscriber, address receiver, int96 flowRate);


    function createTier(int96 flowRate) external {
        _createTier(msg.sender, flowRate);
    }

    function _createTier(address receiver, int96 flowRate) internal {
        require(flowRate > 0, Errors.PositiveFlow);

        flowRates[nextTierId] = flowRate;
        tierIdToCreator[nextTierId] = receiver;
        creatorTiers[receiver].add(nextTierId);

        emit PatronTierCreated(nextTierId, receiver, flowRate);
        nextTierId += 1;
    }

    function getTiers() public view returns (bytes32[] memory) {
        return creatorTiers[msg.sender]._inner._values;
    }

    function _handleSubscribe(address payor, address subscriber, address creator, int96 flowRate, uint256 tierId) internal {
        subscriptionToCreator[nextSubscriptionId] = creator;
        subscriptionToPayor[nextSubscriptionId] = payor;
        subscriptionToTier[nextSubscriptionId] = tierId;

        _mint(subscriber, nextSubscriptionId);
        emit PatronTierSubscription(nextSubscriptionId, subscriber, creator, flowRate);
    
        nextSubscriptionId += 1;
    }

    function _placeUnsubscription(bytes calldata _ctx, bytes32 agreementId)
        private
        returns (bytes memory newCtx)
    {
        newCtx = _ctx;
        uint256 tokenId = flowIdToSubscription[agreementId];

        if(_exists(tokenId)) {
            _burn(tokenId);
        }

        // presersve flowIdToSubscription for debugging
        // delete flowIdToSubscription[agreementId];

        delete subscriptionToCreator[tokenId];
        delete subscriptionToPayor[tokenId];
        delete subscriptionToTier[tokenId];
    }

    function _placeSubscription(bytes calldata _ctx, bytes32 agreementId, bytes calldata agreementData)
        private
        returns (bytes memory newCtx)
    {
        newCtx = _ctx;
        (uint256 tierId, uint256 tokenId) = abi.decode(_host.decodeCtx(_ctx).userData, (uint256, uint256));
        require(tokenId == nextSubscriptionId, Errors.TokenIdMismatch);

        (address subscriber, address creator) = abi.decode(agreementData, (address, address));
        (,int96 flowRate,,) = _cfa.getFlowByID(_acceptedToken, agreementId);

        int96 expectedFlowRate = flowRates[tierId];
        require(flowRate == expectedFlowRate, Errors.FlowRateMismatch);
        address expectedCreator = tierIdToCreator[tierId];
        require(creator == expectedCreator, Errors.TierOwnerMismatch);
        // require(length(creatorTiers[creator]) > 0, "No tiers found for creator");
        // require(contains(creatorTiers[creator]), tierId), "Creator does not have this tier");
        
        flowIdToSubscription[agreementId] = nextSubscriptionId;
        _handleSubscribe(subscriber, subscriber, creator, flowRate, tierId);
    }

    function _subscribe(address subscriber, uint256 tierId) public {
        address creator = tierIdToCreator[tierId];
        require(creator != address(0), Errors.TierOwnerMismatch);

        int96 flowRate = flowRates[tierId];
        require(flowRate > 0, Errors.PositiveFlow);

        (, int96 currentFlowRate,,) = _cfa.getFlow(_acceptedToken, subscriber, creator);

        if (currentFlowRate == int96(0)) {
            _createFlow(creator, tierId, nextSubscriptionId, flowRate);
        }
    }

    function subscribe(uint256 tierId) external {
        _subscribe(msg.sender, tierId);
    }

    function unsubscribe(uint256 tokenId) external exists(tokenId) {
        address payor = subscriptionToPayor[tokenId];
        require(msg.sender == ownerOf(tokenId) || msg.sender == payor, Errors.OwnerMismatch);
        uint256 tierId = subscriptionToTier[tokenId];
        address creator = tierIdToCreator[tierId];
        require(creator != address(0), Errors.TierOwnerMismatch);
        _deleteFlow(payor, creator);
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
        return _placeSubscription(_ctx, _agreementId, _agreementData);
    }
    
    function beforeAgreementTerminated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 /*agreementId*/,
        bytes calldata /*agreementData*/,
        bytes calldata /*ctx*/
    )
        external view override
        onlyHost
        returns (bytes memory cbdata)
    {
        // According to the app basic law, we should never revert in a termination callback
        if (!_isAccepted(superToken) || !_isCFAv1(agreementClass)) return abi.encode(true);
        return abi.encode(false);
    }

    // todo: handle update less harshly
    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata /*_agreementData*/,
        bytes calldata /*_cbdata*/,
        bytes calldata _ctx
    )
        external override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory)
    {
        return _placeUnsubscription(_ctx, _agreementId);
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
        // According to the app basic law, we should never revert in a termination callback
        (bool shouldIgnore) = abi.decode(_cbdata, (bool));
        if (shouldIgnore) return _ctx;
        // (address subscriber, address creator) = abi.decode(agreementData, (address, address));
        // don't rely on supplied user data (potentially malicious)
        // (uint256 tierId, uint256 tokenId) = abi.decode(_host.decodeCtx(ctx).userData, (uint256, uint256));
        return _placeUnsubscription(_ctx, _agreementId);
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
    function _createFlow(address to, uint256 tierId, uint256 tokenId, int96 flowRate) internal exists(tokenId) {
        if (to == address(this) || to == address(0)) return;

        int96 expectedFlowRate = flowRates[tierId];
        require(flowRate == expectedFlowRate, Errors.FlowRateMismatch);

        _host.callAgreement(
            _cfa,
            abi.encodeWithSelector(
                _cfa.createFlow.selector,
                _acceptedToken,
                to,
                flowRate,
                new bytes(0) // placeholder
            ),
            abi.encode(tierId, tokenId)  // user data
        );
    }

    function _deleteFlow(address from, address to) internal {
        _host.callAgreement(
            _cfa,
            abi.encodeWithSelector(
                _cfa.deleteFlow.selector,
                _acceptedToken,
                from,
                to,
                new bytes(0) // placeholder
            ),
            "0x"
        );
    }
}