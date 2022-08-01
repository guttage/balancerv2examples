// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeMath.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeERC20.sol";
import "@balancer-labs/v2-vault/contracts/interfaces/IVault.sol";

struct JoinPoolRequest {
    address[2] assets;
    uint256[2] maxAmountsIn;
    bytes userData;
    bool fromInternalBalance;
}


struct SingleSwap {
    bytes32 poolId;
    uint8 kind;
    address assetIn;
    address assetOut;
    uint256 amount;
    bytes userData;
}
struct FundManagement {
    address sender;
    bool fromInternalBalance;
    address payable recipient;
    bool toInternalBalance;
}


interface IBalancerV2Factory {
    function joinPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        JoinPoolRequest memory request
    ) external payable returns (uint256 amountCalculated);
    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256 amountCalculated);

}

contract BalancerExample {
    // Library usage
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    event Received(address, uint256);

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // Contract multisig
    address public multisig;
    address public vaultAddr;
    address public trader;
    IVault internal immutable _vault;
    // Token amount variables

    mapping(address => uint256) public balances;

    // Events
    event Deposited(address from, uint256 amount);
    event Withdraw(address to, uint256 amount);
    event Swapped(uint256 amount);
    event Changedtrader(address trader);

    constructor(IVault vault) {
        multisig = "your multisig addr here";
        vaultAddr = "Vault addr here";
        _vault = vault;
    }

    function _convertERC20sToAssets(IERC20[] memory tokens)
        internal
        pure
        returns (IAsset[] memory assets)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            assets := tokens
        }
    }

    // Modifier
    /**
     * @dev Throws if called by any account other than the multisig.
     */
    modifier onlyMultisig() {
        require(msg.sender == multisig, "Only multisig allowed");
        _;
    }


    /// @param token - ERC20 token which you want to withdraw.
    /// @param amount - amount to withdraw (in wei)
    function withdraw(IERC20 token, uint256 amount) public onlyMultisig {
       
        IERC20 tokenContract = IERC20(token);

        tokenContract.safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }


    //Proxy swaps through the vault contract

    function approve(address token) public onlyMultisig{
        // Approve token spending for vault

        IERC20(token).approve(
            0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce,
            ~uint256(0)
        );
    }

    function allowance(address token) public view returns (uint256) {
        //  Check allowance
        uint256 allowed = IERC20(token).allowance(
            address(this),
            0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce
        );
        return allowed;
    }

    //change owner of trader
    function changeTrader(address _trader) public onlyMultisig {
        trader = _trader;
        emit Changedtrader(trader);
    }

    /**
     * This function adds liquidity to a pool
     */
    function joinPool(
        bytes32 poolId,
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) public onlyMultisig {
        (IERC20[] memory tokens, , ) = _vault.getPoolTokens(poolId);

        // Now the pool is initialized we have to encode a different join into the userData

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: _convertERC20sToAssets(tokens),
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });

        address sender = address(this);
        address recipient = address(this);
        _vault.joinPool(poolId, sender, recipient, request);
    }

    /**
     * This function removes liquidity from a pool
     */

    function exitPool(
        bytes32 poolId,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) public onlyMultisig {
        (IERC20[] memory tokens, , ) = _vault.getPoolTokens(poolId);

        // We can ask the Vault to keep the tokens we receive in our internal balance to save gas
        bool toInternalBalance = false;

        // As we're exiting the pool we need to make an ExitPoolRequest instead
        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: _convertERC20sToAssets(tokens),
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: toInternalBalance
        });

        address sender = address(this);
        address payable recipient = payable(address(this));
        _vault.exitPool(poolId, sender, recipient, request);
    }


    //Proxy swaps through the vault contract
    function proxyswap(
        bytes32 poolId,
        uint8 kind,
        address assetIn,
        address assetOut,
        uint256 amount,
        uint256 _limit
    ) public onlyMultisig returns (uint256) {
        SingleSwap memory singleswap;
        FundManagement memory funds;

        singleswap.poolId = poolId;
        singleswap.kind = kind;
        singleswap.assetIn = assetIn;
        singleswap.assetOut = assetOut;
        singleswap.amount = amount;
        singleswap.userData;

        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = payable(address(this));
        funds.toInternalBalance = false;
        uint256 limit = _limit;
        uint256 deadline = ~uint256(0);

        uint256 result =  IBalancerV2Factory(vaultAddr).swap(
            singleswap,
            funds,
            limit,
            deadline
        );
        emit Swapped(result);
        return result;
    }


}
