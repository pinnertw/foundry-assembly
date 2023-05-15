
library IterableMapping {
    // Iterable mapping from address to uint;
    struct Map {
        address[] keys;
        mapping(address => uint) values;
        mapping(address => uint) indexOf;
        mapping(address => bool) inserted;
    }

    function get(Map storage map, address key) public view returns (uint) {
        return map.values[key];
    }

    function getIndexOfKey(Map storage map, address key) public view returns (int) {
        if(!map.inserted[key]) {
            return -1;
        }
        return int(map.indexOf[key]);
    }

    function getKeyAtIndex(Map storage map, uint index) public view returns (address) {
        return map.keys[index];
    }

    function size(Map storage map) public view returns (uint) {
        return map.keys.length;
    }

    function set(Map storage map, address key, uint val) public {
        if (map.inserted[key]) {
            map.values[key] = val;
        } else {
            map.inserted[key] = true;
            map.values[key] = val;
            map.indexOf[key] = map.keys.length;
            map.keys.push(key);
        }
    }

    function remove(Map storage map, address key) public {
        if (!map.inserted[key]) {
            return;
        }

        delete map.inserted[key];
        delete map.values[key];

        uint index = map.indexOf[key];
        uint lastIndex = map.keys.length - 1;
        address lastKey = map.keys[lastIndex];

        map.indexOf[lastKey] = index;
        delete map.indexOf[key];

        map.keys[index] = lastKey;
        map.keys.pop();
    }
}
contract Printer is ERC20, Ownable {
    using SafeMath for uint256;

    uint256 constant private TOTAL_SUPPLY = 1_000_000_000 * 1e18;
    uint256 constant public MAX_WALLET = TOTAL_SUPPLY * 2 / 100; 
    uint256 public swapTokensAtAmount = TOTAL_SUPPLY * 2 / 1000; 
    
    DividendTracker immutable public DIVIDEND_TRACKER;

    address public immutable UNISWAP_PAIR;
    IUniswapV2Router02 constant UNISWAP_ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address constant UNISWAP_UNIVERSAL_ROUTER = 0xEf1c6E67703c7BD7107eed8303Fbe6EC2554BF6B;

    address immutable DEPLOYER;
    address payable public developmentWallet; 
    address constant public TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH

    uint256 tradingFee = 5;
    uint256 tradingFeeSellIncrease = 0;

    struct RewardSettings {
        uint64 gasForProcessing;
        uint64 percentRewardPool;
        uint64 rewardPoolFrequency;
        uint64 lastRewardPoolingTime;
    }
    uint256 constant MAX_REWARDPOOL_ITERATIONS = 5;
    RewardSettings public rewardSettings = RewardSettings(80_000, 125, 900 seconds, 0);
    uint256 constant MIN_TOKENS_FOR_DIVIDENDS = 1_000_000 * (10**18);

    bool swapping;
    uint256 step;
    bool tradingOpen = false;

    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);
    event IncludeInDividends(address indexed wallet);
    event ExcludeFromDividends(address indexed wallet);
    event SendDividends(uint256 indexed tokensSwapped);
    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    constructor() ERC20("MoneyPrinter", "BRRR") {
        address deployer_ = address(msg.sender);
        DEPLOYER = deployer_;
        DIVIDEND_TRACKER = new DividendTracker();
         // Create a uniswap pair for this new token
        UNISWAP_PAIR = IUniswapV2Factory(UNISWAP_ROUTER.factory())
            .createPair(address(this), UNISWAP_ROUTER.WETH());
  
        // exclude from receiving dividends
        DIVIDEND_TRACKER.excludeFromDividends(address(DIVIDEND_TRACKER));
        DIVIDEND_TRACKER.excludeFromDividends(address(this));
        DIVIDEND_TRACKER.excludeFromDividends(deployer_);
        DIVIDEND_TRACKER.excludeFromDividends(address(UNISWAP_ROUTER));
        DIVIDEND_TRACKER.excludeFromDividends(UNISWAP_UNIVERSAL_ROUTER); 
        DIVIDEND_TRACKER.excludeFromDividends(address(0xdead));
        DIVIDEND_TRACKER.excludeFromDividends(UNISWAP_PAIR);
        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(address(deployer_), TOTAL_SUPPLY);
    }

    receive() external payable {}
    
    modifier tradingCheck(address from) {
        require(tradingOpen || from == owner() || from == DEPLOYER);
        _;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override tradingCheck(from) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        if(amount == 0) {
            return super._transfer(from, to, 0);
        }
        else if(from == address(this) || to == DEPLOYER){
            return super._transfer(from, to, amount);
        }

        uint256 receiverPreBalance = balanceOf(to);
        if (to != UNISWAP_PAIR) {
            require(receiverPreBalance + amount <= MAX_WALLET, "Exceeding the max wallet limit");
        }

        bool rewardsActive = tradingFee == 0;

        uint256 contractTokenBalance = balanceOf(address(this));
        bool shouldSwap = shouldSwapBack(from, contractTokenBalance);
        if(shouldSwap) {
            swapping = true;
            swapBack(rewardsActive);
            swapping = false;
        }
        
        if(rewardsActive && !shouldSwap && to == UNISWAP_PAIR && 
            block.timestamp >= rewardSettings.lastRewardPoolingTime + rewardSettings.rewardPoolFrequency){
            rewardPool();            
        }

        if(!rewardsActive){
            uint256 feeAmount = takeFee(from) * amount / 100;
            super._transfer(from, address(this), feeAmount);    
            amount -= feeAmount;
        }

        super._transfer(from, to, amount);

        try DIVIDEND_TRACKER.setBalance(payable(from), balanceOf(from)) {} catch {}
        try DIVIDEND_TRACKER.setBalance(payable(to), balanceOf(to)) {} catch {}

        bool newDividendReceiver = from == UNISWAP_PAIR && (receiverPreBalance < MIN_TOKENS_FOR_DIVIDENDS && (receiverPreBalance + amount >= MIN_TOKENS_FOR_DIVIDENDS));
        if(!shouldSwap && rewardsActive && !newDividendReceiver) {
            uint256 gas = rewardSettings.gasForProcessing;
            try DIVIDEND_TRACKER.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
                emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
            }
            catch {}
        }
    }

    function rewardPool() private {
        uint256 nrIterations = (block.timestamp - rewardSettings.lastRewardPoolingTime) / rewardSettings.rewardPoolFrequency;
            rewardSettings.lastRewardPoolingTime = uint64(block.timestamp - 
                (block.timestamp - rewardSettings.lastRewardPoolingTime) % rewardSettings.rewardPoolFrequency); 
            uint256 liquidityPairBalance = this.balanceOf(UNISWAP_PAIR);
            uint256 totalAmountToReward = 0;

        if(nrIterations > MAX_REWARDPOOL_ITERATIONS){
            nrIterations = MAX_REWARDPOOL_ITERATIONS;        
        }

        for(uint256 i=0;i<nrIterations;i++){
            uint256 amountToReward = liquidityPairBalance.mul(rewardSettings.percentRewardPool).div(10_000);    
            liquidityPairBalance -= amountToReward;
            totalAmountToReward += amountToReward;
        }
        super._transfer(UNISWAP_PAIR, address(this), totalAmountToReward);
        IUniswapV2Pair(UNISWAP_PAIR).sync();
    }
    
    function takeFee(address from) private view returns (uint256 fee){
        fee = (from == UNISWAP_PAIR ? tradingFee : (tradingFee + tradingFeeSellIncrease));
    }

    function shouldSwapBack(address from, uint256 contractTokenBalance) private view returns (bool swapIt) {
        swapIt = contractTokenBalance >= swapTokensAtAmount && from != UNISWAP_PAIR && (developmentWallet != address(0));
    }

    function swapBack(bool rewardsActive) private {
        uint256 contractBalance = balanceOf(address(this));
        if(contractBalance > swapTokensAtAmount * 5)
            contractBalance = swapTokensAtAmount * 5;
            
        if(rewardsActive){
            uint256 tokenBalance = IERC20(TOKEN).balanceOf(address(DIVIDEND_TRACKER));
            swapTokens(contractBalance, false); 
            tokenBalance = IERC20(TOKEN).balanceOf(address(DIVIDEND_TRACKER)) - tokenBalance;
            DIVIDEND_TRACKER.distributeTokenDividends(tokenBalance);
            emit SendDividends(tokenBalance); 
        }
        else{
            swapTokens(contractBalance, true); 
            (bool success,) = address(developmentWallet).call{value: address(this).balance}(""); success;
        }
    }

    function swapTokens(uint256 tokenAmount, bool swapForEth) private {
        if(allowance(address(this), address(UNISWAP_ROUTER)) < tokenAmount)
            _approve(address(this), address(UNISWAP_ROUTER), TOTAL_SUPPLY);
        
        if(swapForEth){
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = TOKEN;
            // make the swap
            UNISWAP_ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(
                tokenAmount,
                0, // accept any amount of ETH
                path,
                address(this),
                block.timestamp
            );
        }
        else{
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = TOKEN;            
            // make the swap
            UNISWAP_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                tokenAmount,
                0, // accept any amount of ETH
                path,
                address(DIVIDEND_TRACKER),
                block.timestamp
            );
        }
    }

    function setFees(uint256 newFee, uint256 newSellFeeIncrease) external onlyOwner {  
        tradingFee = newFee;
        tradingFeeSellIncrease = newSellFeeIncrease;
        if(tradingFee == 0 && rewardSettings.lastRewardPoolingTime == 0)
            rewardSettings.lastRewardPoolingTime = uint64(block.timestamp);
    }

    function openTrading() external onlyOwner {
        assert(step > 0);
        tradingOpen = true;
    }

    function initialize(uint256 steps) external onlyOwner {
        step+=steps;
    }
  
    function changeSwapAmount(uint256 promille) external {
        require(msg.sender == DEPLOYER);
        require(promille > 0);
        swapTokensAtAmount = promille * TOTAL_SUPPLY / 1000;
    }

    function setRewardPoolSettings(uint64 _frequencyInSeconds, uint64 _percent) external {
        require(msg.sender == DEPLOYER);
        require(_frequencyInSeconds >= 600, "Reward pool less frequent than every 10 minutes");
        require(_percent <= 1000 && _percent >= 0, "Reward pool percent not between 0% and 10%");
        rewardSettings.rewardPoolFrequency = _frequencyInSeconds;
        rewardSettings.percentRewardPool = _percent;
    }

    function withdrawStuckEth() external {
        require(msg.sender == DEPLOYER);
        (bool success,) = address(msg.sender).call{value: address(this).balance}("");
        require(success, "Failed to withdraw stuck eth");
    }

    function updateGasForProcessing(uint64 newValue) external {
        require(msg.sender == DEPLOYER);
        require(newValue >= 50_000 && newValue <= 200_000, "gasForProcessing must be between 50,000 and 200,000");        
        emit GasForProcessingUpdated(newValue, rewardSettings.gasForProcessing);
        rewardSettings.gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 newClaimWait) external {
        require(msg.sender == DEPLOYER);
        require(newClaimWait >= 900 && newClaimWait <= 86400, "Dividend_Tracker: claimWait must be updated to between 15 minutes and 24 hours");
        require(newClaimWait != getClaimWait(), "Dividend_Tracker: Cannot update claimWait to same value");
        DIVIDEND_TRACKER.updateClaimWait(newClaimWait);
    }

    function excludeFromDividends(address account) external onlyOwner {
        DIVIDEND_TRACKER.excludeFromDividends(account);
        emit ExcludeFromDividends(account);
    }

    function includeInDividends(address account) external onlyOwner {
        DIVIDEND_TRACKER.includeInDividends(account);
        emit IncludeInDividends(account);
    }

    function setDevelopmentWallet(address payable newDevelopmentWallet) external onlyOwner {
        require(newDevelopmentWallet != developmentWallet);
        developmentWallet = newDevelopmentWallet;
    }
    
    function getClaimWait() public view returns(uint256) {
        return DIVIDEND_TRACKER.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return DIVIDEND_TRACKER.totalDividendsDistributed();
    }

    function withdrawableDividendOf(address account) public view returns(uint256) {
        return DIVIDEND_TRACKER.withdrawableDividendOf(account);
    }

    function dividendTokenBalanceOf(address account) public view returns (uint256) {
        return DIVIDEND_TRACKER.holderBalance(account);
    }

    function getAccountDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return DIVIDEND_TRACKER.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return DIVIDEND_TRACKER.getAccountAtIndex(index);
    }

    function processDividendTracker(uint256 gas) external {
        (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = DIVIDEND_TRACKER.process(gas);
        emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim() external {
        uint256 lastClaimTime = DIVIDEND_TRACKER.lastClaimTimes(msg.sender);
        require(block.timestamp.sub(lastClaimTime) >= getClaimWait());
        DIVIDEND_TRACKER.processAccount(payable(msg.sender), false);
    }

    function getLastProcessedIndex() external view returns(uint256) {
        return DIVIDEND_TRACKER.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return DIVIDEND_TRACKER.getNumberOfTokenHolders();
    }
    
    function getNumberOfDividends() external view returns(uint256) {
        return DIVIDEND_TRACKER.totalBalance();
    }
}

contract DividendPayingToken is DividendPayingTokenInterface, DividendPayingTokenOptionalInterface, Ownable {
  using SafeMath for uint256;
  using SafeMathUint for uint256;
  using SafeMathInt for int256;

  // With `magnitude`, we can properly distribute dividends even if the amount of received ether is small.
  // For more discussion about choosing the value of `magnitude`,

  uint256 constant internal MAGNITUDE = 2**128;

  uint256 internal magnifiedDividendPerShare;
 
  address constant public TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH

  constructor(){}
  // About dividendCorrection:
  // If the token balance of a `_user` is never changed, the dividend of `_user` can be computed with:
  //   `dividendOf(_user) = dividendPerShare * balanceOf(_user)`.
  // When `balanceOf(_user)` is changed (via minting/burning/transferring tokens),
  //   `dividendOf(_user)` should not be changed,
  //   but the computed value of `dividendPerShare * balanceOf(_user)` is changed.
  // To keep the `dividendOf(_user)` unchanged, we add a correction term:
  //   `dividendOf(_user) = dividendPerShare * balanceOf(_user) + dividendCorrectionOf(_user)`,
  //   where `dividendCorrectionOf(_user)` is updated whenever `balanceOf(_user)` is changed:
  //   `dividendCorrectionOf(_user) = dividendPerShare * (old balanceOf(_user)) - (new balanceOf(_user))`.
  // So now `dividendOf(_user)` returns the same value before and after `balanceOf(_user)` is changed.
  mapping(address => int256) internal magnifiedDividendCorrections;
  mapping(address => uint256) internal withdrawnDividends;
  
  mapping (address => uint256) public holderBalance;
  uint256 public totalBalance;

  uint256 public totalDividendsDistributed;

  /// @dev Distributes dividends whefnever ether is paid to this contract.
  receive() external payable {
    distributeDividends();
  }

  /// @notice Distributes ether to token holders as dividends.
  /// @dev It reverts if the total supply of tokens is 0.
  /// It emits the `DividendsDistributed` event if the amount of received ether is greater than 0.
  /// About undistributed ether:
  ///   In each distribution, there is a small amount of ether not distributed,
  ///     the magnified amount of which is
  ///     `(msg.value * magnitude) % totalSupply()`.
  ///   With a well-chosen `magnitude`, the amount of undistributed ether
  ///     (de-magnified) in a distribution can be less than 1 wei.
  ///   We can actually keep track of the undistributed ether in a distribution
  ///     and try to distribute it in the next distribution,
  ///     but keeping track of such data on-chain costs much more than
  ///     the saved ether, so we don't do that.
    
  function distributeDividends() public override payable {
    require(false, "Cannot send eth directly to tracker as it is unrecoverable"); // 
  }
  
  function distributeTokenDividends(uint256 amount) public onlyOwner {
    require(totalBalance > 0);

    if (amount > 0) {
      magnifiedDividendPerShare = magnifiedDividendPerShare.add(
        (amount).mul(MAGNITUDE) / totalBalance
      );
      emit DividendsDistributed(msg.sender, amount);

      totalDividendsDistributed = totalDividendsDistributed.add(amount);
    }
  }

  /// @notice Withdraws the ether distributed to the sender.
  /// @dev It emits a `DividendWithdrawn` event if the amount of withdrawn ether is greater than 0.
  function _withdrawDividendOfUser(address payable user) internal returns (uint256) {
    uint256 _withdrawableDividend = withdrawableDividendOf(user);
    if (_withdrawableDividend > 0) {
      withdrawnDividends[user] = withdrawnDividends[user].add(_withdrawableDividend);
      emit DividendWithdrawn(user, _withdrawableDividend);
      bool success = IERC20(TOKEN).transfer(user, _withdrawableDividend);

      if(!success) {
        withdrawnDividends[user] = withdrawnDividends[user].sub(_withdrawableDividend);
        return 0;
      }

      return _withdrawableDividend;
    }
    return 0;
  }

  /// @notice View the amount of dividend in wei that an address can withdraw.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` can withdraw.
  function dividendOf(address _owner) public view override returns(uint256) {
    return withdrawableDividendOf(_owner);
  }

  /// @notice View the amount of dividend in wei that an address can withdraw.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` can withdraw.
  function withdrawableDividendOf(address _owner) public view override returns(uint256) {
    return accumulativeDividendOf(_owner).sub(withdrawnDividends[_owner]);
  }

  /// @notice View the amount of dividend in wei that an address has withdrawn.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` has withdrawn.
  function withdrawnDividendOf(address _owner) public view override returns(uint256) {
    return withdrawnDividends[_owner];
  }

  /// @notice View the amount of dividend in wei that an address has earned in total.
  /// @dev accumulativeDividendOf(_owner) = withdrawableDividendOf(_owner) + withdrawnDividendOf(_owner)
  /// = (magnifiedDividendPerShare * balanceOf(_owner) + magnifiedDividendCorrections[_owner]) / magnitude
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` has earned in total.
  function accumulativeDividendOf(address _owner) public view override returns(uint256) {
    return magnifiedDividendPerShare.mul(holderBalance[_owner]).toInt256Safe()
      .add(magnifiedDividendCorrections[_owner]).toUint256Safe() / MAGNITUDE;
  }

  /// @dev Internal function that increases tokens to an account.
  /// Update magnifiedDividendCorrections to keep dividends unchanged.
  /// @param account The account that will receive the created tokens.
  /// @param value The amount that will be created.
  function _increase(address account, uint256 value) internal {
    magnifiedDividendCorrections[account] = magnifiedDividendCorrections[account]
      .sub( (magnifiedDividendPerShare.mul(value)).toInt256Safe() );
  }

  /// @dev Internal function that reduces an amount of the token of a given account.
  /// Update magnifiedDividendCorrections to keep dividends unchanged.
  /// @param account The account whose tokens will be burnt.
  /// @param value The amount that will be burnt.
  function _reduce(address account, uint256 value) internal {
    magnifiedDividendCorrections[account] = magnifiedDividendCorrections[account]
      .add( (magnifiedDividendPerShare.mul(value)).toInt256Safe() );
  }

  function _setBalance(address account, uint256 newBalance) internal {
    uint256 currentBalance = holderBalance[account];
    holderBalance[account] = newBalance;
    if(newBalance > currentBalance) {
      uint256 increaseAmount = newBalance.sub(currentBalance);
      _increase(account, increaseAmount);
      totalBalance += increaseAmount;
    } else if(newBalance < currentBalance) {
      uint256 reduceAmount = currentBalance.sub(newBalance);
      _reduce(account, reduceAmount);
      totalBalance -= reduceAmount;
    }
  }
}

contract DividendTracker is DividendPayingToken {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;

    mapping (address => bool) public excludedFromDividends;

    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait = 3600;
    uint256 public constant minimumTokenBalanceForDividends = 1_000_000 * (10**18); //must hold 1000+ tokens;

    event ExcludeFromDividends(address indexed account);
    event IncludeInDividends(address indexed account);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event Claim(address indexed account, uint256 amount, bool indexed automatic);

    constructor() {}

    function excludeFromDividends(address account) external onlyOwner {
        excludedFromDividends[account] = true;

        _setBalance(account, 0);
        tokenHoldersMap.remove(account);

        emit ExcludeFromDividends(account);
    }
    
    function includeInDividends(address account) external onlyOwner {
        require(excludedFromDividends[account]);
        excludedFromDividends[account] = false;

        emit IncludeInDividends(account);
    }

    function updateClaimWait(uint256 newClaimWait) external onlyOwner {        
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }

    function getLastProcessedIndex() external view returns(uint256) {
        return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }

    function getAccount(address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable) {
        account = _account;
        index = tokenHoldersMap.getIndexOfKey(account);
        iterationsUntilProcessed = -1;
        if(index >= 0) {
            if(uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex ?
                                                        tokenHoldersMap.keys.length.sub(lastProcessedIndex) :
                                                        0;


                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }
        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);
        lastClaimTime = lastClaimTimes[account];
        nextClaimTime = lastClaimTime > 0 ?
                                    lastClaimTime.add(claimWait) :
                                    0;
        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ?
                                                    nextClaimTime.sub(block.timestamp) :
                                                    0;
    }

    function getAccountAtIndex(uint256 index)
        public view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        if(index >= tokenHoldersMap.size()) {
            return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
        }
        address account = tokenHoldersMap.getKeyAtIndex(index);
        return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
        if(lastClaimTime > block.timestamp)  {
            return false;
        }
        return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function setBalance(address payable account, uint256 newBalance) external onlyOwner {
        if(excludedFromDividends[account]) {
            return;
        }
        if(newBalance >= minimumTokenBalanceForDividends) {
            _setBalance(account, newBalance);
            tokenHoldersMap.set(account, newBalance);
            
            uint256 lastClaimTime = lastClaimTimes[account];
            if(lastClaimTime == 0){
                lastClaimTimes[account] = block.timestamp;
            }
            else if(canAutoClaim(lastClaimTime)){
                processAccount(account, false);
            }            
        }
        else {
            _setBalance(account, 0);
            tokenHoldersMap.remove(account);
        }
    }
    
    function process(uint256 gas) public returns (uint256, uint256, uint256) {
        uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

        if(numberOfTokenHolders == 0) {
            return (0, 0, lastProcessedIndex);
        }
        uint256 _lastProcessedIndex = lastProcessedIndex;
        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();
        uint256 iterations = 0;
        uint256 claims = 0;

        while(gasUsed < gas && iterations < numberOfTokenHolders) {
            _lastProcessedIndex++;

            if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
                _lastProcessedIndex = 0;
            }
            address account = tokenHoldersMap.keys[_lastProcessedIndex];
            if(canAutoClaim(lastClaimTimes[account])) {
                if(processAccount(payable(account), true)) {
                    claims++;
                }
            }
            iterations++;
            uint256 newGasLeft = gasleft();
            if(gasLeft > newGasLeft) {
                gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
            }
            gasLeft = newGasLeft;
        }
        lastProcessedIndex = _lastProcessedIndex;
        return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address payable account, bool automatic) public onlyOwner returns (bool) {
        uint256 amount = _withdrawDividendOfUser(account);
        if(amount > 0) {
            lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
            return true;
        }
        return false;
    }
}
