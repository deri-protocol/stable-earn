// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IStaker.sol";
import "./IStaderSource.sol";
import "../library/SafeMath.sol";
import "../utils/NameVersion.sol";
import "../token/IERC20.sol";
import "../swapper/ISwapper.sol";
import "../library/SafeERC20.sol";
import "./StakeStaderStorage.sol";

contract StakeStaderImplementation is StakeStaderStorage, IStaker, NameVersion {
    using SafeMath for int256;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IStaderSource public immutable source;
    IERC20 public immutable stakerBnb;
    ISwapper public immutable swapper;
    IERC20 public immutable tokenB0;
    address public immutable fund;

    constructor(
        address source_,
        address stakerBnb_,
        address swapper_,
        address tokenB0_,
        address _fund
    ) NameVersion("StakeStaderImplementation", "1.0.0") {
        source = IStaderSource(source_);
        stakerBnb = IERC20(stakerBnb_);
        swapper = ISwapper(swapper_);
        tokenB0 = IERC20(tokenB0_);
        fund = _fund;
    }

    function approve_() external _onlyAdmin_ {
        stakerBnb.approve(address(source), type(uint256).max);
        _approveSwapper(address(stakerBnb));
    }

    modifier onlyFund() {
        require(msg.sender == fund, "only fund");
        _;
    }

    function deposit() external payable {
        source.deposit{value: address(this).balance}();
    }

    function convertToBnb(uint256 amountInStakerBnb)
        external
        view
        returns (uint256 bnbAmount)
    {
        bnbAmount = source.convertBnbXToBnb(amountInStakerBnb);
    }

    function convertToStakerBnb(uint256 amountInBnb)
        external
        view
        returns (uint256 stakerBnbAmount)
    {
        stakerBnbAmount = source.convertBnbToBnbX(amountInBnb);
    }

    function requestWithdraw(address user, uint256 amount) external onlyFund {
        source.requestWithdraw(amount);
        withdrawlRequestNum++;
        withdrawalRequestId[user] = withdrawlRequestNum;
        withdrawlRequestUser[withdrawlRequestNum] = user;
    }

    function claimWithdraw(address user) external onlyFund {
        uint256 requestId = withdrawalRequestId[user];
        require(requestId > 0, "claimWithdraw: invalid request");

        address lastUser = withdrawlRequestUser[withdrawlRequestNum];
        withdrawalRequestId[user] = 0;
        withdrawlRequestUser[withdrawlRequestNum] = address(0);

        if (user != lastUser) {
            withdrawalRequestId[lastUser] = requestId;
            withdrawlRequestUser[requestId] = lastUser;
        }
        withdrawlRequestNum--;

        source.claimWithdraw(requestId - 1);
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success, "claimWithdraw: fail");
    }

    function getUserRequestStatus(address user)
        external
        view
        returns (bool, uint256)
    {
        uint256 requestId = withdrawalRequestId[user];
        return source.getUserRequestStatus(address(this), requestId - 1);
    }

    function swapStakerBnbToB0(uint256 amountInStakerBnb)
        external
        onlyFund
        returns (uint256)
    {
        (uint256 resultB0, ) = swapper.swapExactBXForB0(
            address(stakerBnb),
            amountInStakerBnb
        );
        tokenB0.transfer(msg.sender, resultB0);
        return resultB0;
    }

    function _approveSwapper(address underlying) internal {
        uint256 allowance = IERC20(underlying).allowance(
            address(this),
            address(swapper)
        );
        if (allowance != type(uint256).max) {
            if (allowance != 0) {
                IERC20(underlying).safeApprove(address(swapper), 0);
            }
            IERC20(underlying).safeApprove(address(swapper), type(uint256).max);
        }
    }

    receive() external payable {}
}
