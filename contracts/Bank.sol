//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "./interfaces/IBank.sol";
import "./interfaces/IPriceOracle.sol";

contract Bank is IBank {
    address priceOracle;
    address hakToken;

    mapping(address => uint256) ethBalances;
    mapping(address => uint256) ethInterest;
    mapping(address => uint) ethLastBlockNumber;

    constructor(address _priceOracle, address _hakToken) {
        priceOracle = _priceOracle;
        hakToken = _hakToken;
    }

    function deposit(address token, uint256 amount) payable external override returns (bool) {
        if (token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            ethInterest[msg.sender] = getTotalInterest(msg.sender, block.number);
            ethLastBlockNumber[msg.sender] = block.number;
            ethBalances[msg.sender] += msg.value <= amount ? msg.value : amount;

            emit Deposit(msg.sender, token, msg.value);
            return true;
        } else if (token == hakToken) {
            return true;
        } else {
            revert("token not supported");
        }
    }

    function getTotalInterest(address customerAddress, uint currentBlockNumber) private view returns (uint256) {
        return (currentBlockNumber - ethLastBlockNumber[customerAddress]) * 3 * ethBalances[customerAddress] / 10000 + ethInterest[customerAddress];
    }

    function withdraw(address token, uint256 amount) external override returns (uint256) {
        if (token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            if (ethBalances[msg.sender] == 0) {
                revert("no balance");
            }

            if (ethBalances[msg.sender] < amount) {
                revert("amount exceeds balance");
            }

            if (amount == 0) {
                amount = ethBalances[msg.sender];
            }

            uint256 totalInterest = getTotalInterest(msg.sender, block.number);

            ethLastBlockNumber[msg.sender] = block.number;
            ethBalances[msg.sender] -= amount;
            ethInterest[msg.sender] = 0;

            emit Withdraw(msg.sender, token, amount + totalInterest);

            return amount + totalInterest;
        } else if (token == hakToken) {
            return 0;
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
        if (token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            return ethBalances[msg.sender] + getTotalInterest(msg.sender, block.number);
        } else if (token == hakToken) {
            return 0;
        } else {
            revert("token not supported");
        }
    }
}
