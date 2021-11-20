//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "./interfaces/IBank.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IERC20.sol";


contract Bank is IBank {
    address priceOracle;
    address hakToken;
    address ethToken;
    address selfAddress;

    mapping(address => uint256) ethBalances;
    mapping(address => uint256) ethInterest;
    mapping(address => uint) ethLastBlockNumber;

    mapping(address => uint256) hakBalances;
    mapping(address => uint256) hakInterest;
    mapping(address => uint) hakLastBlockNumber;

    constructor(address _priceOracle, address payable _hakToken) {
        priceOracle = _priceOracle;
        hakToken = _hakToken;
        ethToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        selfAddress = address(this);
    }

    function deposit(address token, uint256 amount) payable external override returns (bool) {
        if (token == ethToken) {
            ethInterest[msg.sender] = getEthTotalInterest(msg.sender, block.number);
            ethLastBlockNumber[msg.sender] = block.number;
            // TODO find out when to revert, amount == 0 ?
            ethBalances[msg.sender] += msg.value <= amount ? msg.value : amount;

            emit Deposit(msg.sender, token, msg.value);
            return true;
        } else if (token == hakToken) {

            // TODO steal later

            uint256 allowance = IERC20(hakToken).allowance(msg.sender, selfAddress);

            if (amount > allowance) {
                revert("insufficient allowance");
            }

            bool transferSuccessful = IERC20(hakToken).transferFrom(msg.sender, selfAddress, amount);

            if (!transferSuccessful) {
                revert("unsuccessful transfer from");
            }

            hakInterest[msg.sender] = getHakTotalInterest(msg.sender, block.number);
            hakLastBlockNumber[msg.sender] = block.number;
            hakBalances[msg.sender] += amount;

            emit Deposit(msg.sender, token, amount);
            return true;
        } else {
            revert("token not supported");
        }
    }

    function getEthTotalInterest(address customerAddress, uint currentBlockNumber) private view returns (uint256) {
        return (currentBlockNumber - ethLastBlockNumber[customerAddress]) * 3 * ethBalances[customerAddress] / 10000 + ethInterest[customerAddress];
    }

    function getHakTotalInterest(address customerAddress, uint currentBlockNumber) private view returns (uint256) {
        return (currentBlockNumber - hakLastBlockNumber[customerAddress]) * 3 * hakBalances[customerAddress] / 10000 + hakInterest[customerAddress];
    }

    function withdraw(address token, uint256 amount) external override returns (uint256) {
        if (token == ethToken) {
            if (ethBalances[msg.sender] == 0) {
                revert("no balance");
            }

            if (ethBalances[msg.sender] < amount) {
                revert("amount exceeds balance");
            }

            if (amount == 0) {
                amount = ethBalances[msg.sender];
            }

            uint256 totalInterest = getEthTotalInterest(msg.sender, block.number);

            ethLastBlockNumber[msg.sender] = block.number;
            ethBalances[msg.sender] -= amount;
            ethInterest[msg.sender] = 0;

            msg.sender.transfer(amount + totalInterest);
            emit Withdraw(msg.sender, token, amount + totalInterest);

            return amount + totalInterest;
        } else if (token == hakToken) {
            if (hakBalances[msg.sender] == 0) {
                revert("no balance");
            }

            if (hakBalances[msg.sender] < amount) {
                revert("amount exceeds balance");
            }

            if (amount == 0) {
                amount = hakBalances[msg.sender];
            }

            uint256 totalInterest = getHakTotalInterest(msg.sender, block.number);

            hakLastBlockNumber[msg.sender] = block.number;
            hakBalances[msg.sender] -= amount;
            hakInterest[msg.sender] = 0;

            IERC20(hakToken).approve(msg.sender, amount + totalInterest);

            emit Withdraw(msg.sender, token, amount + totalInterest);

            return amount + totalInterest;
        } else {
            revert("token not supported");
        }
    }

    function borrow(address token, uint256 amount)
    external
    override
    returns (uint256) {}

    function repay(address token, uint256 amount)
    payable
    external
    override
    returns (uint256) {}

    function liquidate(address token, address account)
    payable
    external
    override
    returns (bool) {}

    function getCollateralRatio(address token, address account)
    view
    public
    override
    returns (uint256) {}

    function getBalance(address token) view public override returns (uint256) {
        if (token == ethToken) {
            return ethBalances[msg.sender] + getEthTotalInterest(msg.sender, block.number);
        } else if (token == hakToken) {
            return hakBalances[msg.sender] + getHakTotalInterest(msg.sender, block.number);
        } else {
            revert("token not supported");
        }
    }
}
