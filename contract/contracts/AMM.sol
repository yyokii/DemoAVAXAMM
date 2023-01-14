// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract AMM {
    IERC20 tokenX; // ERC20を実装したコントラクト
    IERC20 tokenY; // ERC20を実装したコントラクト
    /*
    本プロジェクトで使うシェアという言葉は, 流動性の提供者がプールにどのくらいのトークンを預けているのかを表す数値を指します。
    DEXで用意されていることが多いLPトークンと同じ役目を果たします。
    */
    uint256 public totalShare; // シェアの総量
    mapping(address => uint256) public share; // 各ユーザのシェア
    mapping(IERC20 => uint256) public totalAmount; // プールにロックされた各トークンの量

    uint256 public constant PRECISION = 1_000_000; // シェアの精度に使用する定数(= 6桁)

    // プールに使えるトークンを指定します。
    constructor(IERC20 _tokenX, IERC20 _tokenY) {
        tokenX = _tokenX;
        tokenY = _tokenY;
    }

    // プールに流動性があり, 使用可能であることを確認します。
    modifier activePool() {
        require(totalShare > 0, "Zero Liquidity");
        _;
    }

    // スマートコントラクトが扱えるトークンであることを確認します。
    modifier validToken(IERC20 _token) {
        require(
            _token == tokenX || _token == tokenY,
            "Token is not in the pool"
        );
        _;
    }

    // スマートコントラクトが扱えるトークンであることを確認します。
    modifier validTokens(IERC20 _tokenX, IERC20 _tokenY) {
        require(
            _tokenX == tokenX || _tokenY == tokenY,
            "Token is not in the pool"
        );
        require(
            _tokenY == tokenX || _tokenY == tokenY,
            "Token is not in the pool"
        );
        require(_tokenX != _tokenY, "Tokens should be different!");
        _;
    }

    // 引数のトークンとペアのトークンのコントラクトを返します。
    function pairToken(IERC20 token)
        private
        view
        validToken(token)
        returns (IERC20)
    {
        if (token == tokenX) {
            return tokenY;
        }
        return tokenX;
    }

    // 引数のトークンの量に値するペアのトークンの量を返します。
    function getEquivalentToken(IERC20 _inToken, uint256 _amountIn)
        public
        view
        activePool
        validToken(_inToken)
        returns (uint256)
    {
        IERC20 outToken = pairToken(_inToken);

        return (totalAmount[outToken] * _amountIn) / totalAmount[_inToken];
    }

        // プールに流動性を提供します。
    function provide(
        IERC20 _tokenX,
        uint256 _amountX,
        IERC20 _tokenY,
        uint256 _amountY
    ) external validTokens(_tokenX, _tokenY) returns (uint256) {
        require(_amountX > 0, "Amount cannot be zero!");
        require(_amountY > 0, "Amount cannot be zero!");

        uint256 newshare;
        if (totalShare == 0) {
            // 初期は100
            newshare = 100 * PRECISION;
        } else {
            uint256 shareX = (totalShare * _amountX) / totalAmount[_tokenX];
            uint256 shareY = (totalShare * _amountY) / totalAmount[_tokenY];
            require(
                shareX == shareY,
                "Equivalent value of tokens not provided..."
            );
            newshare = shareX;
        }

        require(
            newshare > 0,
            "Asset value less than threshold for contribution!"
        );

        _tokenX.transferFrom(msg.sender, address(this), _amountX);
        _tokenY.transferFrom(msg.sender, address(this), _amountY);

        totalAmount[_tokenX] += _amountX;
        totalAmount[_tokenY] += _amountY;

        totalShare += newshare;
        share[msg.sender] += newshare;

        return newshare;
    }

    // ユーザのシェアから引き出せるトークンの量を算出します。
    function getWithdrawEstimate(IERC20 _token, uint256 _share)
        public
        view
        activePool
        validToken(_token)
        returns (uint256)
    {
        require(_share <= totalShare, "Share should be less than totalShare");
        return (_share * totalAmount[_token]) / totalShare;
    }

    function withdraw(uint256 _share)
        external
        activePool
        returns (uint256, uint256)
    {
        require(_share > 0, "share cannot be zero!");
        require(_share <= share[msg.sender], "Insufficient share");

        uint256 amountTokenX = getWithdrawEstimate(tokenX, _share);
        uint256 amountTokenY = getWithdrawEstimate(tokenY, _share);

        share[msg.sender] -= _share;
        totalShare -= _share;

        totalAmount[tokenX] -= amountTokenX;
        totalAmount[tokenY] -= amountTokenY;

        tokenX.transfer(msg.sender, amountTokenX);
        tokenY.transfer(msg.sender, amountTokenY);

        return (amountTokenX, amountTokenY);
    }

     // swap元のトークン量からswap先のトークン量を算出
    function getSwapEstimateOut(IERC20 _inToken, uint256 _amountIn)
        public
        view
        activePool
        validToken(_inToken)
        returns (uint256)
    {
        IERC20 outToken = pairToken(_inToken);

        uint256 amountInWithFee = _amountIn * 997;

        uint256 numerator = amountInWithFee * totalAmount[outToken];
        uint256 denominator = totalAmount[_inToken] * 1000 + amountInWithFee;
        uint256 amountOut = numerator / denominator;

        return amountOut;
    }

    // swap先のトークン量からswap元のトークン量を算出
    function getSwapEstimateIn(IERC20 _outToken, uint256 _amountOut)
        public
        view
        activePool
        validToken(_outToken)
        returns (uint256)
    {
        require(
            _amountOut < totalAmount[_outToken],
            "Insufficient pool balance"
        );
        IERC20 inToken = pairToken(_outToken);

        uint256 numerator = 1000 * totalAmount[inToken] * _amountOut;
        uint256 denominator = 997 * (totalAmount[_outToken] - _amountOut);
        uint256 amountIn = numerator / denominator;

        return amountIn;
    }

     function swap(
        IERC20 _inToken,
        IERC20 _outToken,
        uint256 _amountIn
    ) external activePool validTokens(_inToken, _outToken) returns (uint256) {
        require(_amountIn > 0, "Amount cannot be zero!");

        uint256 amountOut = getSwapEstimateOut(_inToken, _amountIn);

        _inToken.transferFrom(msg.sender, address(this), _amountIn);
        totalAmount[_inToken] += _amountIn;
        totalAmount[_outToken] -= amountOut;
        _outToken.transfer(msg.sender, amountOut);
        return amountOut;
    }
}