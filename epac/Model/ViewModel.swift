//
//  ViewModel.swift
//  epac
//
//  Created by Sunny on 2024-12-12.
//

import Foundation
import SwiftData

actor ViewModel: ObservableObject {
	private lazy var fetch = Fetch(modelContainer: modelContainer)
	private var modelContainer: ModelContainer
	init(modelContainer: ModelContainer) {
		self.modelContainer = modelContainer
	}
}
