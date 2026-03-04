-include .env

.PHONY: all test deploy

build :; forge build

compile :; forge compile

test :; forge test

test -vvv :; forge test -vvv

coverage :; forge coverage

install :; forge install cyfrin/foundry-devops@0.2.2 && forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 && forge install foundry-rs/forge-std@v1.8.2 && forge install transmissions11/solmate@v6

deploy-sepolia: 
	@forge script script/DeployKUSDEngine.s.sol:DeployKUSDEngine --rpc-url $(SEPOLIA_RPC_URL) --account myaccount --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

deploy-base: 
	@forge script script/DeployKUSDEngine.s.sol:DeployKUSDEngine --rpc-url $(BASE_RPC_URL) --account myaccount --broadcast --verify --etherscan-api-key $(BASESCAN_API_KEY) -vvvv

