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

    struct CurrencyBalance {
        uint256 balance;
        uint256 interest;
        uint lastBlockNumber;
        uint256 interestRate;
    }


    mapping(address => CurrencyBalance) ethDeposits;
    mapping(address => CurrencyBalance) ethLoans;
    mapping(address => CurrencyBalance) hakDeposits;


    constructor(address _priceOracle, address payable _hakToken) {
        priceOracle = _priceOracle;
        hakToken = _hakToken;
        ethToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        selfAddress = address(this);
    }

    function calculateSimpleInterest(CurrencyBalance storage currency, uint curBlockNumber) private view returns(uint256) {
        return (curBlockNumber - currency.lastBlockNumber) * currency.interestRate * currency.balance / 100 / 100; // 100 blocks 3 percent
    }

    function updateCurrencyInterest(CurrencyBalance storage currency, uint curBlockNumber) private {
        currency.interest += calculateSimpleInterest(currency, curBlockNumber);
    }

    function addBalance(CurrencyBalance storage currency, uint256 amount, uint curBlockNumber) private {
        updateCurrencyInterest(currency, curBlockNumber);
        currency.balance += amount;
        currency.lastBlockNumber = curBlockNumber;
    }

    function removeBalanceAndInterest(CurrencyBalance storage currency, uint256 amount, uint curBlockNumber) private returns(uint256) {
        updateCurrencyInterest(currency, curBlockNumber);
        
        uint256 totalRemoved = amount + currency.interest;
        currency.balance -= amount;
        currency.interest = 0;
        currency.lastBlockNumber = curBlockNumber;
        return totalRemoved;
    }

    function getTotalBalance(CurrencyBalance storage currency, uint256 curBlockNumber) private view returns(uint256) {
        return currency.balance + currency.interest + calculateSimpleInterest(currency, curBlockNumber);
    } 

    function deposit(address token, uint256 amount) payable external override returns (bool) {
        if (token == ethToken) {
            // TODO find out when to revert, amount == 0 ?
            addBalance(ethDeposits[msg.sender], msg.value <= amount ? msg.value : amount, block.number);
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

            addBalance(hakDeposits[msg.sender], amount, block.number);
            emit Deposit(msg.sender, token, amount);
            return true;
        } else {
            revert("token not supported");
        }
    }

    function withdraw(address token, uint256 amount) external override returns (uint256) {
        if (token == ethToken) {
            CurrencyBalance storage currency = ethDeposits[msg.sender];

            if (currency.balance == 0) {
                revert("no balance");
            }

            if (currency.balance < amount) {
                revert("amount exceeds balance");
            }

            if (amount == 0) {
                amount = currency.balance;
            }

            uint256 totalAmount = removeBalanceAndInterest(currency, amount, block.number);
            msg.sender.transfer(totalAmount);
            emit Withdraw(msg.sender, token, totalAmount);

            return totalAmount;
        } else if (token == hakToken) {
            CurrencyBalance storage currency = hakDeposits[msg.sender];

            if (currency.balance == 0) {
                revert("no balance");
            }

            if (currency.balance < amount) {
                revert("amount exceeds balance");
            }

            if (amount == 0) {
                amount = currency.balance;
            }

            uint256 totalAmount = removeBalanceAndInterest(currency, amount, block.number);
            IERC20(hakToken).approve(msg.sender, totalAmount);

            emit Withdraw(msg.sender, token, totalAmount);
            return totalAmount;
        } else {
            revert("token not supported");
        }
    }

    function borrow(address token, uint256 amount) external override returns (uint256) {
        if (token != ethToken) {
            revert();
        }

        return 0;
    }

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
            return getTotalBalance(ethDeposits[msg.sender], block.number);
        } else if (token == hakToken) {
            return getTotalBalance(hakDeposits[msg.sender], block.number);
        } else {
            revert("token not supported");
        }
    }
}
