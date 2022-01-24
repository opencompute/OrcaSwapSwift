//
//  OrcaSwapSwapTests.swift
//  
//
//  Created by Chung Tran on 19/10/2021.
//

import Foundation
import XCTest
import RxSwift
@testable import SolanaSwift
@testable import OrcaSwapSwift

class OrcaSwapSwapTests: XCTestCase {
    // MARK: - Properties
    var solanaSDK: SolanaSDK!
    var orcaSwap: OrcaSwap!
    
    var poolsRepository: [String: OrcaSwap.Pool]!
    
    // MARK: - Setup
    override func setUpWithError() throws {
        try super.setUpWithError()
        poolsRepository = try JSONDecoder().decode([String: OrcaSwap.Pool].self, from: OrcaSwap.getFileFrom(type: "pools", network: "mainnet"))
    }
    
    func setUp(testJSONFile: String, testName: String) throws {
        let test = try getDataFromJSONTestResourceFile(fileName: testJSONFile, decodedTo: [String: SwapTest].self)[testName]!
        
        let accountStorage = InMemoryAccountStorage()
        
        let network = SolanaSDK.Network.mainnetBeta
        let orcaSwapNetwork = network == .mainnetBeta ? "mainnet": network.cluster
        
        solanaSDK = SolanaSDK(
            endpoint: .init(address: test.endpoint, network: network, additionalQuery: test.endpointAdditionalQuery),
            accountStorage: accountStorage
        )
        
        let account = try SolanaSDK.Account(
            phrase: test.seedPhrase.components(separatedBy: " "),
            network: network
        )
        try accountStorage.save(account)
        
        orcaSwap = OrcaSwap(
            apiClient: OrcaSwap.MockAPIClient(network: orcaSwapNetwork),
            solanaClient: solanaSDK,
            accountProvider: solanaSDK,
            notificationHandler: solanaSDK
        )
        
        _ = orcaSwap.load().toBlocking().materialize()
    }
    
    override func tearDownWithError() throws {
        solanaSDK = nil
        orcaSwap = nil
    }
    
    // MARK: - Helper
    struct RawPool {
        init(name: String, reversed: Bool = false) {
            self.name = name
            self.reversed = reversed
        }
        
        let name: String
        let reversed: Bool
    }
    
    func fillPoolsBalancesAndSwap(
        fromWalletPubkey: String,
        toWalletPubkey: String?,
        bestPoolsPair: [RawPool],
        amount: Double,
        slippage: Double,
        isSimulation: Bool
    ) throws -> Single<OrcaSwap.SwapResponse> {
        let bestPoolsPair = try Single.zip(
            bestPoolsPair.map { rawPool -> Single<OrcaSwap.Pool> in
                var pool = poolsRepository[rawPool.name]!
                if rawPool.reversed {
                    pool = pool.reversed
                }
                return pool.filledWithUpdatedBalances(solanaClient: solanaSDK)
            }
        ).toBlocking().first()!
        
        let swapSimulation = orcaSwap.swap(
            fromWalletPubkey: fromWalletPubkey,
            toWalletPubkey: toWalletPubkey,
            bestPoolsPair: bestPoolsPair,
            amount: amount,
            slippage: 0.5,
            isSimulation: isSimulation
        )
        
        return swapSimulation
    }
}
