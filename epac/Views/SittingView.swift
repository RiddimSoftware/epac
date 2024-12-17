//
//  SittingView.swift
//  epac
//
//  Created by Sunny on 2024-12-13.
//

import SwiftUI

struct SittingView: View {
	let hansard: Hansard
	@Binding var selectedSubject: SubjectOfBusiness?
	var body: some View {
		List {
			ForEach(hansard.orders.sorted(by: { $0.hansardID < $1.hansardID }).filter { !$0.subjects.isEmpty }) { order in
				Section {
					ForEach(order.subjects.sorted(by: { $0.hansardID < $1.hansardID }).filter { !$0.speeches.isEmpty && !$0.speeches.first!.messages.isEmpty }) { subject in
						VStack {
							Text(subject.title)
						}
						.onTapGesture {
						 selectedSubject = subject
					 }
					}
				} header: {
					VStack {
						Text(order.catchline)
							.font(.system(size: 25, weight: .bold))
					}
				}
			}
		}
		.listStyle(.plain)
		.listSectionSpacing(20)
//		List(hansard.orders.filter { !$0.subjects.isEmpty }) { order in
//			ForEach(hansard.orders) { order in

//			}
//		}
	}
}
