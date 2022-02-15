//
//  File.swift
//  
//
//  Created by Chung Tran on 15/02/2022.
//

import Foundation

extension OrcaSwap {
    public struct PreparedSwapTransaction {
        public let instructions: [TransactionInstruction]
        public let signers: [Account]
        public let accountCreationFee: Lamports
    }
}
