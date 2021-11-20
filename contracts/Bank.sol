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

    struct AccountInfo {

        uint256 ethBalance;
        uint256 ethInterest;
        uint ethLastBlockNumber;

        uint256 hakBalance;
        uint256 hakInterest;
        uint hakLastBlockNumber;

    }

    mapping(address => AccountInfo) accountsInfo;


    constructor(address _priceOracle, address payable _hakToken) {
        priceOracle = _priceOracle;
        hakToken = _hakToken;
        ethToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        selfAddress = address(this);
    }

    function deposit(address token, uint256 amount) payable external override returns (bool) {
        if (token == ethToken) {
            accountsInfo[msg.sender].ethInterest = getEthTotalInterest(msg.sender, block.number);
            accountsInfo[msg.sender].ethLastBlockNumber = block.number;
            // TODO find out when to revert, amount == 0 ?
            accountsInfo[msg.sender].ethBalance += msg.value <= amount ? msg.value : amount;

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

            accountsInfo[msg.sender].hakInterest = getHakTotalInterest(msg.sender, block.number);
            accountsInfo[msg.sender].hakLastBlockNumber = block.number;
            accountsInfo[msg.sender].hakBalance += amount;

            emit Deposit(msg.sender, token, amount);
            return true;
        } else {
            revert("token not supported");
        }
    }

    function getEthTotalInterest(address customerAddress, uint currentBlockNumber) private view returns (uint256) {
        return (currentBlockNumber - accountsInfo[customerAddress].ethLastBlockNumber) * 3 * accountsInfo[customerAddress].ethBalance / 10000 + accountsInfo[customerAddress].ethInterest;
    }

    function getHakTotalInterest(address customerAddress, uint currentBlockNumber) private view returns (uint256) {
        return (currentBlockNumber - accountsInfo[customerAddress].hakLastBlockNumber) * 3 * accountsInfo[customerAddress].hakBalance / 10000 + accountsInfo[customerAddress].hakInterest;
    }

    function withdraw(address token, uint256 amount) external override returns (uint256) {
        if (token == ethToken) {
            if (accountsInfo[msg.sender].ethBalance == 0) {
                revert("no balance");
            }

            if (accountsInfo[msg.sender].ethBalance < amount) {
                revert("amount exceeds balance");
            }

            if (amount == 0) {
                amount = accountsInfo[msg.sender].ethBalance;
            }

            uint256 totalInterest = getEthTotalInterest(msg.sender, block.number);

            accountsInfo[msg.sender].ethLastBlockNumber = block.number;
            accountsInfo[msg.sender].ethBalance -= amount;
            accountsInfo[msg.sender].ethInterest = 0;

            msg.sender.transfer(amount + totalInterest);
            emit Withdraw(msg.sender, token, amount + totalInterest);

            return amount + totalInterest;
        } else if (token == hakToken) {
            if (accountsInfo[msg.sender].hakBalance == 0) {
                revert("no balance");
            }

            if (accountsInfo[msg.sender].hakBalance < amount) {
                revert("amount exceeds balance");
            }

            if (amount == 0) {
                amount = accountsInfo[msg.sender].hakBalance;
            }

            uint256 totalInterest = getHakTotalInterest(msg.sender, block.number);

            accountsInfo[msg.sender].hakLastBlockNumber = block.number;
            accountsInfo[msg.sender].hakBalance -= amount;
            accountsInfo[msg.sender].hakInterest = 0;

            IERC20(hakToken).approve(msg.sender, amount + totalInterest);

            emit Withdraw(msg.sender, token, amount + totalInterest);

            return amount + totalInterest;
        } else {
            revert("token not supported");
        }
    }

    function borrow(address token, uint256 amount) external override returns (uint256) {
        if (token != ethToken) {
            revert();
        }

//        uint x = (deposits[account] + accruedInterest[account]) * 10000 / (borrowed[account] + owedInterest[account]) >= 15000;

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
            return accountsInfo[msg.sender].ethBalance + getEthTotalInterest(msg.sender, block.number);
        } else if (token == hakToken) {
            return accountsInfo[msg.sender].hakBalance + getHakTotalInterest(msg.sender, block.number);
        } else {
            revert("token not supported");
        }
    }
}
