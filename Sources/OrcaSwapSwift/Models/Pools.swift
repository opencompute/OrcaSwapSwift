//
//  File.swift
//  
//
//  Created by Chung Tran on 13/10/2021.
//

import Foundation
import RxSwift
import SolanaSwift

public typealias Pools = [String: Pool] // [poolId: string]: PoolConfig;
public typealias PoolsPair = [Pool]

private var balancesCache = [String: SolanaSDK.TokenAccountBalance]()
private let lock = NSLock()

extension Pools {
    func getPools(
        forRoute route: Route,
        fromTokenName: String,
        toTokenName: String,
        solanaClient: OrcaSwapSolanaClient
    ) -> Single<[Pool]> {
        guard route.count > 0 else {return .just([])}
        
        let requests = route.map {fixedPool(forPath: $0, solanaClient: solanaClient)}
        return Single.zip(requests).map {$0.compactMap {$0}}
            .map { pools in
                var pools = pools
                
                // modify orders
                if pools.count == 2 {
                    // reverse order of the 2 pools
                    // Ex: Swap from SOCN -> BTC, but paths are
                    // [
                    //     "BTC/SOL[aquafarm]",
                    //     "SOCN/SOL[stable][aquafarm]"
                    // ]
                    // Need to change to
                    // [
                    //     "SOCN/SOL[stable][aquafarm]",
                    //     "BTC/SOL[aquafarm]"
                    // ]
                    
                    if pools[0].tokenAName != fromTokenName && pools[0].tokenBName != fromTokenName {
                        let temp = pools[0]
                        pools[0] = pools[1]
                        pools[1] = temp
                    }
                }

                // reverse token A and token B in pool if needed
                for i in 0..<pools.count {
                    if i == 0 {
                        var pool = pools[0]
                        if pool.tokenAName.fixedTokenName != fromTokenName.fixedTokenName {
                            pool = pool.reversed
                        }
                        pools[0] = pool
                    }
                    
                    if i == 1 {
                        var pool = pools[1]
                        if pool.tokenBName.fixedTokenName != toTokenName.fixedTokenName {
                            pool = pool.reversed
                        }
                        pools[1] = pool
                    }
                }
                return pools
            }
    }
    
    private func fixedPool(
        forPath path: String, // Ex. BTC/SOL[aquafarm][stable]
        solanaClient: OrcaSwapSolanaClient
    ) -> Single<Pool?> {
        guard var pool = self[path] else {return .just(nil)}
        
        if path.contains("[stable]") {
            pool.isStable = true
        }
        
        // get balances
        lock.lock()
        let getBalancesRequest: Single<(SolanaSDK.TokenAccountBalance, SolanaSDK.TokenAccountBalance)>
        if let tokenABalance = pool.tokenABalance ?? balancesCache[pool.tokenAccountA],
           let tokenBBalance = pool.tokenBBalance ?? balancesCache[pool.tokenAccountB]
        {
            getBalancesRequest = .just((tokenABalance, tokenBBalance))
        } else {
            getBalancesRequest = Single.zip(
                solanaClient.getTokenAccountBalance(pubkey: pool.tokenAccountA, commitment: nil),
                solanaClient.getTokenAccountBalance(pubkey: pool.tokenAccountB, commitment: nil)
            )
        }
        lock.unlock()
        
        return getBalancesRequest
            .do(onSuccess: {
                lock.lock()
                balancesCache[pool.tokenAccountA] = $0
                balancesCache[pool.tokenAccountB] = $1
                lock.unlock()
            })
            .map {tokenABalane, tokenBBalance in
                pool.tokenABalance = tokenABalane
                pool.tokenBBalance = tokenBBalance
                
                return pool
            }
    }
}

public extension PoolsPair {
    func constructExchange(
        tokens: [String: TokenValue],
        solanaClient: OrcaSwapSolanaClient,
        owner: Account,
        fromTokenPubkey: String,
        intermediaryTokenAddress: String? = nil,
        toTokenPubkey: String?,
        amount: Lamports,
        slippage: Double,
        feePayer: PublicKey?,
        minRenExemption: Lamports
    ) -> Single<(AccountInstructions, Lamports /*account creation fee*/)> {
        guard count > 0 && count <= 2 else {return .error(OrcaSwapError.invalidPool)}
        
        if count == 1 {
            // direct swap
            return self[0]
                .constructExchange(
                    tokens: tokens,
                    solanaClient: solanaClient,
                    owner: owner,
                    fromTokenPubkey: fromTokenPubkey,
                    toTokenPubkey: toTokenPubkey,
                    amount: amount,
                    slippage: slippage,
                    feePayer: feePayer,
                    minRenExemption: minRenExemption
                )
                .map {($0.0, $0.1)}
        } else {
            // transitive swap
            guard let intermediaryTokenAddress = intermediaryTokenAddress else {
                return .error(OrcaSwapError.intermediaryTokenAddressNotFound)
            }

            return self[0]
                .constructExchange(
                    tokens: tokens,
                    solanaClient: solanaClient,
                    owner: owner,
                    fromTokenPubkey: fromTokenPubkey,
                    toTokenPubkey: intermediaryTokenAddress,
                    amount: amount,
                    slippage: slippage,
                    feePayer: feePayer,
                    minRenExemption: minRenExemption
                )
                .flatMap { pool0AccountInstructions, pool0AccountCreationFee -> Single<(AccountInstructions, Lamports /*account creation fee*/)> in
                    guard let amount = try self[0].getMinimumAmountOut(inputAmount: amount, slippage: slippage)
                    else {throw OrcaSwapError.unknown}
                    
                    return self[1].constructExchange(
                        tokens: tokens,
                        solanaClient: solanaClient,
                        owner: owner,
                        fromTokenPubkey: intermediaryTokenAddress,
                        toTokenPubkey: toTokenPubkey,
                        amount: amount,
                        slippage: slippage,
                        feePayer: feePayer,
                        minRenExemption: minRenExemption
                    )
                        .map {pool1AccountInstructions, pool1AccountCreationFee in
                            (.init(
                                account: pool1AccountInstructions.account,
                                instructions: pool0AccountInstructions.instructions + pool1AccountInstructions.instructions,
                                cleanupInstructions: pool0AccountInstructions.cleanupInstructions + pool1AccountInstructions.cleanupInstructions,
                                signers: pool0AccountInstructions.signers + pool1AccountInstructions.signers
                            ), pool0AccountCreationFee + pool1AccountCreationFee)
                        }
                }
                .map {($0.0, $0.1)}
        }
    }
    
    func getOutputAmount(
        fromInputAmount inputAmount: UInt64
    ) -> UInt64? {
        guard count > 0 else {return nil}
        let pool0 = self[0]
        guard let estimatedAmountOfPool0 = try? pool0.getOutputAmount(fromInputAmount: inputAmount)
        else {return nil}
        
        // direct
        if count == 1 {
            return estimatedAmountOfPool0
        }
        // transitive
        else {
            let pool1 = self[1]
            guard let estimatedAmountOfPool1 = try? pool1.getOutputAmount(fromInputAmount: estimatedAmountOfPool0)
            else {return nil}
            
            return estimatedAmountOfPool1
        }
    }
    
    func getInputAmount(
        fromEstimatedAmount estimatedAmount: UInt64
    ) -> UInt64? {
        guard count > 0 else {return nil}
        
        // direct
        if count == 1 {
            let pool0 = self[0]
            guard let inputAmountOfPool0 = try? pool0.getInputAmount(fromEstimatedAmount: estimatedAmount)
            else {return nil}
            return inputAmountOfPool0
        }
        // transitive
        else {
            let pool1 = self[1]
            guard let inputAmountOfPool1 = try? pool1.getInputAmount(fromEstimatedAmount: estimatedAmount)
            else {return nil}
            let pool0 = self[0]
            
            guard let inputAmountOfPool0 = try? pool0.getInputAmount(fromEstimatedAmount: inputAmountOfPool1)
            else {return nil}
            return inputAmountOfPool0
        }
    }
    
    func getInputAmount(
        minimumAmountOut: UInt64,
        slippage: Double
    ) -> UInt64? {
        guard count > 0 else {return nil}
        let pool0 = self[0]
        // direct
        if count == 1 {
            guard let inputAmount = try? pool0.getInputAmount(minimumReceiveAmount: minimumAmountOut, slippage: slippage)
            else {return nil}
            return inputAmount
        } else {
            let pool1 = self[1]
            guard let inputAmountPool1 = try? pool1.getInputAmount(minimumReceiveAmount: minimumAmountOut, slippage: slippage),
                  let inputAmountPool0 = try? pool0.getInputAmount(minimumReceiveAmount: inputAmountPool1, slippage: slippage)
            else {return nil}
            return inputAmountPool0
        }
    }
    
    func getMinimumAmountOut(
        inputAmount: UInt64,
        slippage: Double
    ) -> UInt64? {
        guard count > 0 else {return nil}
        let pool0 = self[0]
        // direct
        if count == 1 {
            guard let minimumAmountOut = try? pool0.getMinimumAmountOut(inputAmount: inputAmount, slippage: slippage)
            else {return nil}
            return minimumAmountOut
        }
        // transitive
        else {
            guard let outputAmountOfPool0 = try? pool0.getOutputAmount(fromInputAmount: inputAmount)
            else {return nil}
            
            let pool1 = self[1]
            guard let minimumAmountOut = try? pool1.getMinimumAmountOut(inputAmount: outputAmountOfPool0, slippage: slippage)
            else {return nil}
            return minimumAmountOut
        }
    }
    
    func getIntermediaryToken(
        inputAmount: UInt64,
        slippage: Double
    ) -> InterTokenInfo? {
        guard count > 1 else {return nil}
        let pool0 = self[0]
        return .init(
            tokenName: pool0.tokenBName,
            outputAmount: try? pool0.getOutputAmount(fromInputAmount: inputAmount),
            minAmountOut: try? pool0.getMinimumAmountOut(inputAmount: inputAmount, slippage: slippage),
            isStableSwap: self[1].isStable == true
        )
    }
    
    func calculateLiquidityProviderFees(
        inputAmount: Double,
        slippage: Double
    ) throws -> [UInt64] {
        guard count > 1 else {return []}
        let pool0 = self[0]
        
        guard let sourceDecimals = pool0.tokenABalance?.decimals else {throw OrcaSwapError.unknown}
        let inputAmount = inputAmount.toLamport(decimals: sourceDecimals)
                
        // 1 pool
        var result = [UInt64]()
        let fee0 = try pool0.calculatingFees(inputAmount)
        result.append(fee0)
        
        // 2 pool
        if count == 2 {
            let pool1 = self[1]
            if let inputAmount = try? pool0.getMinimumAmountOut(inputAmount: inputAmount, slippage: slippage) {
                let fee1 = try pool1.calculatingFees(inputAmount)
                result.append(fee1)
            }
        }
        return result
    }
    
    /// baseOutputAmount is the amount the user would receive if fees are included and slippage is excluded.
    private func getBaseOutputAmount(
        inputAmount: UInt64
    ) -> UInt64? {
        guard count > 0 else {return nil}
        let pool0 = self[0]
        guard let outputAmountOfPool0 = try? pool0.getBaseOutputAmount(inputAmount: inputAmount)
        else {return nil}
        
        // direct
        if count == 1 {
            return outputAmountOfPool0
        }
        // transitive
        else {
            let pool1 = self[1]
            guard let outputAmountOfPool1 = try? pool1.getBaseOutputAmount(inputAmount: outputAmountOfPool0)
            else {return nil}
            
            return outputAmountOfPool1
        }
    }
    
    /// price impact
    func getPriceImpact(
        inputAmount: UInt64,
        outputAmount: UInt64
    ) -> BDouble? {
        guard let baseOutputAmount = getBaseOutputAmount(inputAmount: inputAmount)
        else {return nil}
        
        let inputAmountDecimal = BDouble(inputAmount.convertToBalance(decimals: 0))
        let baseOutputAmountDecimal = BDouble(baseOutputAmount.convertToBalance(decimals: 0))
        
        return (baseOutputAmountDecimal - inputAmountDecimal) / baseOutputAmountDecimal * 100
    }
}

// MARK: - Helpers
private func createSolanaAccountAsync(network: Network) -> Single<Account> {
    .create { observer in
        do {
            let account = try Account(network: network)
            observer(.success(account))
        } catch {
            observer(.failure(error))
        }
        return Disposables.create()
    }
    .subscribe(on: ConcurrentDispatchQueueScheduler(qos: .userInteractive))
}

private extension String {
    /// Convert  SOL[aquafarm] to SOL
    var fixedTokenName: String {
        components(separatedBy: "[").first!
    }
}
