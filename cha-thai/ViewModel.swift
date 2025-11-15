//
//  ViewModel.swift
//  cha-thai
//
//  Created by Sanpawat Sewsuwan on 15/11/2568 BE.
//

import Foundation
import FoundationModels
import Playgrounds

@Generable
struct Game: Identifiable {
  let id: UUID = UUID()

  @Guide(.count(10))
  var words: [String]
}

@Observable
class ViewModel {

  var result: Game?

  func requestWords(keywords: [String]) async throws {
    let simple =
      "Give me 10 short fun and interesting words that relavant to these following keywords; \(keywords.joined(separator: ", "))"
    let session = LanguageModelSession()
    result = try await session.respond(to: simple, generating: Game.self).content
    //        let stream = session.streamResponse(to: simple, generating: Story.self)
    //
    //        for try await partial in stream {
    //            result = partial.content
    //        }
  }
}
