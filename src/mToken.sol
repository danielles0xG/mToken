// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {MathUtils} from "./CustomMath.sol";

/// @title Interest-bearing token
/// @author DanielG
/// @notice Interests accrued on transfer
/// @dev Contract is ERC20 and it doesn't receive eth
contract mToken is ERC20 {
    using MathUtils for uint256;

    address private immutable _admin;
    uint256 private _interestRate; // in basis points

    // basis points denominator
    uint16 private constant BP_DENOMINATOR = 10_000;

    // sender => time stamp since last accrued interest
    mapping(address account => uint256 timeStamp) private lastAccruedTime;

    event AcrruedInterestEvent(address indexed _sender, uint256 _interest, uint256 _blockTime);
    event BurnEvent(address indexed _sender, uint256 amount);
    event UpdateInterestEvent(uint96 newInterest);
    event MintEvent(uint256 indexed _amount);

    /// @notice admin ward, single access control
    modifier onlyAdmin() {
        require(msg.sender == _admin, "Only admin");
        _;
    }

    /// @notice sets last accrued call of sender to current timestamp
    modifier updateAccrueTime(address _receiver) {
        lastAccruedTime[_receiver] = block.timestamp;
        _;
    }

    /// @notice Only called on Transfer & TransferFrom
    modifier accrueInterest(address _sender) {
        uint256 accruedInterest = _calculateUserInterest(_sender);
        uint256 currentTime = block.timestamp;
        if (accruedInterest > 0) {
            _mint(_sender, accruedInterest);
            lastAccruedTime[_sender] = currentTime;
            emit AcrruedInterestEvent(_sender, accruedInterest, currentTime);
        }
        _;
    }

    /// @notice Deployer is admin/owner
    /// @param name Custom token name
    /// @param symbol mTKN
    /// @param initialSupply token initial supply
    /// @param interestRate interest rate for APY
    /// @dev Admin has no rights to accrue interests as he is the initial supply minter
    constructor(string memory name, string memory symbol, uint256 initialSupply, uint96 interestRate)
        ERC20(name, symbol)
    {
        _admin = msg.sender;
        updateIR(interestRate);
        _mint(_admin, initialSupply);
    }

    receive() external payable {
        revert("Unsupported");
    }

    fallback() external payable {
        revert("Unsupported");
    }

    /// @notice Updates receiver accrue time
    /// @dev access: only admin
    function mint(address _to, uint256 _amount) external onlyAdmin updateAccrueTime(_to) {
        _mint(_to, _amount);
        emit MintEvent(_amount);
    }

    /// @notice doesn't updates accrued time for anyone
    /// @dev access: any
    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
        emit BurnEvent(msg.sender, _amount);
    }

    /// @return _earned interest earned since last Accrued Time
    function earned() external view returns (uint256 _earned) {
        _earned = _calculateUserInterest(msg.sender);
    }

    /// @notice Updates: sender accrued interest, last time accrued and receiver accrued time
    /// @dev access: any
    function transfer(address to, uint256 value)
        public
        override
        accrueInterest(msg.sender)
        updateAccrueTime(to)
        returns (bool)
    {
        require(to != address(0x0),"Zero Addres");
        require(msg.sender != to && value > 0, "Invalid Tranfer");
        require(super.transfer(to, value), "Transfer fail");
        return true;
    }


    /// @notice Updates sender accrued interest, last time accrued and receiver accrued time
    /// @dev access: any
    function transferFrom(address from, address to, uint256 value)
        public
        override
        accrueInterest(from)
        updateAccrueTime(to)
        returns (bool)
    {
        require(from != address(0x0) && to != address(0x0),"Zero Addres");
        require(from != to && value > 0, "Invalid Tranfer");
        return super.transferFrom(from, to, value);
    }

    /// @notice Interest rate in basis points
    /// @dev access: only admin
    function updateIR(uint96 _newRate) public onlyAdmin {
        require(_newRate > 0 && _newRate < BP_DENOMINATOR, "Invalid interest rate");
        _interestRate = _newRate;
        emit UpdateInterestEvent(_newRate);
    }

    /// @notice Compounds interest rate by second
    /// @return _interest earned since last Accrued Time
    function _calculateUserInterest(address _sender) internal view returns (uint256 _interest) {
        uint256 senderBalance = balanceOf(_sender);
        uint256 rayRate = _interestRate.mulDivRoundingUp(1e27, 100);
        uint256 timeSinceLastAccrue = block.timestamp - lastAccruedTime[_sender];
        if (timeSinceLastAccrue > 0) {
            // no minimum accrual period
            // convert compounded interest to basis points
            _interest = rayRate.calculateCompoundedInterest(uint40(lastAccruedTime[_sender])).rayToWad() / 1e18;
            // calculate interest amount based on user balance
            _interest = senderBalance.mulDivRoundingUp(_interest, BP_DENOMINATOR);
        }
    }
}
