// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAny2EVMMessageReceiver {
  /// @notice Called by the Router to deliver a message. If this reverts, any token transfers also revert.
  /// The message will move to a FAILED state and become available for manual execution.
  /// @param message CCIP Message.
  /// @dev Note ensure you check the msg.sender is the OffRampRouter.
  function ccipReceive(
    Client.Any2EVMMessage calldata message
  ) external;
}
contract OwnerIsCreator {
    address private s_owner;
    
    constructor() {
        s_owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == s_owner, "Only owner can call this function");
        _;
    }
    
    function owner() public view returns (address) {
        return s_owner;
    }
}


// OpenZeppelin Imports
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Chainlink
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
// import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
// import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
// import { IAny2EVMMessageReceiver } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
// import "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";


import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/automation/interfaces/KeeperCompatibleInterface.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Cross-Chain NFT Ticketing dApp
 * @dev A decentralized ticketing system using Chainlink CCIP for cross-chain communication
 * @dev Supports Ethereum Sepolia, Avalanche Fuji, and Polygon Amoy testnets
 */
contract CrossChainNFTTicketing is 
    ERC721, 
    IAny2EVMMessageReceiver, 
    OwnerIsCreator, 
    ReentrancyGuard 
{
    // =============================================================================
    // CHAIN SELECTORS (Official Chainlink CCIP Chain Selectors)
    // =============================================================================
    
    // Ethereum Sepolia Testnet
    uint64 public constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;
    
    // Avalanche Fuji Testnet  
    uint64 public constant FUJI_CHAIN_SELECTOR = 14767482510784806043;
    
    // Polygon Amoy Testnet
    uint64 public constant AMOY_CHAIN_SELECTOR = 16281711391670634445;

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================
    
    IRouterClient private immutable ccipRouter;
    uint64 private immutable currentChainSelector;
    
    uint256 private _eventIdCounter;
    uint256 private _ticketIdCounter;

    // =============================================================================
    // STRUCTS
    // =============================================================================
    
    /**
     * @dev Event structure containing all event details
     */
    struct Event {
        uint256 eventId;
        address organizer;
        string name;
        string description;
        uint256 ticketPrice;
        uint64 chainSelector;  // Chain where event is listed and NFTs will be minted
        uint256 totalTickets;
        uint256 soldTickets;
        bool isActive;
    }

    /**
     * @dev Ticket message structure for CCIP communication
     */
    struct TicketMessage {
        uint256 eventId;
        address buyer;
        string ticketType;
        uint256 timestamp;
    }

    // =============================================================================
    // MAPPINGS
    // =============================================================================
    
    // eventId => Event details
    mapping(uint256 => Event) public events;
    
    // eventId => buyer => hasTicket
    mapping(uint256 => mapping(address => bool)) public hasTicket;
    
    // buyer => eventId[]
    mapping(address => uint256[]) public userTickets;
    
    // ticketId => eventId
    mapping(uint256 => uint256) public ticketToEvent;
    
    // Chain selector => supported chain
    mapping(uint64 => bool) public supportedChains;

    // =============================================================================
    // EVENTS
    // =============================================================================
    
    event EventListed(
        uint256 indexed eventId,
        address indexed organizer,
        string name,
        uint256 ticketPrice,
        uint64 chainSelector
    );
    
    event TicketPurchased(
        uint256 indexed eventId,
        address indexed buyer,
        uint256 amount,
        uint64 destinationChain
    );
    
    event TicketMinted(
        uint256 indexed eventId,
        address indexed buyer,
        uint256 indexed ticketId
    );
    
    event CCIPMessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChain,
        address indexed buyer,
        uint256 eventId
    );
    
    event CCIPMessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChain,
        address indexed buyer,
        uint256 eventId
    );

    // =============================================================================
    // MODIFIERS
    // =============================================================================
    
    /**
     * @dev Restricts access to CCIP Router only
     */
    modifier onlyRouter() {
        require(msg.sender == address(ccipRouter), "Only CCIP Router can call");
        _;
    }
    
    /**
     * @dev Checks if chain is supported
     */
    modifier onlySupportedChain(uint64 chainSelector) {
        require(supportedChains[chainSelector], "Chain not supported");
        _;
    }

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================
    
    /**
     * @dev Constructor initializes the contract with CCIP router
     * @param _ccipRouter Address of the CCIP Router contract
     * @param _currentChainSelector Chain selector for the current deployment
     */
    constructor(
        address _ccipRouter,
        uint64 _currentChainSelector
    ) ERC721("CrossChainTicket", "CCT") {
        ccipRouter = IRouterClient(_ccipRouter);
        currentChainSelector = _currentChainSelector;
        
        // Initialize counters
        _eventIdCounter = 0;
        _ticketIdCounter = 0;
        
        // Initialize supported chains
        supportedChains[SEPOLIA_CHAIN_SELECTOR] = true;
        supportedChains[FUJI_CHAIN_SELECTOR] = true;
        supportedChains[AMOY_CHAIN_SELECTOR] = true;
    }

    // =============================================================================
    // EVENT MANAGEMENT FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Allows organizers to list new events
     * @param _name Event name
     * @param _description Event description
     * @param _ticketPrice Price per ticket in native tokens
     * @param _totalTickets Maximum number of tickets available
     * @param _chainSelector Chain where NFTs will be minted
     */
    function addEvent(
        string memory _name,
        string memory _description,
        uint256 _ticketPrice,
        uint256 _totalTickets,
        uint64 _chainSelector
    ) external onlySupportedChain(_chainSelector) {
        require(_ticketPrice > 0, "Ticket price must be greater than 0");
        require(_totalTickets > 0, "Total tickets must be greater than 0");
        require(bytes(_name).length > 0, "Event name cannot be empty");
        
        _eventIdCounter++;
        uint256 eventId = _eventIdCounter;
        
        events[eventId] = Event({
            eventId: eventId,
            organizer: msg.sender,
            name: _name,
            description: _description,
            ticketPrice: _ticketPrice,
            chainSelector: _chainSelector,
            totalTickets: _totalTickets,
            soldTickets: 0,
            isActive: true
        });
        
        emit EventListed(eventId, msg.sender, _name, _ticketPrice, _chainSelector);
    }

    // =============================================================================
    // TICKET PURCHASE FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Allows users to buy tickets from any supported chain
     * @param _eventId ID of the event
     * @param _ticketType Type of ticket (e.g., "General", "VIP")
     */
    function buyTicket(
        uint256 _eventId,
        string memory _ticketType
    ) external payable nonReentrant {
        Event storage eventDetails = events[_eventId];
        require(eventDetails.isActive, "Event is not active");
        require(eventDetails.soldTickets < eventDetails.totalTickets, "Event sold out");
        require(msg.value >= eventDetails.ticketPrice, "Insufficient payment");
        require(!hasTicket[_eventId][msg.sender], "Already has ticket for this event");
        
        // Transfer payment to organizer on current chain
        (bool success, ) = eventDetails.organizer.call{value: msg.value}("");
        require(success, "Payment transfer failed");
        
        // If buying on the same chain where event is listed, mint directly
        if (currentChainSelector == eventDetails.chainSelector) {
            _mintTicket(_eventId, msg.sender, _ticketType);
        } else {
            // Send CCIP message to destination chain for minting
            _sendCCIPMessage(_eventId, msg.sender, _ticketType, eventDetails.chainSelector);
        }
        
        emit TicketPurchased(_eventId, msg.sender, msg.value, eventDetails.chainSelector);
    }

    // =============================================================================
    // CCIP FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Sends cross-chain message to mint ticket on destination chain
     * @param _eventId Event ID
     * @param _buyer Buyer address
     * @param _ticketType Type of ticket
     * @param _destinationChain Destination chain selector
     */
    function _sendCCIPMessage(
        uint256 _eventId,
        address _buyer,
        string memory _ticketType,
        uint64 _destinationChain
    ) internal {
        // Create ticket message
        TicketMessage memory ticketMsg = TicketMessage({
            eventId: _eventId,
            buyer: _buyer,
            ticketType: _ticketType,
            timestamp: block.timestamp
        });
        
        // Encode message
        bytes memory encodedMessage = abi.encode(ticketMsg);
        
        // Create CCIP message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)), // Send to same contract on destination chain
            data: encodedMessage,
            tokenAmounts: new Client.EVMTokenAmount[](0), // No tokens being sent
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 300_000}) // Gas limit for execution
            ),
            feeToken: address(0) // Pay fees in native token
        });
        
        // Calculate and pay CCIP fees
        uint256 ccipFee = ccipRouter.getFee(_destinationChain, message);
        require(address(this).balance >= ccipFee, "Insufficient balance for CCIP fees");
        
        // Send message
        bytes32 messageId = ccipRouter.ccipSend{value: ccipFee}(_destinationChain, message);
        
        emit CCIPMessageSent(messageId, _destinationChain, _buyer, _eventId);
    }
    
    /**
     * @dev Receives and processes CCIP messages
     * @param message CCIP message received
     */
    function ccipReceive(
        Client.Any2EVMMessage calldata message
    ) external override onlyRouter {
        // Decode the message
        TicketMessage memory ticketMsg = abi.decode(message.data, (TicketMessage));
        
        // Mint ticket for the buyer
        _mintTicket(ticketMsg.eventId, ticketMsg.buyer, ticketMsg.ticketType);
        
        emit CCIPMessageReceived(
            message.messageId,
            message.sourceChainSelector,
            ticketMsg.buyer,
            ticketMsg.eventId
        );
    }

    // =============================================================================
    // NFT MINTING FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Mints NFT ticket for buyer
     * @param _eventId Event ID
     * @param _buyer Buyer address
     * @param _ticketType Type of ticket
     */
    function _mintTicket(
        uint256 _eventId,
        address _buyer,
        string memory _ticketType
    ) internal {
        Event storage eventDetails = events[_eventId];
        require(eventDetails.isActive, "Event is not active");
        require(eventDetails.soldTickets < eventDetails.totalTickets, "Event sold out");
        require(!hasTicket[_eventId][_buyer], "Already has ticket for this event");
        
        // Increment counters
        _ticketIdCounter++;
        uint256 ticketId = _ticketIdCounter;
        eventDetails.soldTickets++;
        
        // Update mappings
        hasTicket[_eventId][_buyer] = true;
        userTickets[_buyer].push(_eventId);
        ticketToEvent[ticketId] = _eventId;
        
        // Mint NFT
        _safeMint(_buyer, ticketId);
        
        emit TicketMinted(_eventId, _buyer, ticketId);
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Returns event details
     * @param _eventId Event ID
     * @return Event details
     */
    function getEvent(uint256 _eventId) external view returns (Event memory) {
        return events[_eventId];
    }
    
    /**
     * @dev Checks if user has ticket for specific event
     * @param _eventId Event ID
     * @param _user User address
     * @return bool indicating if user has ticket
     */
    function hasTicketForEvent(uint256 _eventId, address _user) external view returns (bool) {
        return hasTicket[_eventId][_user];
    }
    
    /**
     * @dev Returns all event IDs for which user has tickets
     * @param _user User address
     * @return Array of event IDs
     */
    function getUserTickets(address _user) external view returns (uint256[] memory) {
        return userTickets[_user];
    }
    
    /**
     * @dev Returns current chain selector
     * @return Current chain selector
     */
    function getCurrentChainSelector() external view returns (uint64) {
        return currentChainSelector;
    }
    
    /**
     * @dev Returns CCIP router address
     * @return CCIP router address
     */
    function getCCIPRouter() external view returns (address) {
        return address(ccipRouter);
    }
    
    /**
     * @dev Returns total number of events created
     * @return Total events count
     */
    function getTotalEvents() external view returns (uint256) {
        return _eventIdCounter;
    }
    
    /**
     * @dev Returns total number of tickets minted
     * @return Total tickets count
     */
    function getTotalTickets() external view returns (uint256) {
        return _ticketIdCounter;
    }

    // =============================================================================
    // UTILITY FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Allows contract owner to withdraw accumulated fees
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        (bool success, ) = owner().call{value: balance}("");
        require(success, "Fee withdrawal failed");
    }
    
    /**
     * @dev Allows contract owner to add/remove supported chains
     * @param _chainSelector Chain selector
     * @param _supported Whether chain is supported
     */
    function setSupportedChain(uint64 _chainSelector, bool _supported) external onlyOwner {
        supportedChains[_chainSelector] = _supported;
    }
    
    /**
     * @dev Internal function to check if a token exists
     * @param tokenId Token ID to check
     * @return bool indicating if token exists
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @dev Returns token URI for NFT (can be overridden for custom metadata)
     * @param _tokenId Token ID
     * @return Token URI
     */
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "Token does not exist");
        
        uint256 eventId = ticketToEvent[_tokenId];
        Event memory eventDetails = events[eventId];
        
        // Basic metadata - can be enhanced with actual metadata service
        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(abi.encodePacked(
                '{"name":"',
                eventDetails.name,
                ' Ticket #',
                Strings.toString(_tokenId),
                '","description":"',
                eventDetails.description,
                '","attributes":[{"trait_type":"Event ID","value":"',
                Strings.toString(eventId),
                '"},{"trait_type":"Chain","value":"',
                Strings.toString(eventDetails.chainSelector),
                '"}]}'
            )))
        ));
    }
    
    /**
     * @dev Allows contract to receive native tokens for CCIP fees
     */
    receive() external payable {}
    
    /**
     * @dev Fallback function
     */
    fallback() external payable {}
}

// =============================================================================
// UTILITY LIBRARIES
// =============================================================================

library Base64 {
    string internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    
    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        
        string memory table = TABLE;
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        string memory result = new string(encodedLen + 32);
        
        assembly {
            mstore(result, encodedLen)
            let tablePtr := add(table, 1)
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))
            let resultPtr := add(result, 32)
            
            for {} lt(dataPtr, endPtr) {}
            {
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)
                
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(6, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(input, 0x3F)))))
                resultPtr := add(resultPtr, 1)
            }
            
            switch mod(mload(data), 3)
            case 1 { mstore(sub(resultPtr, 2), shl(240, 0x3d3d)) }
            case 2 { mstore(sub(resultPtr, 1), shl(248, 0x3d)) }
        }
        
        return result;
    }
}