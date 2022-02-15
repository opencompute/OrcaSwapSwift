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
    
    override func tearDownWithError() throws {
        solanaSDK = nil
        orcaSwap = nil
    }
    
    // MARK: - Direct swap
    func testDirectSwapSOLToCreatedSPL() throws {
        try doTest(testJSONFile: "direct-swap-tests", testName: "solToCreatedSpl", isSimulation: true)
    }
    
    func testDirectSwapSOLToNonCreatedSPL() throws {
        try doTest(testJSONFile: "direct-swap-tests", testName: "solToNonCreatedSpl", isSimulation: true)
    }
    
    func testDirectSwapSPLToSOL() throws {
        try doTest(testJSONFile: "direct-swap-tests", testName: "splToSol", isSimulation: true)
    }
    
    func testDirectSwapSPLToCreatedSPL() throws {
        try doTest(testJSONFile: "direct-swap-tests", testName: "splToCreatedSpl", isSimulation: true)
    }
    
    func testDirectSwapSPLToNonCreatedSPL() throws {
        try doTest(testJSONFile: "direct-swap-tests", testName: "splToNonCreatedSpl", isSimulation: true)
    }
    
    // MARK: - Transitive swap
    func testTransitiveSwapSOLToCreatedSPL() throws {
        try doTest(testJSONFile: "transitive-swap-tests", testName: "solToCreatedSpl", isSimulation: true)
    }
    
    func testTransitiveSwapSOLToNonCreatedSPL() throws {
        let test = try doTest(testJSONFile: "transitive-swap-tests", testName: "solToNonCreatedSpl", isSimulation: true)
        
        try closeAssociatedToken(mint: test.toMint)
    }

    func testTransitiveSwapSPLToSOL() throws {
        try doTest(testJSONFile: "transitive-swap-tests", testName: "splToSol", isSimulation: true)
    }
    
    func testTransitiveSwapSPLToCreatedSPL() throws {
        try doTest(testJSONFile: "transitive-swap-tests", testName: "splToCreatedSpl", isSimulation: true)
    }
    
    func testTransitiveSwapSPLToNonCreatedSPL() throws {
        let test = try doTest(testJSONFile: "transitive-swap-tests", testName: "splToNonCreatedSpl", isSimulation: true)
        
        try closeAssociatedToken(mint: test.toMint)
    }
    
    
    // MARK: - Helpers
    @discardableResult
    func doTest(testJSONFile: String, testName: String, isSimulation: Bool) throws -> SwapTest {
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
        
        let preparedTransactions = try fillPoolsBalancesAndSwap(
            fromWalletPubkey: test.sourceAddress,
            toWalletPubkey: test.destinationAddress,
            bestPoolsPair: test.poolsPair,
            amount: test.inputAmount,
            slippage: test.slippage,
            isSimulation: isSimulation
        ).toBlocking().first()!
        
        let request: Single<String>
        if preparedTransactions.count == 1 {
            request = solanaSDK.serializeAndSend(
                preparedTransaction: preparedTransactions[0],
                isSimulation: true
            )
        } else if preparedTransactions.count == 2 {
            request = solanaSDK.serializeAndSend(
                preparedTransaction: preparedTransactions[0],
                isSimulation: false
            )
                .flatMapCompletable { [weak self] txid in
                    guard let self = self else {throw OrcaSwapError.unknown}
                    return self.orcaSwap.notificationHandler.waitForConfirmation(signature: txid)
                }
                .andThen(
                    solanaSDK.serializeAndSend(
                        preparedTransaction: preparedTransactions[1],
                        isSimulation: true
                    )
                )
        } else {
            fatalError()
        }
        
        XCTAssertNoThrow(try request.toBlocking().first())
        return test
    }
    
    func closeAssociatedToken(mint: String) throws {
        let associatedTokenAddress = try SolanaSDK.PublicKey.associatedTokenAddress(
            walletAddress: solanaSDK.accountStorage.account!.publicKey,
            tokenMintAddress: try SolanaSDK.PublicKey(string: mint)
        )
        
        let _ = try solanaSDK.closeTokenAccount(
            tokenPubkey: associatedTokenAddress.base58EncodedString
        )
            .retry { errors in
                errors.enumerated().flatMap{ (index, error) -> Observable<Int64> in
                    if error.readableDescription == "InvalidAccountData" {
                        return .timer(.seconds(1), scheduler: MainScheduler.instance)
                    }
                    return .error(error)
                }
            }
            .toBlocking().first()
    }
    
    // MARK: - Helper
    struct RawPool: Codable {
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
    ) throws -> Single<[SolanaSDK.PreparedTransaction]> {
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
            feePayer: nil,
            slippage: 0.5
        )
        
        return swapSimulation
    }
}
