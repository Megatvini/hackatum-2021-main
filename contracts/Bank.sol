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

    uint256 WEI_MULT = 1_000_000_000_000_000_000;

    struct CurrencyBalance {
        uint256 balance;
        uint256 interest;
        uint256 lastBlockNumber;
        uint256 interestRate;
    }


    mapping(address => CurrencyBalance) ethDeposits;
    mapping(address => CurrencyBalance) ethLoans;

    mapping(address => CurrencyBalance) hakDeposits;
    mapping(address => uint256) hakCollaterals;

    constructor(address _priceOracle, address payable _hakToken) {
        priceOracle = _priceOracle;
        hakToken = _hakToken;
        ethToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        selfAddress = address(this);
    }

    function calculateSimpleInterest(CurrencyBalance storage currency, uint256 curBlockNumber) private view returns(uint256) {
        return (curBlockNumber - currency.lastBlockNumber) * currency.interestRate * currency.balance / 100 / 100; // 100 blocks 3 percent
    }

    function updateCurrencyInterest(CurrencyBalance storage currency, uint256 curBlockNumber) private {
        currency.interest += calculateSimpleInterest(currency, curBlockNumber);
    }

    function addBalance(CurrencyBalance storage currency, uint256 amount, uint256 curBlockNumber) private {
        updateCurrencyInterest(currency, curBlockNumber);
        currency.balance += amount;
        currency.lastBlockNumber = curBlockNumber;
    }

    function removeBalanceAndInterest(CurrencyBalance storage currency, uint256 amount, uint256 curBlockNumber) private returns(uint256) {
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
        uint256 msgValue = msg.value * WEI_MULT;
        amount *= WEI_MULT;


        if (token == ethToken) {
            // TODO find out when to revert, amount == 0 ?

            CurrencyBalance storage currency = ethDeposits[msg.sender];
            currency.interestRate = 3;
            uint256 res = msgValue <= amount ? msgValue : amount;
            addBalance(currency, res, block.number);
            emit Deposit(msg.sender, token, res / WEI_MULT);
            return true;
        } else if (token == hakToken) {
            // TODO steal later

            uint256 allowance = IERC20(hakToken).allowance(msg.sender, selfAddress) * WEI_MULT;

            if (amount > allowance) {
                revert("insufficient allowance");
            }

            bool transferSuccessful = IERC20(hakToken).transferFrom(msg.sender, selfAddress, amount / WEI_MULT);

            if (!transferSuccessful) {
                revert("unsuccessful transfer from");
            }

            CurrencyBalance storage currency = hakDeposits[msg.sender];
            currency.interestRate = 3;
            addBalance(hakDeposits[msg.sender], amount, block.number);

            emit Deposit(msg.sender, token, amount / WEI_MULT);
            return true;
        } else {
            revert("token not supported");
        }
    }

    function withdraw(address token, uint256 amount) external override returns (uint256) {
        amount *= WEI_MULT;

        CurrencyBalance storage currency;

        if (token == ethToken) {
            currency = ethDeposits[msg.sender];
        } else if (token == hakToken) {
            currency = hakDeposits[msg.sender];
        } else {
            revert("token not supported");
        }

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
        if (token == ethToken) {
            msg.sender.transfer(totalAmount / WEI_MULT);
        } else {
            IERC20(hakToken).approve(msg.sender, totalAmount / WEI_MULT);
        }
        
        emit Withdraw(msg.sender, token, totalAmount / WEI_MULT);
        return totalAmount / WEI_MULT;
    }

    function borrow(address token, uint256 amount) external override returns (uint256) {
        amount *= WEI_MULT;

        if (token != ethToken) {
            revert("We only load out ETH");
        }

        uint256 totalHakDeposited = getTotalBalance(hakDeposits[msg.sender], block.number);
        if (totalHakDeposited == 0) {
            revert("no collateral deposited");
        }

        uint256 totalHakAvailable = totalHakDeposited - hakCollaterals[msg.sender];

        uint256 hakPriceInWei = IPriceOracle(priceOracle).getVirtualPrice(hakToken);
        uint256 maxWeiAvailableToBorrow = hakPriceInWei * totalHakAvailable * 100 / 150 / WEI_MULT ;

        if (amount == 0) {
            amount = maxWeiAvailableToBorrow;
        }

        if (amount > maxWeiAvailableToBorrow) {
            revert("borrow would exceed collateral ratio");
        }

        uint256 collateralUsed = amount * WEI_MULT * 150 / hakPriceInWei / 100;
        hakCollaterals[msg.sender] +=  collateralUsed;

        CurrencyBalance storage ethLoan = ethLoans[msg.sender];
        ethLoan.interestRate = 5;
        addBalance(ethLoan, amount, block.number);

        totalHakDeposited = getTotalBalance(hakDeposits[msg.sender], block.number);
        uint256 newCollateralRatio = totalHakDeposited * hakPriceInWei / getTotalBalance(ethLoans[msg.sender], block.number) / 100_000_000_000_000;

        msg.sender.transfer(amount / WEI_MULT);
        emit Borrow(msg.sender, token, amount / WEI_MULT, newCollateralRatio);

        return newCollateralRatio;
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

    function getCollateralRatio(address token, address account) view public override returns (uint256) {
        if (token != hakToken) {
            revert("Only know ETH collateral");
        }

        uint256 hakPriceInWei = IPriceOracle(priceOracle).getVirtualPrice(hakToken); // * 1_000_000_000_000_000_000
        uint256 totalHakDepositedWei = getTotalBalance(hakDeposits[account], block.number);
        uint256 totalEthBorrowedWei = getTotalBalance(ethLoans[account], block.number);

        if (totalEthBorrowedWei == 0) {
            return type(uint256).max;
        } 

        return totalHakDepositedWei * hakPriceInWei / totalEthBorrowedWei / 100_000_000_000_000;
    }

    function getBalance(address token) view public override returns (uint256) {
        if (token == ethToken) {
            return getTotalBalance(ethDeposits[msg.sender], block.number) / WEI_MULT;
        } else if (token == hakToken) {
            return getTotalBalance(hakDeposits[msg.sender], block.number) / WEI_MULT;
        } else {
            revert("token not supported");
        }
    }
}
