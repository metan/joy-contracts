pragma solidity ^0.4.11;

import '../math/SafeMath.sol';
import '../token/MultiContractAsset.sol';
import '../token/ERC223ReceivingContract.sol';
import '../ownership/Ownable.sol';
import '../game/JoyGameAbstract.sol';

contract tokenDeposit is ERC223ReceivingContract, Ownable {
    using SafeMath for uint;

    MultiContractAsset m_supportedToken;

    mapping(address => uint256) deposits;

    // debug
    address public dbg_tokenAddr;
    address public dbg_senderAddr;
    // debug

    /**
     * platformReserve - Main platform address and reserve for winnings
     * Important address that collecting part of players losses as reserve which players will get thier winnings.
     * For security reasons "platform reserve address" needs to be separated/other that address of owner of this contract.
     */
    address platformReserve;

    /**
     * @dev Constructor
     * @param _supportedToken The address of token contract that will be supported as players deposit
     */
    function tokenDeposit(address _supportedToken, address _platformReserve) {
        // owner need to be separated from _platformReserve
        require(owner != _platformReserve);

        platformReserve = _platformReserve;
        m_supportedToken = MultiContractAsset(_supportedToken);
    }

    /**
     * @dev Gets the balance of the specified address.
     * @param _playerAddr The address to query the the balance of.
     * @return An uint256 representing the amount owned by the passed address.
     */
    function balanceOfPlayer(address _playerAddr) public constant returns (uint256) {
        return deposits[_playerAddr];
    }

    /**
     * @dev Function that receive tokens, throw exception if tokens is not supported.
     * This contract could recieve tokens, using functionalities designed in erc223 standard.
     * !! works only with tokens designed in erc223 way.
     */
    function onTokenReceived(address _from, uint _value, bytes _data) public {
        // msg.sender is a token-contract address here
        // we will use this information to filter what token we accept as deposit
        dbg_tokenAddr = address(m_supportedToken);
        dbg_senderAddr = msg.sender;

        // get address of supported token
        require(msg.sender == address(m_supportedToken));
        //TODO make sure about other needed requirements!

        deposits[_from] = deposits[_from].add(_value);
        OnTokenReceived(_from, _value, _data);
    }

    /**
     * @dev Temporarily transfer funds to the game contract
     *
     * This method can be used only by the owner of this contract.
     * That contruct allow to adding new games without modyfing this contract.
     * Important security check is that will work only if the owner of the game
     * will be same as the owner of this contract
     *
     * @param _playerAddr address of registred player
     * @param _gameContractAddress address to the game contract
     * @param _value amount of Tokens that will be transfered
     * @param _data additionl data
     */
    function transferToGame(address _playerAddr, address _gameContractAddress, uint _value, bytes _data) onlyOwner {
        // platformReserve is not allowed to play, this check prevents owner take possession of platformReserve
        require(_playerAddr != platformReserve);

        // check if player have requested _value in his deposit
        require(_value <= deposits[_playerAddr]);

        // _gameContractAddress should be a contract, throw exception if owner will tries to transfer flunds to the individual address.
        // Require supported Token to have 'isContract' method.
        require(isContract(_gameContractAddress));

        // Create local joyGame object using address of given gameContract.
        JoyGameAbstract joyGame = JoyGameAbstract(_gameContractAddress);

        // Require this contract and gameContract to be owned by the same address.
        // This check prevents interaction with this contract from external contracts
        require(joyGame.getOwner() == owner);

        deposits[_playerAddr] = deposits[_playerAddr].sub(_value);

        // increase gameContract deposit for the time of the game
        // this funds are locked, and even can not be withdraw by owner
        deposits[_gameContractAddress] = deposits[_gameContractAddress].add(_value);


        joyGame.onTokenReceived(msg.sender, _value, _data);

        // Event
        OnTokenReceived(msg.sender, _value, _data);
    }

    /**
     * @dev Function that could be executed by players to withdraw thier deposit
     */
    function payOut(address _to, uint256 _value) {
        // use transfer function from supported token.
        // should be used from player address that was registred in deposits
        require(_value <= deposits[msg.sender]);

        /**
         * Prevents payOut to the contract address.
         * This trick deprives owner incentives to steal Tokens from players.
         * Even if owner use 'transferToGame' method to transfer some deposits to the fake contract,
         * he will not be able to withdraw Tokens to any private address.
         */
        require(isContract(_to) == false);

        deposits[msg.sender] = deposits[msg.sender].sub(_value);

        // Use m_supportedToken metheod to transfer real Tokens.
        m_supportedToken.transfer(_to, _value);
    }

    //---------------------- utils ---------------------------

    function isContract(address _addr) internal constant returns (bool) {
        uint codeLength;
        assembly {
            // Retrieve the size of the code on target address, this needs assembly .
            codeLength := extcodesize(_addr)
        }
        return (codeLength > 0);
    }
}

