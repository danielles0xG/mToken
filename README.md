# ERC20 interest-bearing token 

ERC20 interest-bearing token that continuously accrues yield to its holders.

- Admin can mint new tokens to users at any moment in time
- Users of the token can hold, transfer, and burn tokens while continuously accruing interest on their existing balances.
- Rate (APY) is initially set by an admin of the token and is defined in [BPS](https://www.investopedia.com/terms/b/basispoint.asp).
- Admin is able to change the interest rate at any moment in time.



### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Deploy

```shell
$ forge script script/mTokenDeploy.s.sol:mTokenDeploy --rpc-url <your_rpc_url> --private-key <your_private_key>
```
