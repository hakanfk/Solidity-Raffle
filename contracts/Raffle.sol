//Enter the raffle(with paying some amount)
// Pick a random winner
// Winner to be selected every 60 minutes
// Chainlink Oracle -->> For randomness outsid eof the blockchain

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

error Raffle__NotEnoughETHEntered();
error Raffle__TransferFailed();
error Raffle__IsNotOpen();
error Raffle__UpkeepNotNeeded(uint256 balance, uint256 numPlayers);

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
    //Types
    enum RaffleState {
        OPEN,
        CLOSED,
        CALCULATING
    }

    //State Variables
    uint256 private immutable i_minimumEth;
    address payable[] private s_players;
    bytes32 private immutable i_gasLane;
    uint16 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;

    //Raffle Variables
    address private s_recentWinner;
    RaffleState private s_raffleState;
    uint256 private s_lastTimeStamp;
    uint256 private immutable i_interval;

    //-----Events-----
    event RaffleEnter(address indexed player);
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleWinner(address indexed winner);

    constructor(
        address vrfCoordinatorV2,
        uint256 minimumFee,
        bytes32 gasLane,
        uint16 subscriptionId,
        uint32 callbackGasLimit,
        uint256 interval
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_minimumEth = minimumFee;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        i_interval = interval;
    }

    /* --------------- */
    /* ------------------ Functions ------------------ */

    function enterRaffle() public payable {
        //We can use require but to be more gas efficient we'll use revert
        if (msg.value < i_minimumEth) {
            revert Raffle__NotEnoughETHEntered();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__IsNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }

    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performsData */)
    {
        bool isOpen = (RaffleState.OPEN == s_raffleState);
        bool timePassed = (block.timestamp - s_lastTimeStamp) > i_interval;
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;

        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        //Request the random number
        //Once get it, do something with it

        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length
            );
        }

        s_raffleState = RaffleState.CALCULATING;

        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        //send money to winner
        (bool success, ) = recentWinner.call{value: address(this).balance}("");

        //After selection change the raffle state
        s_raffleState = RaffleState.OPEN;

        //After selection, clear the array
        s_players = new address payable[](0);

        //And reset the last timestamp
        s_lastTimeStamp = block.timestamp;

        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit RaffleWinner(recentWinner);
    }

    /* ----------------------------- */
    /* --------- View, Pure Functions -------------- */

    function getEntranceFee() public view returns (uint256) {
        return i_minimumEth;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getNumofPlayers() public view returns (uint256) {
        return s_players.length;
    }
}
