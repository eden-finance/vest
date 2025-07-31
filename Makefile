# .Makefile

ENV_FILE=.env
DEPLOY_OUTPUT=deployment.log

all: build

build:
	forge build --sizes

test:
	forge test --gas-report

deploy-core:
	source $(ENV_FILE) && ./save-core-output.sh

deploy-proxy:
	source $(ENV_FILE) && forge script script/02_DeployProxy.s.sol:DeployProxyScript --broadcast --rpc-url $$SEPOLIA_RPC --private-key $$PRIVATE_KEY

clean:
	forge clean
	rm -f $(DEPLOY_OUTPUT)
