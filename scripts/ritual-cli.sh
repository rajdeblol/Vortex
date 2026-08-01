#!/bin/bash
# ritual-cli.sh
# Minimal helper to interact with LiveYieldOracle on Ritual

set -e

if [ -z "$1" ]; then
  echo "Usage: ./scripts/ritual-cli.sh <command> [args]"
  echo "Commands:"
  echo "  deploy          - Deploy contracts (requires PRIVATE_KEY)"
  echo "  fund <amount>   - Fund RitualWallet (in wei)"
  echo "  schedule <freq> - Start scheduler with block frequency"
  echo "  state           - Read current oracle state"
  exit 1
fi

CMD=$1
shift

case $CMD in
  deploy)
    echo "Deploying to Ritual..."
    forge script script/DeployRitual.s.sol:DeployRitual --rpc-url ritual --broadcast --verify
    ;;

  fund)
    AMOUNT=${1:-1000000000000000000} # 1 ETH default
    ORACLE=${ORACLE:-$(cat .oracle-address 2>/dev/null || echo "")}
    if [ -z "$ORACLE" ]; then
      echo "Set ORACLE env var or create .oracle-address file"
      exit 1
    fi
    cast send $ORACLE "fundRitualWallet()" --value $AMOUNT --rpc-url ritual --private-key $PRIVATE_KEY
    ;;

  schedule)
    FREQ=${1:-100}
    ORACLE=${ORACLE:-$(cat .oracle-address 2>/dev/null || echo "")}
    cast send $ORACLE "startScheduler(uint256)" $FREQ --rpc-url ritual --private-key $PRIVATE_KEY
    ;;

  state)
    ORACLE=${ORACLE:-$(cat .oracle-address 2>/dev/null || echo "")}
    echo "Current Targets:"
    cast call $ORACLE "getCurrentTargets()(uint256[])" --rpc-url ritual
    echo "Last Update:"
    cast call $ORACLE "getLastUpdate()(uint256,uint256)" --rpc-url ritual
    ;;
  *)
    echo "Unknown command: $CMD"
    exit 1
    ;;
esac